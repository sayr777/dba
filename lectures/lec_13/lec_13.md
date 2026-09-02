# Лекция 13. Rollback-стратегии. Обслуживание БД. Управление изменениями. Итог курса

**Неделя:** 13

---

## Цель лекции

По итогам лекции студент:

- знает три стратегии отката миграций и умеет выбрать подходящую;
- знает паттерны zero-downtime для опасных DDL-операций;
- знает инструменты планового обслуживания БД (`vacuumdb`, `reindexdb`, `pg_upgrade`);
- ориентируется в современном ландшафте СУБД и умеет составить roadmap внедрения новой технологии.

---

## 1. Три стратегии отката миграций

Когда деплой мигарции прошёл с ошибкой или привёл к неожиданному поведению приложения:

| Стратегия               | Суть                                               | Когда применять                           | Сложность |
|-------------------------|----------------------------------------------------|-------------------------------------------|-----------|
| **Forward rollback**    | Написать новую миграцию, исправляющую ситуацию     | Всегда пробовать в первую очередь         | Низкая    |
| **Undo-скрипты (U)**    | Выполнить заранее написанный `U{N}__*.sql`         | Когда undo написан до деплоя              | Средняя   |
| **PITR**                | Восстановить БД на момент до миграции              | Потеря данных; ничего другого нет         | Высокая   |

### 1.1. Forward rollback (рекомендуемый подход)

```sql
-- V003 добавила колонку с неверным дефолтом
-- Forward rollback: V004 исправляет ситуацию

-- V004__fix_orders_discount_default.sql
ALTER TABLE orders ALTER COLUMN discount SET DEFAULT 0.0;
UPDATE orders SET discount = 0.0 WHERE discount IS NULL;
```

Преимущества: история изменений сохранена, Flyway не знает об ошибке, риск минимален.

### 1.2. Undo-скрипты

```sql
-- V003__add_discount_column.sql (версионная миграция)
ALTER TABLE orders ADD COLUMN discount NUMERIC(5,2) DEFAULT 0.10;

-- U003__add_discount_column.sql (undo)
ALTER TABLE orders DROP COLUMN discount;
```

Undo выполняется вручную (или через Flyway Teams):
```bash
flyway undo   # откатить последнюю версионную миграцию
```

### 1.3. PITR как последний рубеж

Применяется, когда:
- Миграция уничтожила данные (DROP + commit).
- Forward rollback невозможен (нет backup копии данных до миграции).

```bash
# Восстановить на момент до миграции (см. лекцию 6)
recovery_target_time = '2024-09-01 14:29:00'  # 1 минуту до миграции
```

**Стоимость PITR:** потеря всех транзакций после точки восстановления, не только связанных с миграцией.

---

## 2. Zero-downtime паттерны

Некоторые DDL-операции блокируют таблицу. На production с высоким трафиком это недопустимо.

### 2.1. Опасные и безопасные операции

| Операция                                    | Блокировка                            | Альтернатива                              |
|---------------------------------------------|---------------------------------------|-------------------------------------------|
| `ADD COLUMN ... DEFAULT` (PostgreSQL < 11) | ACCESS EXCLUSIVE (долго)              | PostgreSQL 11+ — мгновенно               |
| `ADD COLUMN NOT NULL` без default           | ACCESS EXCLUSIVE + перепись таблицы   | 3-шаговый паттерн (см. ниже)             |
| `CREATE INDEX`                              | ShareLock (блокирует запись)          | `CREATE INDEX CONCURRENTLY`              |
| `DROP TABLE`                                | ACCESS EXCLUSIVE                      | 3-шаговый паттерн (переименование)       |
| `ALTER COLUMN TYPE`                         | ACCESS EXCLUSIVE + перепись           | Новая колонка + триггер миграции данных  |
| `RENAME COLUMN`                             | ACCESS EXCLUSIVE                      | 4-шаговый паттерн (см. ниже)            |

### 2.2. ADD NOT NULL без блокировки (3 шага)

```sql
-- Шаг 1 (V010): добавить колонку без NOT NULL
ALTER TABLE orders ADD COLUMN region TEXT;

-- Шаг 2 (V011): заполнить существующие строки + добавить CHECK constraint
UPDATE orders SET region = 'default' WHERE region IS NULL;
ALTER TABLE orders ADD CONSTRAINT orders_region_not_null
  CHECK (region IS NOT NULL) NOT VALID;
VALIDATE CONSTRAINT orders_region_not_null;  -- без ACCESS EXCLUSIVE

-- Шаг 3 (V012): установить NOT NULL (теперь PostgreSQL знает, что constraint проверен)
ALTER TABLE orders ALTER COLUMN region SET NOT NULL;
ALTER TABLE orders DROP CONSTRAINT orders_region_not_null;
```

### 2.3. RENAME COLUMN без блокировки (4 шага)

```sql
-- Шаг 1: добавить новую колонку
ALTER TABLE users ADD COLUMN full_name TEXT;

-- Шаг 2: синхронизировать (триггер или backfill)
UPDATE users SET full_name = name;

-- Шаг 3: переключить приложение на новую колонку

-- Шаг 4: удалить старую
ALTER TABLE users DROP COLUMN name;
```

### 2.4. DROP TABLE без блокировки (3 шага)

```sql
-- Шаг 1: переименовать (откатить легко)
ALTER TABLE orders RENAME TO orders_deprecated;

-- Шаг 2: убедиться, что приложение не использует (мониторинг логов)

-- Шаг 3: удалить
DROP TABLE orders_deprecated;
```

---

## 3. Плановое обслуживание БД

### 3.1. vacuumdb и reindexdb

Ручные операции для сценариев, когда autovacuum не справляется:

```bash
# Полный VACUUM ANALYZE всей базы (занять может часы)
vacuumdb --analyze --verbose -d myapp_prod

# Только одна таблица
vacuumdb --analyze --verbose -d myapp_prod -t orders

# VACUUM FULL (перепись таблицы; требует ACCESS EXCLUSIVE)
# Только в окно обслуживания!
vacuumdb --full -d myapp_prod -t orders_deprecated

# Пересборка индексов
reindexdb -d myapp_prod              # вся база
reindexdb -d myapp_prod -t orders    # одна таблица
reindexdb -d myapp_prod -i idx_orders_created  # один индекс

# REINDEX CONCURRENTLY (без блокировки)
psql -d myapp_prod -c "REINDEX TABLE CONCURRENTLY orders;"
```

### 3.2. pg_upgrade: обновление мажорной версии

`pg_upgrade` обновляет кластер PostgreSQL между мажорными версиями (например, 15 → 17) без полного pg_dump/restore.

```bash
# Проверить совместимость (без изменений)
pg_upgrade \
  -b /usr/lib/postgresql/15/bin \
  -B /usr/lib/postgresql/17/bin \
  -d /var/lib/postgresql/15/main \
  -D /var/lib/postgresql/17/main \
  --check

# Выполнить обновление
pg_upgrade \
  -b /usr/lib/postgresql/15/bin \
  -B /usr/lib/postgresql/17/bin \
  -d /var/lib/postgresql/15/main \
  -D /var/lib/postgresql/17/main
```

Альтернатива без downtime: логическая репликация на новую версию + переключение трафика.

---

## 4. Современный ландшафт СУБД

### 4.1. Категории СУБД в 2024–2025 годах

| Категория              | Представители                              | Когда применять                                  |
|------------------------|--------------------------------------------|--------------------------------------------------|
| **Реляционные (OLTP)** | PostgreSQL, MySQL, Oracle, SQL Server      | Транзакционные системы; сложные JOIN              |
| **NewSQL**             | CockroachDB, YugabyteDB, TiDB              | Горизонтальное масштабирование с SQL             |
| **Аналитические (OLAP)** | ClickHouse, DuckDB, BigQuery, Redshift   | BI, хранилища данных, агрегаты по миллиардам строк |
| **HTAP (гибридные)**   | TiDB, SingleStore                          | OLTP + аналитика без ETL                         |
| **Документные**        | MongoDB, CouchDB                           | Гибкая схема; JSON-документы                     |
| **Ключ-значение**      | Redis, DynamoDB                            | Кэш, сессии, очереди                             |
| **Графовые**           | Neo4j, Apache AGE (PG extension)           | Социальные сети, маршрутизация                   |
| **Временны́е ряды**    | TimescaleDB (PG), InfluxDB                 | IoT, метрики, трейдинг                           |
| **Векторные**          | pgvector (PG), Weaviate, Pinecone          | AI/ML, RAG, поиск по эмбеддингам                |

### 4.2. PostgreSQL как платформа расширений

| Расширение    | Функциональность              |
|---------------|-------------------------------|
| PostGIS       | Геопространственная СУБД      |
| pgvector      | Векторная СУБД                |
| TimescaleDB   | Time-series СУБД              |
| Apache AGE    | Графовая СУБД                 |
| Citus         | Горизонтальное масштабирование|

### 4.3. Roadmap внедрения новой технологии

```markdown
## Roadmap: внедрение [Технологии]

| Этап              | Срок      | Результат                                  |
|-------------------|-----------|--------------------------------------------|
| 1. Исследование   | 2 недели  | Выбор; оценка функциональность/зрелость/стоимость |
| 2. POC (dev)      | 4 недели  | Прототип; бенчмарк на реальных данных      |
| 3. Pilot (staging)| 4 недели  | Интеграция; нагрузочное тестирование       |
| 4. Production     | 2 недели  | Деплой; мониторинг; runbook               |
| 5. Ретроспектива  | 1 неделя  | Оценка результатов; обновление roadmap     |
```

---

## 5. Итоги курса

За 13 недель курс прошёл полный жизненный цикл работы с PostgreSQL глазами системного аналитика:

| Тема                                            | Неделя  | Результат                                                     |
|-------------------------------------------------|---------|---------------------------------------------------------------|
| Роль DBA, архитектура PostgreSQL                | 1–2     | Понимаю архитектуру; умею оформить тикет к DBA               |
| Роли, привилегии, схемы, RLS                    | 3–4     | Умею спроектировать ролевую модель и матрицу доступа         |
| Резервное копирование и восстановление          | 5–6     | Знаю RPO/RTO; понимаю PITR и failover runbook                |
| Мониторинг и анализ запросов                    | 7–8     | Умею читать pg_stat_*; понимаю EXPLAIN; знаю pgBadger        |
| Оптимизация, индексы, PgBouncer                 | 9       | Умею выбрать индекс; понимаю autovacuum; умею обосновать ПАО |
| Отказоустойчивость и репликация                 | 10      | Умею формулировать требования к HA                           |
| Информационная безопасность, pgAudit, 152-ФЗ   | 11      | Знаю требования ИБ; умею работать с pgAudit и TLS            |
| Flyway, Migration Plan, Runbook                 | 12      | Умею написать migration plan и runbook                       |
| Rollback-стратегии, обслуживание, ландшафт СУБД | 13      | Знаю zero-downtime паттерны; ориентируюсь в ландшафте СУБД  |

---

## 6. Итоги лекции

После этой лекции студент умеет:

- **Выбрать стратегию отката**: forward rollback (предпочтительно) → undo-скрипт → PITR (крайняя мера).
- **Применить zero-downtime паттерн**: ADD NOT NULL (3 шага), RENAME COLUMN (4 шага), `CREATE INDEX CONCURRENTLY`.
- **Запустить `vacuumdb --full` и `reindexdb --concurrently`** для ручного обслуживания.
- **Объяснить разницу** между мажорными и минорными обновлениями PostgreSQL; назвать методы (pg_upgrade vs логическая репликация).
- **Оценить новую СУБД** для задачи: OLTP vs OLAP vs векторный поиск vs временны́е ряды.

---

## Ссылки

- Flyway undo: https://flywaydb.org/documentation/command/undo
- pg_upgrade: https://www.postgresql.org/docs/current/pgupgrade.html
- vacuumdb: https://www.postgresql.org/docs/current/app-vacuumdb.html
- reindexdb: https://www.postgresql.org/docs/current/app-reindexdb.html
- Zero-downtime migrations: https://gist.github.com/jcoleman/1e6ad1bf8de454c166da94b67537758
- pgvector: https://github.com/pgvector/pgvector
