# Обоснование внедрения PgBouncer

**Источник:** лаб. 07 — «Управление соединениями»  
**Кто создаёт:** системный аналитик  
**Кому передаётся:** архитектор / тимлид / DBA для принятия решения о внедрении

---

## Зачем этот документ

Внедрение пулера соединений — архитектурное решение с ограничениями. Документ обосновывает потребность (проблема), описывает решение, измеряет эффект и честно перечисляет ограничения.

> **Запомнить:** PgBouncer в transaction mode решает проблему памяти (каждое соединение = процесс PostgreSQL = ~5–10 МБ), но вводит ограничения на PREPARE/EXECUTE, SET, advisory locks. Аналитик должен знать оба аспекта.

---

## Шаблон документа

```markdown
# Обоснование внедрения PgBouncer — eshop

## Проблема

Приложение eshop создаёт до 50 параллельных соединений к PostgreSQL.  
Каждое соединение = отдельный backend-процесс PostgreSQL.

Оценка потребления памяти:
- 50 соединений × 8 МБ/процесс = ~400 МБ только на backend-процессы
- При пиковой нагрузке (100+ соединений) сервер входит в swap

Симптом: `FATAL: remaining connection slots are reserved for non-replication superuser connections`  
Порог: `max_connections = 100`, фактически занято ~90.

## Предлагаемое решение

PgBouncer в режиме **transaction pooling**:
- pool_size = 10 (одновременных backend-процессов PostgreSQL)
- max_client_conn = 100 (клиентских соединений к PgBouncer)
- reserve_pool_size = 5

## Измерение эффекта (pgbench)

Нагрузочный тест: 50 клиентов, 30 секунд, транзакции TPC-B.

```bash
# Без PgBouncer (прямое подключение):
pgbench -U postgres -h localhost -p 5432 -c 50 -T 30 eshop

# С PgBouncer (через пулер):
pgbench -U postgres -h localhost -p 6432 -c 50 -T 30 eshop
```

| Метрика                    | Без PgBouncer | С PgBouncer | Изменение |
|----------------------------|---------------|-------------|-----------|
| Backend-процессов в PG     | 50            | 10          | -80%      |
| TPS (транзакций/сек)       |               |             |           |
| Latency avg, мс            |               |             |           |
| Памяти на соединения       | ~400 МБ       | ~80 МБ      | -80%      |

## Ограничения

| Функция PostgreSQL          | Проблема в transaction mode                  | Обходное решение           |
|-----------------------------|----------------------------------------------|----------------------------|
| PREPARE / EXECUTE           | Prepared statements не переживают переключение пула | Отключить в драйвере (preparedStatements=false) |
| SET / RESET (user-level)    | Настройки могут «утечь» к другому клиенту   | Использовать SET LOCAL в транзакции |
| LISTEN / NOTIFY             | Не работают                                  | Прямое соединение для событий |
| Временные таблицы           | Недоступны между транзакциями               | Использовать session mode |
| Advisory locks              | Теряются при возврате соединения в пул       | Прямое соединение или session mode |

## Вывод

PgBouncer в transaction mode рекомендуется для:
- Сервисов с коротковременными транзакциями (OLTP)
- Ситуаций, когда число клиентов >> max_connections

Не рекомендуется без дополнительной настройки для:
- ORM с prepared statements по умолчанию
- Сервисов, использующих LISTEN/NOTIFY
```

---

## Режимы PgBouncer — кратко

| Режим | Когда соединение возвращается в пул | Для чего |
|-------|-------------------------------------|----------|
| `session` | При отключении клиента | Совместимость; не экономит соединения |
| `transaction` | После каждой транзакции | OLTP; максимальная экономия |
| `statement` | После каждого оператора | Редко; несовместимо с мультистейтментами |

> **Запомнить:** в курсе используется **transaction mode**. Это режим по умолчанию в большинстве production-сред.

---

## Диагностика PgBouncer

```ini
; pgbouncer.ini — ключевые параметры
[databases]
eshop = host=127.0.0.1 port=5432 dbname=eshop

[pgbouncer]
pool_mode = transaction
max_client_conn = 100
default_pool_size = 10
reserve_pool_size = 5
reserve_pool_timeout = 5
listen_port = 6432
auth_type = scram-sha-256
```

```bash
# Статистика через psql (подключиться к pgbouncer как admin):
psql -h 127.0.0.1 -p 6432 -U pgbouncer pgbouncer
SHOW POOLS;     -- активные пулы и соединения
SHOW CLIENTS;   -- подключённые клиенты
SHOW SERVERS;   -- соединения к PostgreSQL
SHOW STATS;     -- статистика запросов
```

---

> **Связанные страницы:** [[concepts/connection-pooling]], [[tools/pgbouncer]], [[artifacts/db-health-report]]
