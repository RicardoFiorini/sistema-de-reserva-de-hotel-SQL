# Sistema de Reserva de Hotel (SQL)
Uma solução de backend em SQL projetada para automatizar e organizar a **gestão de reservas, hóspedes e quartos** em um ambiente hoteleiro.
## Funcionalidades do Sistema

- **Gestão de Hóspedes:** Armazenamento de dados cadastrais e histórico de visitas.
- **Controle de Inventário:** Diferenciação de quartos por categoria, preço e status.
- **Lógica de Reservas:** Registro de datas de entrada (check-in) e saída (check-out).
- **Financeiro:** Cálculo de valores totais baseados em diárias.

## Status de Desenvolvimento
- [x] Modelagem Entidade-Relacionamento
- [x] Scripts DDL (Tabelas e Chaves)
- [x] Consultas de disponibilidade por data
- [ ] Implementar validação para evitar Overbooking
## Exemplo de Consulta (Quartos Ocupados)
O script abaixo exemplifica como verificar quais hóspedes estão atualmente no hotel:
```sql

SELECT hospedes.nome, quartos.numero, reservas.data_saida
FROM reservas
JOIN hospedes ON reservas.id_hospede = hospedes.id
JOIN quartos ON reservas.id_quarto = quartos.id
WHERE CURRENT_DATE BETWEEN reservas.data_entrada AND reservas.data_saida;

```
## Dica de Implementação
> [!TIP]
> Para garantir que um quarto não seja alugado duas vezes no mesmo período, utilize cláusulas de verificação de datas (NOT EXISTS) antes de confirmar o INSERT na tabela de reservas.
## Dicionário de Dados
| Tabela | Descrição |
| --- | --- |
| Hospedes | Informações de contato e identificação do cliente |
| Quartos | Detalhes físicos e preços das acomodações |
| Reservas | Vinculação entre cliente, quarto e período de estadia |
| Categorias | Definições de luxo e capacidade dos quartos |
