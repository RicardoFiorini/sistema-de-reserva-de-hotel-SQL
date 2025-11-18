-- 1. Configuração e Charset (Padrão Internacional)
CREATE DATABASE IF NOT EXISTS HotelEnterprise
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

USE HotelEnterprise;

-- 2. Tabela de Hóspedes (Com Documentação e Soft Delete)
CREATE TABLE Hospedes (
    hospede_id INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    documento VARCHAR(20) NOT NULL UNIQUE COMMENT 'CPF ou Passaporte',
    email VARCHAR(100) NOT NULL UNIQUE,
    telefone VARCHAR(20),
    data_nascimento DATE,
    vip BOOLEAN DEFAULT FALSE,
    criado_em DATETIME DEFAULT CURRENT_TIMESTAMP,
    atualizado_em DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deletado_em DATETIME DEFAULT NULL, -- Soft Delete
    
    INDEX idx_busca_hospede (nome, email)
);

-- 3. Tabela de Categorias de Quartos (Normalização de Preços)
CREATE TABLE CategoriasQuarto (
    categoria_id INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(50) NOT NULL, -- Ex: Suite Presidencial, Standard
    preco_base DECIMAL(10, 2) NOT NULL,
    capacidade_pessoas INT NOT NULL DEFAULT 2,
    descricao TEXT
);

-- 4. Tabela de Quartos (Físicos)
CREATE TABLE Quartos (
    quarto_id INT AUTO_INCREMENT PRIMARY KEY,
    categoria_id INT NOT NULL,
    numero VARCHAR(10) NOT NULL UNIQUE,
    andar INT NOT NULL,
    ativo BOOLEAN DEFAULT TRUE, -- Se está em manutenção ou não
    
    FOREIGN KEY (categoria_id) REFERENCES CategoriasQuarto(categoria_id),
    INDEX idx_quarto_categoria (categoria_id)
);

-- 5. Tabela de Reservas (O Coração do Sistema)
CREATE TABLE Reservas (
    reserva_id INT AUTO_INCREMENT PRIMARY KEY,
    codigo_reserva VARCHAR(10) NOT NULL UNIQUE COMMENT 'Código alfanumérico para o cliente (Ex: A1B2C)',
    hospede_id INT NOT NULL,
    quarto_id INT NOT NULL,
    
    -- Datas
    checkin_previsto DATETIME NOT NULL,
    checkout_previsto DATETIME NOT NULL,
    checkin_real DATETIME DEFAULT NULL,
    checkout_real DATETIME DEFAULT NULL,
    
    -- Financeiro (Snapshot: O preço fica gravado AQUI)
    preco_diaria_acordado DECIMAL(10, 2) NOT NULL,
    valor_total_previsto DECIMAL(10, 2) GENERATED ALWAYS AS (DATEDIFF(checkout_previsto, checkin_previsto) * preco_diaria_acordado) STORED,
    
    status ENUM('Pendente', 'Confirmada', 'CheckIn', 'CheckOut', 'Cancelada', 'NoShow') DEFAULT 'Pendente',
    criado_em DATETIME DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (hospede_id) REFERENCES Hospedes(hospede_id),
    FOREIGN KEY (quarto_id) REFERENCES Quartos(quarto_id),
    
    -- Índice Composto Vital para evitar Overbooking
    INDEX idx_conflito_datas (quarto_id, checkin_previsto, checkout_previsto),
    INDEX idx_status (status)
);

-- 6. Tabela de Pagamentos (Ledger Financeiro)
CREATE TABLE Pagamentos (
    pagamento_id INT AUTO_INCREMENT PRIMARY KEY,
    reserva_id INT NOT NULL,
    valor DECIMAL(10, 2) NOT NULL,
    metodo ENUM('CartaoCredito', 'Pix', 'Dinheiro', 'Transferencia') NOT NULL,
    status ENUM('Aprovado', 'Pendente', 'Estornado') DEFAULT 'Pendente',
    data_pagamento DATETIME DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (reserva_id) REFERENCES Reservas(reserva_id)
);

-- 7. Tabela de Auditoria (Compliance)
CREATE TABLE LogsSistema (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    acao VARCHAR(50),
    tabela_afetada VARCHAR(50),
    detalhes JSON, -- Uso moderno de JSON para flexibilidade
    data_log DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================
-- 🧠 LÓGICA AVANÇADA (TRIGGERS, VIEWS, PROCEDURES)
-- =========================================================

-- VIEW: Ocupação em Tempo Real
CREATE OR REPLACE VIEW v_MapaOcupacao AS
SELECT 
    q.numero AS quarto,
    c.nome AS categoria,
    CASE 
        WHEN r.reserva_id IS NOT NULL THEN 'OCUPADO'
        WHEN q.ativo = 0 THEN 'MANUTENÇÃO'
        ELSE 'LIVRE'
    END AS estado_atual,
    r.checkin_previsto,
    r.checkout_previsto,
    h.nome AS hospede_atual
FROM Quartos q
LEFT JOIN CategoriasQuarto c ON q.categoria_id = c.categoria_id
LEFT JOIN Reservas r ON q.quarto_id = r.quarto_id 
    AND r.status IN ('Confirmada', 'CheckIn')
    AND NOW() BETWEEN r.checkin_previsto AND r.checkout_previsto;

-- FUNCTION: Verificar Disponibilidade (Lógica de Intervalos)
-- Retorna 1 se livre, 0 se ocupado
DELIMITER //
CREATE FUNCTION fn_VerificarDisponibilidade(p_quarto_id INT, p_inicio DATETIME, p_fim DATETIME) 
RETURNS BOOLEAN
READS SQL DATA
BEGIN
    DECLARE v_conflitos INT;
    
    SELECT COUNT(*) INTO v_conflitos
    FROM Reservas
    WHERE quarto_id = p_quarto_id
      AND status NOT IN ('Cancelada', 'CheckOut') -- Ignora canceladas e já finalizadas
      -- A mágica da intersecção de datas:
      AND (
          (checkin_previsto < p_fim) AND (checkout_previsto > p_inicio)
      );
      
    RETURN (v_conflitos = 0);
END //
DELIMITER ;

-- PROCEDURE: Criar Reserva Segura (Atomicidade)
-- Substitui o INSERT direto para garantir que não haja overbooking no milissegundo
DELIMITER //
CREATE PROCEDURE sp_CriarReserva(
    IN p_hospede_id INT,
    IN p_quarto_id INT,
    IN p_data_in DATETIME,
    IN p_data_out DATETIME
)
BEGIN
    DECLARE v_preco DECIMAL(10,2);
    DECLARE v_disponivel BOOLEAN;
    
    -- 1. Verificar Disponibilidade usando a Função
    SET v_disponivel = fn_VerificarDisponibilidade(p_quarto_id, p_data_in, p_data_out);
    
    IF v_disponivel = FALSE THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERRO: Quarto indisponível para o período selecionado.';
    END IF;

    -- 2. Buscar Preço Atual (Snapshot)
    SELECT preco_base INTO v_preco 
    FROM Quartos q
    JOIN CategoriasQuarto c ON q.categoria_id = c.categoria_id
    WHERE q.quarto_id = p_quarto_id;

    -- 3. Inserir Reserva
    INSERT INTO Reservas (
        codigo_reserva, hospede_id, quarto_id, 
        checkin_previsto, checkout_previsto, preco_diaria_acordado, status
    ) VALUES (
        UPPER(SUBSTRING(MD5(RAND()), 1, 6)), -- Gera código aleatório ex: A3F9D1
        p_hospede_id, p_quarto_id, 
        p_data_in, p_data_out, v_preco, 'Confirmada'
    );
    
    SELECT LAST_INSERT_ID() as reserva_id, 'Reserva criada com sucesso' as mensagem;
END //
DELIMITER ;

-- TRIGGER: Auditoria de Cancelamento
DELIMITER //
CREATE TRIGGER trg_AuditoriaCancelamento
AFTER UPDATE ON Reservas
FOR EACH ROW
BEGIN
    IF NEW.status = 'Cancelada' AND OLD.status != 'Cancelada' THEN
        INSERT INTO LogsSistema (acao, tabela_afetada, detalhes)
        VALUES (
            'CANCELAMENTO', 
            'Reservas', 
            JSON_OBJECT(
                'reserva_id', OLD.reserva_id, 
                'valor_perdido', OLD.valor_total_previsto,
                'data_cancelamento', NOW()
            )
        );
    END IF;
END //
DELIMITER ;
