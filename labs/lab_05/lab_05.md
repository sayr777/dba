# Лабораторная работа №5
## Мониторинг базы eshop: pg_stat_*, блокировки, журналирование

**Неделя:** 7  
**Ориентировочное время:** 2 занятия (≈ 4 ак. ч.)

---

## Цель работы

- Научиться читать ключевые системные представления PostgreSQL.
- Выявлять долгие запросы, блокировки, bloat таблиц.
- Настроить журналирование для последующего анализа медленных запросов.
- Составить отчёт о состоянии БД.

---

## Предварительные требования

- Завершена лаб. 02: база `eshop` с ролями существует.
- Прочитана лек. 07.

---

## Часть 1. pg_stat_activity: текущая активность

### 1.1. Общий обзор соединений

Подключитесь к `eshop` под `postgres` и выполните:

```sql
SELECT pid, usename, application_name, state,
       wait_event_type, wait_event,
       now() - query_start AS duration,
       LEFT(query, 80) AS query_preview
FROM   pg_stat_activity
WHERE  pid <> pg_backend_pid()
ORDER  BY duration DESC NULLS LAST;
```

Обратите внимание: скорее всего, вы увидите только `autovacuum launcher` и пустые соединения.

### 1.2. Симуляция долгой транзакции

Откройте **второе** окно psql / SQL-редактор в DBeaver и выполните (НЕ делайте COMMIT):

```sql
-- Второй сеанс: начать транзакцию и повесить её
BEGIN;
UPDATE orders SET status = 'processing' WHERE id = 1;
-- НЕ выполняем COMMIT — оставляем транзакцию открытой
```

В **первом** окне:

```sql
-- Найти зависшую транзакцию
SELECT pid, usename, state,
       now() - xact_start AS tx_duration,
       LEFT(query, 80) AS last_query
FROM   pg_stat_activity
WHERE  state = 'idle in transaction';
```

Запишите PID зависшей транзакции: ___

### 1.3. Симуляция блокировки

В **третьем** окне psql:

```sql
-- Попытаться обновить ту же строку — будет ждать
UPDATE orders SET status = 'shipped' WHERE id = 1;
-- Этот запрос ЗАВИСНЕТ
```

В **первом** окне:

```sql
-- Посмотреть блокировку
SELECT blocked.pid        AS blocked_pid,
       blocked.usename    AS blocked_user,
       blocker.pid        AS blocker_pid,
       blocker.usename    AS blocker_user,
       blocked.query      AS blocked_query
FROM   pg_stat_activity AS blocked
JOIN   pg_stat_activity AS blocker
       ON blocker.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE  cardinality(pg_blocking_pids(blocked.pid)) > 0;
```

### 1.4. Разрешить блокировку

```sql
-- Мягкое завершение зависшей транзакции
SELECT pg_cancel_backend(<PID из шага 1.2>);

-- Проверить: третий сеанс теперь должен завершить UPDATE
```

```
-- Вариант А: отменить ОЖИДАЮЩИЙ запрос (третий сеанс получит ошибку,
-- блокировщик останется жить)
SELECT pg_cancel_backend(<blocked_pid>);

-- Вариант Б: убить БЛОКИРОВЩИКА (транзакция откатится, блокировка снимется)
SELECT pg_terminate_backend(<blocker_pid>);
```

---

## Часть 2. Статистика таблиц и индексов

### 2.1. pg_stat_user_tables

```sql
SELECT relname,
       seq_scan, idx_scan,
       n_live_tup, n_dead_tup,
       ROUND(n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0) * 100, 1) AS dead_pct,
       last_autovacuum, last_autoanalyze
FROM   pg_stat_user_tables
ORDER  BY relname;
```

Запишите значения для таблицы `orders`: n_live_tup = ___, n_dead_tup = ___

### 2.2. Создать bloat искусственно

```sql
-- Создать мёртвые строки через UPDATE
UPDATE products SET description = 'обновлено' WHERE id IN (1,2,3);
UPDATE products SET description = NULL WHERE id IN (1,2,3);
-- Повторить 10 раз
DO $$
BEGIN
    FOR i IN 1..10 LOOP
        UPDATE products SET stock_qty = stock_qty + 1;
        UPDATE products SET stock_qty = stock_qty - 1;
    END LOOP;
END;
$$;
```

```sql
-- Посмотреть bloat
SELECT relname, n_live_tup, n_dead_tup,
       ROUND(n_dead_tup::numeric / NULLIF(n_live_tup+n_dead_tup,0)*100,1) AS dead_pct
FROM   pg_stat_user_tables
WHERE  relname = 'products';
-- dead_pct должен вырасти
```

### 2.3. Запустить VACUUM и проверить

```sql
VACUUM ANALYZE products;

-- Проверить снова
SELECT relname, n_dead_tup, last_vacuum
FROM   pg_stat_user_tables
WHERE  relname = 'products';
-- n_dead_tup должен упасть до 0
```

### 2.4. Cache hit ratio

```sql
SELECT SUM(blks_hit)::float / NULLIF(SUM(blks_hit) + SUM(blks_read), 0) * 100 AS cache_hit_pct
FROM   pg_stat_database
WHERE  datname = 'eshop';
```

Запишите значение: ___%. Если < 99% — обсудите с преподавателем причины.

---

## Часть 3. Настройка журналирования

### 3.1. Параметры logging в postgresql.conf

Найдите файл `postgresql.conf` (путь: выполните `SHOW config_file;`) и добавьте/измените:

```ini
logging_collector           = on
log_directory               = 'log'
log_filename                = 'postgresql-%Y-%m-%d.log'
log_rotation_age            = 1d

# Формат для pgBadger (понадобится в лаб. 06)
log_line_prefix             = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '

# Медленные запросы: логировать всё дольше 500 мс
log_min_duration_statement  = 500

# Полезные события
log_lock_waits              = on
log_temp_files              = 10240
log_autovacuum_min_duration = 250
```

Применить без перезапуска (для параметров, которые поддерживают `pg_reload_conf`):
```sql
SELECT pg_reload_conf();
SHOW log_min_duration_statement;    -- должно показать 500ms
```

### 3.2. Создать «медленный» запрос

```sql
-- Искусственная нагрузка: запрос без индекса
SELECT o.id, c.name, o.total_amount
FROM   orders o
JOIN   customers c ON o.customer_id = c.id
WHERE  c.email LIKE '%example%'
ORDER  BY o.total_amount DESC;
```

Найдите в лог-файле строку с этим запросом:
```bash
# Windows
type "C:\Program Files\PostgreSQL\17\data\log\postgresql-2024-09-01.log" | findstr "duration"

# Linux
grep "duration" /var/lib/postgresql/17/main/log/postgresql-$(date +%Y-%m-%d).log
```

---

## Часть 4. Отчёт о состоянии БД

Заполните шаблон (сохранить как `C:\backup\eshop\db_health_report.md`):

```markdown
## Отчёт о состоянии БД eshop

**Дата:** ___
**PostgreSQL version:** (SELECT version();) ___

### Соединения
- Всего соединений: ___
- Активных запросов: ___
- Idle in transaction: ___

### Кэш
- Cache hit ratio: ___%

### Bloat
| Таблица    | n_live_tup | n_dead_tup | dead_pct |
|------------|------------|------------|----------|
| customers  |            |            |          |
| orders     |            |            |          |
| order_items|            |            |          |

### Индексы
- Неиспользуемых индексов: ___ (запрос из лек. 07, раздел 4)

### Журналирование
- log_min_duration_statement: 500ms ✓
- log_lock_waits: on ✓
- Медленных запросов за последние 24 ч: ___

### Выводы и рекомендации
___ (заполнить самостоятельно)
```

---

## Чек-лист «работа зачтена»

- [ ] Симуляция блокировки выполнена: `pg_blocking_pids` показал блокировщика.
- [ ] `pg_cancel_backend` снял блокировку.
- [ ] Bloat создан и устранён через `VACUUM ANALYZE products`.
- [ ] `log_min_duration_statement = 500ms` применён; медленный запрос найден в логе.
- [ ] `db_health_report.md` заполнен.

---

## Самостоятельное задание

1. Напишите SQL-запрос, который выводит топ-5 таблиц по доле мёртвых строк.
2. Настройте `log_lock_waits = on`. Создайте блокировку, подождите 3 секунды, затем снимите. Найдите запись о блокировке в лог-файле.
3. Объясните: что означает `wait_event_type = 'Lock'` в `pg_stat_activity`?

---

## Ссылки

- pg_stat_activity: https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STAT-ACTIVITY-VIEW
- pg_blocking_pids: https://www.postgresql.org/docs/current/functions-info.html
- Журналирование: https://www.postgresql.org/docs/current/runtime-config-logging.html
- VACUUM: https://www.postgresql.org/docs/current/sql-vacuum.html
