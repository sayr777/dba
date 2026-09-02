# Лекция 7. Мониторинг, сбор статистики, журналирование

**Неделя:** 7

---

## Цель лекции

По итогам лекции студент:

- знает ключевые системные представления PostgreSQL для мониторинга активности;
- умеет выявить долгие запросы, блокировки и деградацию кэша через `pg_stat_*`;
- знает, как настроить журналирование для последующего анализа;
- понимает, какие метрики передавать DBA при описании проблемы с производительностью.

---

## 1. Зачем мониторить БД

Мониторинг позволяет обнаружить проблему **до** того, как её заметит пользователь:

| Без мониторинга                             | С мониторингом                                     |
|---------------------------------------------|----------------------------------------------------|
| Узнаём о проблеме от пользователя           | Алерт за 10 минут до деградации                    |
| Непонятно, когда началось                   | Есть timeline и метрики на момент начала            |
| Тяжело воспроизвести                        | Логи и статистика сохранены                        |
| DBA ищет причину «вслепую»                  | DBA видит конкретный запрос / блокировку           |

**Три зоны мониторинга PostgreSQL:**
1. **Активность** — что происходит прямо сейчас (соединения, запросы, блокировки).
2. **Статистика** — накопленные данные об использовании таблиц, индексов, фоновых процессов.
3. **Журналы** — историческая запись событий для post-mortem анализа.

---

## 2. Активные соединения: pg_stat_activity

`pg_stat_activity` — главное представление для мониторинга текущей активности.

```sql
-- Все активные запросы (кроме собственного соединения)
SELECT pid, usename, application_name, state,
       wait_event_type, wait_event,
       now() - query_start AS duration,
       LEFT(query, 100) AS query_preview
FROM   pg_stat_activity
WHERE  pid <> pg_backend_pid()
ORDER  BY duration DESC NULLS LAST;
```

Ключевые столбцы:

| Столбец             | Описание                                                          |
|---------------------|-------------------------------------------------------------------|
| `pid`               | PID процесса backend                                              |
| `state`             | `active` / `idle` / `idle in transaction` / `fastpath function call` |
| `wait_event_type`   | Тип ожидания: `Lock`, `LWLock`, `IO`, `Client`, `IPC`            |
| `wait_event`        | Конкретное событие ожидания                                       |
| `query_start`       | Когда начался текущий запрос                                      |

### 2.1. Долгие запросы

```sql
-- Запросы дольше 5 минут
SELECT pid, usename, now() - query_start AS duration, state, query
FROM   pg_stat_activity
WHERE  state = 'active'
  AND  query_start < now() - INTERVAL '5 minutes'
ORDER  BY duration DESC;
```

### 2.2. Зависшие транзакции

```sql
-- idle in transaction дольше 10 минут — держат блокировки, мешают autovacuum
SELECT pid, usename, state,
       now() - xact_start AS transaction_duration,
       LEFT(query, 80) AS last_query
FROM   pg_stat_activity
WHERE  state = 'idle in transaction'
  AND  xact_start < now() - INTERVAL '10 minutes';
```

### 2.3. Блокировки

```sql
-- Кто кого блокирует
SELECT blocked.pid        AS blocked_pid,
       blocked.usename    AS blocked_user,
       blocker.pid        AS blocker_pid,
       blocker.usename    AS blocker_user,
       blocked.query      AS blocked_query,
       blocker.query      AS blocker_query
FROM   pg_stat_activity AS blocked
JOIN   pg_stat_activity AS blocker
       ON blocker.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE  cardinality(pg_blocking_pids(blocked.pid)) > 0;
```

### 2.4. Завершение зависшего процесса

```sql
SELECT pg_cancel_backend(pid);     -- мягкое завершение (текущая транзакция)
SELECT pg_terminate_backend(pid);  -- жёсткое завершение (только для DBA)
```

---

## 3. Статистика таблиц: pg_stat_user_tables

```sql
SELECT relname                                      AS table_name,
       seq_scan,
       idx_scan,
       n_live_tup,
       n_dead_tup,
       ROUND(n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0) * 100, 1) AS dead_pct,
       last_vacuum,
       last_autovacuum,
       last_analyze,
       last_autoanalyze
FROM   pg_stat_user_tables
ORDER  BY n_dead_tup DESC;
```

**На что обращать внимание:**

| Признак                                 | Интерпретация                               |
|-----------------------------------------|---------------------------------------------|
| `seq_scan` >> `idx_scan`                | Индекс не используется или его нет          |
| `n_dead_tup` / `n_live_tup` > 20%      | Bloat — много мёртвых версий; нужен VACUUM  |
| `last_autovacuum` — давно или NULL      | Autovacuum не справляется или отключён      |

---

## 4. Статистика индексов: pg_stat_user_indexes

```sql
SELECT relname   AS table_name,
       indexrelname AS index_name,
       idx_scan,            -- 0 = неиспользуемый кандидат на удаление
       idx_tup_read,
       idx_tup_fetch
FROM   pg_stat_user_indexes
ORDER  BY idx_scan ASC;
```

---

## 5. Состояние фоновых процессов: pg_stat_bgwriter

```sql
SELECT checkpoints_timed,    -- плановые checkpoint
       checkpoints_req,      -- внеплановые (много = увеличить checkpoint_completion_target)
       buffers_checkpoint,
       buffers_clean,
       buffers_backend,      -- много = shared_buffers мал (backend сам сбрасывает страницы)
       buffers_alloc
FROM   pg_stat_bgwriter;
```

---

## 6. Метрика кэша: cache hit ratio

```sql
SELECT SUM(blks_hit)::float / NULLIF(SUM(blks_hit) + SUM(blks_read), 0) * 100 AS cache_hit_pct
FROM   pg_stat_database;
```

| Значение  | Интерпретация                                                    |
|-----------|------------------------------------------------------------------|
| > 99%     | Отлично: данные в кэше                                           |
| 95–99%    | Приемлемо: часть данных читается с диска                         |
| < 95%     | Плохо: `shared_buffers` мал либо данных больше, чем памяти      |

---

## 7. Настройка журналирования

### 7.1. Ключевые параметры postgresql.conf

```ini
logging_collector              = on
log_directory                  = 'log'
log_filename                   = 'postgresql-%Y-%m-%d.log'
log_rotation_age               = 1d
log_rotation_size              = 100MB

# Формат строки (важен для pgBadger)
log_line_prefix                = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '

# Медленные запросы
log_min_duration_statement     = 1000   # запросы дольше 1 секунды

# Дополнительные события
log_lock_waits                 = on
log_temp_files                 = 10240  # временные файлы > 10 МБ
log_autovacuum_min_duration    = 250
log_connections                = on
log_disconnections             = on
```

---

## 8. Ключевые метрики и пороги

| Метрика                            | Как получить                                  | Порог тревоги       |
|------------------------------------|-----------------------------------------------|---------------------|
| Cache hit ratio                    | pg_stat_database                              | < 99%               |
| Активных соединений                | pg_stat_activity WHERE state='active'         | > 80% от max_connections |
| Долгих транзакций                  | pg_stat_activity WHERE state='idle in transaction' | > 5 мин        |
| Bloat (n_dead_tup / total)         | pg_stat_user_tables                           | > 20%               |
| Внеплановых checkpoint             | pg_stat_bgwriter (checkpoints_req)            | > 30% от checkpoints_timed |
| Ошибки архивирования               | pg_stat_archiver (failed_count)               | > 0                 |

---

## 9. Что передавать DBA при проблеме с производительностью

```markdown
## Отчёт о проблеме производительности

Среда: production
Время начала деградации: 2024-09-01 14:30 MSK
Симптом: запросы на создание заказа выполняются > 30 сек

Метрики на момент проблемы:
- Cache hit ratio: 87% (обычно > 99%)
- Активных соединений: 95 из 100
- Долгих транзакций: 3 соединения idle in transaction > 15 мин
- Медленные запросы в логе: INSERT INTO orders ... — 28 000 мс

Прикреплено:
- Вывод pg_stat_activity
- Фрагмент лога с медленными запросами
- Вывод запроса на блокировки

Был ли деплой / миграция перед началом проблемы: да / нет / не знаю
```

---

## 10. Итоги лекции

После этой лекции студент умеет:

- **Найти блокировку** через `pg_stat_activity` + `pg_blocking_pids()` и снять её через `pg_cancel_backend`.
- **Оценить bloat** таблицы по `n_dead_tup / (n_live_tup + n_dead_tup)` и инициировать `VACUUM ANALYZE`.
- **Вычислить cache hit ratio** из `pg_stat_database` и объяснить причины значений < 99%.
- **Настроить журналирование** для последующего анализа: `log_min_duration_statement`, `log_lock_waits`, `log_line_prefix` для pgBadger.
- **Составить отчёт о состоянии БД** с конкретными числами, а не общими словами.

---

## Ссылки

- pg_stat_activity: https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STAT-ACTIVITY-VIEW
- pg_stat_user_tables: https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STAT-ALL-TABLES-VIEW
- Настройка журналирования: https://www.postgresql.org/docs/current/runtime-config-logging.html
- pg_blocking_pids: https://www.postgresql.org/docs/current/functions-info.html
