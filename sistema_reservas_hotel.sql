-- Criação do banco de dados
CREATE DATABASE SistemaReservasHotel;
USE SistemaReservasHotel;

-- Tabela para armazenar informações dos hóspedes
CREATE TABLE Hospedes (
    hospede_id INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    telefone VARCHAR(20),
    data_nascimento DATE,
    data_registro DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY (email)
);

-- Tabela para armazenar informações dos quartos
CREATE TABLE Quartos (
    quarto_id INT AUTO_INCREMENT PRIMARY KEY,
    numero_quarto VARCHAR(10) NOT NULL UNIQUE,
    tipo ENUM('Simples', 'Duplo', 'Suite') NOT NULL,
    preco DECIMAL(10, 2) NOT NULL,
    status ENUM('Disponível', 'Reservado', 'Indisponível') DEFAULT 'Disponível'
);

-- Tabela para armazenar informações sobre reservas
CREATE TABLE Reservas (
    reserva_id INT AUTO_INCREMENT PRIMARY KEY,
    hospede_id INT NOT NULL,
    quarto_id INT NOT NULL,
    data_checkin DATE NOT NULL,
    data_checkout DATE NOT NULL,
    data_reserva DATETIME DEFAULT CURRENT_TIMESTAMP,
    status ENUM('Ativa', 'Concluída', 'Cancelada') DEFAULT 'Ativa',
    FOREIGN KEY (hospede_id) REFERENCES Hospedes(hospede_id) ON DELETE CASCADE,
    FOREIGN KEY (quarto_id) REFERENCES Quartos(quarto_id) ON DELETE CASCADE
);

-- Índices para melhorar a performance
CREATE INDEX idx_hospede_email ON Hospedes(email);
CREATE INDEX idx_quarto_tipo ON Quartos(tipo);
CREATE INDEX idx_quarto_status ON Quartos(status);
CREATE INDEX idx_reserva_hospede ON Reservas(hospede_id);
CREATE INDEX idx_reserva_quarto ON Reservas(quarto_id);

-- View para listar reservas com detalhes dos hóspedes e quartos
CREATE VIEW ViewReservas AS
SELECT r.reserva_id, h.nome AS hospede, q.numero_quarto, q.tipo, 
       r.data_checkin, r.data_checkout, r.status AS status_reserva
FROM Reservas r
JOIN Hospedes h ON r.hospede_id = h.hospede_id
JOIN Quartos q ON r.quarto_id = q.quarto_id;

-- Função para contar reservas ativas de um hóspede
DELIMITER //
CREATE FUNCTION ContarReservasAtivas(hospedeId INT) RETURNS INT
BEGIN
    DECLARE qtd INT;
    SELECT COUNT(*) INTO qtd FROM Reservas WHERE hospede_id = hospedeId AND status = 'Ativa';
    RETURN qtd;
END //
DELIMITER ;

-- Função para obter o total de receitas de reservas
DELIMITER //
CREATE FUNCTION TotalReceitas() RETURNS DECIMAL(10, 2)
BEGIN
    DECLARE total DECIMAL(10, 2);
    SELECT SUM(q.preco) INTO total
    FROM Reservas r
    JOIN Quartos q ON r.quarto_id = q.quarto_id
    WHERE r.status = 'Concluída';
    RETURN IFNULL(total, 0);
END //
DELIMITER ;

-- Trigger para atualizar o status do quarto ao criar uma reserva
DELIMITER //
CREATE TRIGGER Trigger_AntesInserirReserva
BEFORE INSERT ON Reservas
FOR EACH ROW
BEGIN
    DECLARE quartoStatus ENUM('Disponível', 'Reservado', 'Indisponível');
    SELECT status INTO quartoStatus FROM Quartos WHERE quarto_id = NEW.quarto_id;
    IF quartoStatus != 'Disponível' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quarto não disponível para reserva.';
    END IF;
END //
DELIMITER ;

-- Trigger para mudar o status do quarto após a reserva ser concluída
DELIMITER //
CREATE TRIGGER Trigger_AposConcluirReserva
AFTER UPDATE ON Reservas
FOR EACH ROW
BEGIN
    IF NEW.status = 'Concluída' AND OLD.status != 'Concluída' THEN
        UPDATE Quartos SET status = 'Disponível' WHERE quarto_id = NEW.quarto_id;
    END IF;
END //
DELIMITER ;

-- Inserção de exemplo de hóspedes
INSERT INTO Hospedes (nome, email, telefone, data_nascimento) VALUES 
('Pedro Almeida', 'pedro@example.com', '123456789', '1990-01-15'),
('Maria Oliveira', 'maria@example.com', '987654321', '1985-05-20');

-- Inserção de exemplo de quartos
INSERT INTO Quartos (numero_quarto, tipo, preco, status) VALUES 
('101', 'Simples', 100.00, 'Disponível'),
('102', 'Duplo', 150.00, 'Disponível'),
('201', 'Suite', 250.00, 'Indisponível');

-- Inserção de exemplo de reservas
INSERT INTO Reservas (hospede_id, quarto_id, data_checkin, data_checkout) VALUES 
(1, 1, '2024-11-10', '2024-11-15'),
(2, 2, '2024-11-12', '2024-11-14');

-- Selecionar todas as reservas
SELECT * FROM ViewReservas;

-- Contar reservas ativas para um hóspede específico
SELECT ContarReservasAtivas(1) AS reservas_ativas_hospede_1;

-- Obter o total de receitas de reservas concluídas
SELECT TotalReceitas() AS total_receitas;

-- Atualizar o status de uma reserva para concluída
UPDATE Reservas SET status = 'Concluída' WHERE reserva_id = 1;

-- Cancelar uma reserva (isso não altera o status do quarto)
UPDATE Reservas SET status = 'Cancelada' WHERE reserva_id = 2;

-- Excluir um hóspede (isso falhará se o hóspede tiver reservas ativas)
DELETE FROM Hospedes WHERE hospede_id = 1;

-- Excluir um quarto (isso falhará se o quarto tiver reservas ativas)
DELETE FROM Quartos WHERE quarto_id = 1;
