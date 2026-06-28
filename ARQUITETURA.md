# Guia de Arquitetura e Engenharia de Dados

Este documento explica os fundamentos arquiteturais do **Lead Streaming Service**. Ele foi escrito para ligar os conceitos clássicos de desenvolvimento Web (MVC, Bancos Relacionais) às práticas de **Sistemas Distribuídos e Engenharia de Dados** de alta performance.

---

## 1. Visão Geral: Por que não usar o MVC Clássico?

Em uma aplicação web tradicional (como um app Rails tradicional com PostgreSQL/Oracle):
1. O usuário faz uma ação (ex: clica em um botão).
2. O servidor Rails recebe a requisição.
3. O servidor abre uma transação no banco de dados relacional e insere/atualiza um registro.
4. O servidor responde `200 OK`.

### O Problema do Modelo Tradicional em Larga Escala:
Se o seu site tem 100.000 pessoas acessando simultaneamente e gerando cliques, page views e rolagens, o banco de dados relacional começará a travar. Gravações individuais (uma a uma) criam gargalos de rede, concorrência de escrita (locks de tabela) e esgotamento de conexões. 

### A Solução: Arquitetura Orientada a Eventos (EDA)
Este projeto usa uma arquitetura assíncrona desacoplada por mensageria:
* **Ingestão Ultrarápida**: O Rails apenas valida a estrutura em memória e envia o evento para uma fila (Redpanda/Kafka). O Rails responde `202 Accepted` em menos de **10 milissegundos**.
* **Processamento Assíncrono**: Um trabalhador em segundo plano (o *Consumer*) puxa os eventos da fila em lotes (batches) e grava em massa nos bancos de dados finais.

---

## 2. Validação Leve com `EventIngestionContract` (`dry-validation`)

No Rails clássico, usamos validações do `ActiveRecord` dentro dos Models (ex: `validates :email, presence: true`). 

### Por que não usamos ActiveRecord Validations aqui?
1. **Dependência do Banco**: Validations do ActiveRecord exigem que exista uma tabela correspondente no banco SQL da aplicação e uma conexão ativa para verificar restrições.
2. **Performance**: Ingestar eventos exige o mínimo de overhead possível. Inicializar um objeto ActiveRecord pesado para cada clique do usuário consome muita memória.

### O que é o `dry-validation`?
O `dry-validation` é uma biblioteca Ruby focada exclusivamente em validação de esquemas e regras de negócio complexas de forma extremamente rápida e isolada. 
* Ele roda **totalmente em memória RAM** sem encostar em bancos de dados.
* Ele valida tipos estruturais (ex: "o `lead_id` deve ser uma string em formato UUID válido", "o `timestamp` deve ser uma data ISO8601").
* Se o JSON enviado pela API falhar no contrato, rejeitamos a requisição no Controller imediatamente, sem desperdiçar recursos de rede enviando lixo para a fila de mensagens.

---

## 3. A Camada de Mensageria: `Producer` e `Consumer`

Para desacoplar a API dos bancos de dados, dividimos a responsabilidade entre duas entidades:

```
[Cliente] ➔ [API Controller] ➔ [Producer] ➔ █ Redpanda (Fila) █ ➔ [Consumer] ➔ [ClickHouse & Elasticsearch]
```

### O `Producer` (Produtor)
O `Producer` tem uma única responsabilidade: **enviar a mensagem para a fila o mais rápido possível**.
* Ele não sabe onde o evento será salvo e nem como ele será processado.
* Ele garante a **ordem das mensagens** enviando o `lead_id` como chave de partição. Isso garante que todos os eventos do lead "Ana Silva" caiam no mesmo processador, mantendo a ordem cronológica perfeita de suas ações.

### O `Consumer` (Consumidor)
O `Consumer` é um daemon (um processo de linha de comando contínuo) que roda de forma independente.
* Ele consome dados do Redpanda/Kafka usando **Micro-Batching** (lotes). Em vez de salvar cada clique individualmente, ele espera acumular (por exemplo) 1.000 cliques ou 2 segundos, e faz uma única gravação em lote.
* Se os bancos de dados ClickHouse ou Elasticsearch estiverem offline para manutenção, o `Consumer` apenas pausa o consumo. O Redpanda retém as mensagens com segurança. Assim que os bancos voltam, o `Consumer` processa a fila acumulada, garantindo **resiliência total**.

---

## 4. Onde estão os Models? (O Padrão Repository)

Em aplicações MVC com ActiveRecord, os models acumulam duas funções: representam a estrutura da tabela (dados) e executam queries (comportamento). 

Neste projeto, usamos o **Repository Pattern**:
1. **Dados Imutáveis**: Eventos de marketing são fatos históricos (ex: "Lead visitou o preço em 28/06"). Fatos históricos não são atualizados (`UPDATE`) ou deletados (`DELETE`). Eles são apenas inseridos (`INSERT`).
2. **Repositórios Dedicados**: `Clickhouse::LeadEventRepository` e `Elasticsearch::LeadEventRepository` contêm a lógica pura de inserção e consulta para cada tecnologia, mantendo o código limpo, testável e sem a rigidez do ActiveRecord.

---

## 5. Como Funcionam os Bancos de Dados (E a diferença para Postgres/Oracle)

Bancos relacionais (Postgres, Oracle) são **OLTP (Online Transaction Processing)**. Eles são perfeitos para transações financeiras onde cada registro é guardado linha a linha e exige consistência ACID estrita. Porém, para análise de milhões de dados, eles são lentos.

Neste projeto, combinamos duas tecnologias especializadas:

### A. ClickHouse (Banco de Dados Columnar)
Diferente do Postgres que armazena os dados agrupados por **linhas**, o ClickHouse armazena os dados agrupados por **colunas**.

| Linha | lead_id | event_type | payload | timestamp |
| :--- | :--- | :--- | :--- | :--- |
| **Row-based (Postgres)** | Armazena a linha inteira junta em disco. Para somar cliques, precisa ler o e-mail, payload, ID, etc. |
| **Column-based (ClickHouse)** | Guarda todos os `event_type` juntos, todas as datas juntas. |

* **Vantagem Analítica**: Se você quer rodar um relatório de "Quantos eventos do tipo `conversion` ocorreram na última semana?", o Clickhouse ignora as colunas `payload` e `lead_id` no disco. Ele lê apenas a coluna `event_type` e `timestamp`. Isso reduz a leitura de disco em até **95%**, executando consultas analíticas em milissegundos sobre bilhões de linhas.
* **ReplacingMergeTree**: Motor que detecta duplicatas com base na chave primária e as limpa em segundo plano de forma assíncrona.

### B. Elasticsearch (Motor de Busca Baseado em Documentos)
O Elasticsearch funciona através de um **Índice Invertido** (como o índice remissivo no final de um livro técnico).
* Em vez de procurar em cada linha se o campo `contact_email` contém `"ana"`, o Elasticsearch mantém uma lista mapeada: a palavra `"ana"` está associada aos registros `[ID 1, ID 4, ID 7]`.
* Isso permite consultas de texto e filtros dinâmicos instantâneos para o **Motor de Segmentação** (ex: encontrar leads que visitaram o `/pricing` E preencheram o formulário de eBook).

---

## 6. Outros Pontos Cruciais do Projeto

### Idempotência
Como trabalhamos em rede, existe o risco do cliente enviar o mesmo evento duas vezes devido a uma falha de conexão temporária (problema do *At-least-once delivery*). Para evitar duplicar a pontuação de leads, geramos um `event_id` (UUID) no cliente. O ClickHouse e o Elasticsearch usam esse ID para garantir que o mesmo evento nunca seja computado duas vezes.

### SLA de Ingestão de 5 Minutos
Monitoramos a latência calculando a diferença entre o momento em que o evento ocorreu (`created_at`) e quando ele foi indexado e ficou disponível para consulta (`processed_at`). Em nossa arquitetura assíncrona de alto fluxo, essa latência fica abaixo de **100 milissegundos**, superando com folga a meta de SLA de 5 minutos estabelecida para operações de marketing.
