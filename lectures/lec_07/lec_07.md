# Лекция 7. Мониторинг, сбор статистики, журналирование

**Неделя:** 7  
**Версия PostgreSQL:** 18 (запросы проверены для 17+; отличия от 16 и ниже отмечены)  
**Связанная лабораторная работа:** лаб. 05 «Мониторинг базы eshop»

---

## Цель лекции

По итогам лекции студент:

- знает ключевые системные представления PostgreSQL для мониторинга активности;
- умеет выявить долгие запросы, блокировки, мёртвые строки и деградацию кэша через `pg_stat_*`;
- различает отмену запроса и завершение сессии и знает, когда что применять;
- знает, как настроить журналирование для последующего анализа;
- понимает, какие метрики передавать DBA при описании проблемы с производительностью.

---

## 1. Зачем мониторить БД

Мониторинг позволяет обнаружить проблему **до** того, как её заметит пользователь:

| Без мониторинга                   | С мониторингом                            |
|-----------------------------------|-------------------------------------------|
| Узнаём о проблеме от пользователя | Алерт за 10 минут до деградации           |
| Непонятно, когда началось         | Есть timeline и метрики на момент начала  |
| Тяжело воспроизвести              | Логи и статистика сохранены               |
| DBA ищет причину «вслепую»        | DBA видит конкретный запрос / блокировку  |

**Три зоны мониторинга PostgreSQL:**

1. **Активность** — что происходит прямо сейчас (соединения, запросы, блокировки).
2. **Статистика** — накопленные данные об использовании таблиц, индексов, запросов, фоновых процессов.
3. **Журналы** — историческая запись событий для post-mortem анализа.

> **Статистика накопительная.** Счётчики `pg_stat_*` растут с момента последнего сброса
> (столбец `stats_reset`). Одно значение говорит мало — важна разница между двумя замерами.
> Сброс счётчиков текущей БД: `SELECT pg_stat_reset();`
>
> **Снимок внутри транзакции.** В пределах одной транзакции `pg_stat_activity` и счётчики `pg_stat_*`
> возвращают одни и те же значения (параметр `stats_fetch_consistency = cache`).
> Окно мониторинга должно работать в режиме auto-commit, иначе вы будете видеть устаревшие данные.

---

## 2. Активные соединения: pg_stat_activity

`pg_stat_activity` — главное представление для мониторинга текущей активности.
В нём есть строки не только клиентов, но и фоновых процессов (`checkpointer`, `autovacuum launcher` и др.).
Для анализа нагрузки оставляйте только клиентские сессии.

```sql
-- Клиентские сессии, кроме собственной
SELECT pid, usename, application_name, state,
       wait_event_type, wait_event,
       now() - xact_start  AS tx_duration,
       now() - query_start AS query_duration,
       LEFT(query, 100)    AS query_preview
FROM   pg_stat_activity
WHERE  backend_type = 'client backend'
  AND  pid <> pg_backend_pid()
ORDER  BY tx_duration DESC NULLS LAST;
```

Ключевые столбцы:

| Столбец           | Описание                                                                |
|-------------------|-------------------------------------------------------------------------|
| `pid`             | PID процесса backend                                                    |
| `backend_type`    | Тип процесса: `client backend`, `autovacuum worker`, `checkpointer` …   |
| `state`           | Состояние сессии (см. ниже)                                             |
| `wait_event_type` | Тип ожидания: `Lock`, `LWLock`, `IO`, `Client`, `IPC`, `Timeout`        |
| `wait_event`      | Конкретное событие ожидания                                             |
| `xact_start`      | Когда началась текущая транзакция                                       |
| `query_start`     | Когда начался текущий (или последний) запрос                            |
| `query`           | Текст текущего запроса; для `idle*` — **последнего выполненного**       |

Значения `state`:

| Состояние                       | Что значит                                                                 |
|---------------------------------|----------------------------------------------------------------------------|
| `active`                        | Выполняет запрос                                                           |
| `idle`                          | Ждёт команду, транзакции нет                                               |
| `idle in transaction`           | Транзакция открыта, запроса нет — ждёт клиента. **Держит блокировки**      |
| `idle in transaction (aborted)` | Транзакция открыта, в ней была ошибка; ждёт `ROLLBACK`                     |
| `fastpath function call`        | Выполняет функцию через fast-path интерфейс                                |

Типы ожиданий, которые встречаются чаще всего:

| `wait_event_type` | Что значит                                                                  |
|-------------------|-----------------------------------------------------------------------------|
| `Lock`            | Ждёт тяжёлую блокировку (строки, таблицы), которую держит другая сессия     |
| `LWLock`          | Ждёт внутреннюю легковесную блокировку (буферы, WAL)                        |
| `IO`              | Ждёт чтения или записи на диск                                              |
| `Client`          | Ждёт данных от клиента (типично для `idle`)                                 |

### 2.1. Долгие запросы

```sql
-- Запросы, которые выполняются дольше 5 минут
SELECT pid, usename,
       now() - query_start AS query_duration,
       wait_event_type, wait_event,
       LEFT(query, 100) AS query_preview
FROM   pg_stat_activity
WHERE  backend_type = 'client backend'
  AND  state = 'active'
  AND  query_start < now() - INTERVAL '5 minutes'
ORDER  BY query_duration DESC;
```

### 2.2. Зависшие транзакции

Сессия в `idle in transaction` ничего не делает и не видна по нагрузке на CPU.
При этом она держит блокировки. Если транзакция уже что-то изменила (есть `backend_xid`)
или работает на уровне `REPEATABLE READ`, она ещё и задерживает горизонт очистки:
VACUUM не может удалить мёртвые строки, которые появились после её начала.
Длительность считается по `xact_start`, а не по `query_start`.

```sql
-- Транзакции, открытые дольше 5 минут без активности
SELECT pid, usename, state,
       now() - xact_start AS tx_duration,
       LEFT(query, 80)    AS last_query
FROM   pg_stat_activity
WHERE  state IN ('idle in transaction', 'idle in transaction (aborted)')
  AND  xact_start < now() - INTERVAL '5 minutes'
ORDER  BY tx_duration DESC;
```

Защита на уровне сервера — параметр `idle_in_transaction_session_timeout`:
сессия, которая простаивает в транзакции дольше заданного времени, закрывается автоматически.

### 2.3. Блокировки

```sql
-- Кто кого блокирует
SELECT blocked.pid               AS blocked_pid,
       blocked.usename           AS blocked_user,
       now() - blocked.query_start AS waiting,
       blocker.pid               AS blocker_pid,
       blocker.usename           AS blocker_user,
       blocker.state             AS blocker_state,
       LEFT(blocked.query, 60)   AS blocked_query,
       LEFT(blocker.query, 60)   AS blocker_last_query
FROM   pg_stat_activity AS blocked
JOIN   pg_stat_activity AS blocker
       ON blocker.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE  cardinality(pg_blocking_pids(blocked.pid)) > 0;
```

Обратите внимание на `blocker_state`. Чаще всего блокировщик находится в `idle in transaction`:
приложение открыло транзакцию, изменило строку и не выполнило `COMMIT`.

### 2.4. Отмена запроса и завершение сессии

| Функция                     | Что делает                         | Транзакция                                   | Сессия      |
|-----------------------------|------------------------------------|----------------------------------------------|-------------|
| `pg_cancel_backend(pid)`    | Прерывает **текущий запрос**       | Если запрос был — транзакция прерывается, блокировки снимаются; сессия ждёт `ROLLBACK`. Если запроса нет (`idle*`) — ничего не происходит | Остаётся    |
| `pg_terminate_backend(pid)` | Закрывает **сессию**               | Откатывается, все блокировки снимаются       | Закрывается |

```sql
SELECT pg_cancel_backend(pid);     -- отменить текущий запрос процесса
SELECT pg_terminate_backend(pid);  -- закрыть сессию, откатить её транзакцию
```

**Какую функцию выбрать:**

- Блокировщик в состоянии `active` (выполняет долгий запрос) — `pg_cancel_backend`
  прервёт запрос с ошибкой. Внутри явной транзакции (`BEGIN … `) ошибка прерывает всю транзакцию:
  блокировки снимаются сразу, ожидающие сессии продолжают работу.
  Сама сессия переходит в `idle in transaction (aborted)` и не примет новые команды, пока клиент не выполнит `ROLLBACK`.
- Блокировщик в состоянии `idle in transaction` — `pg_cancel_backend` **не поможет**:
  текущего запроса нет, отменять нечего. Функция вернёт `true`, но блокировка останется.
  Нужен `pg_terminate_backend` (или `ROLLBACK` со стороны приложения).
- `pg_cancel_backend(<blocked_pid>)` на **ожидающем** процессе снимает симптом, а не причину:
  ждущий запрос получит ошибку, блокировщик останется.

**Права:** суперпользователь, член роли `pg_signal_backend`, или владелец сессии — для своих процессов.
Сессии суперпользователя может завершить только суперпользователь.

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

| Признак                                          | Интерпретация                                              |
|--------------------------------------------------|------------------------------------------------------------|
| `seq_scan` >> `idx_scan` на большой таблице      | Индекса нет или планировщик его не использует — `EXPLAIN`  |
| `n_dead_tup / (n_live_tup + n_dead_tup)` > 20 %  | Много мёртвых версий строк; autovacuum не успевает         |
| `last_autovacuum` — давно или NULL               | Autovacuum не справляется, отключён или его держит долгая транзакция |

### 3.1. Мёртвые строки и bloat — не одно и то же

- **Мёртвая строка (dead tuple)** — старая версия строки после `UPDATE` или `DELETE`.
  Её не видит ни одна транзакция, но она ещё занимает место.
- **VACUUM** помечает место мёртвых строк как свободное для новых данных.
  `n_dead_tup` падает до нуля, но **размер файла таблицы, как правило, не уменьшается**.
  Исключение: полностью пустые страницы в самом конце файла VACUUM отрезает.
- **Bloat** — избыточный размер таблицы или индекса: свободное место внутри файла, которое не используется.
  Вернуть его операционной системе может только `VACUUM FULL` (блокирует таблицу целиком) или расширение `pg_repack`.

Порог 20 % не случаен: autovacuum запускается, когда мёртвых строк больше, чем
`autovacuum_vacuum_threshold + autovacuum_vacuum_scale_factor × n_live_tup`
(по умолчанию 50 + 0,2 × n_live_tup).

```sql
-- Размер таблицы, её индексов и общий
SELECT relname,
       pg_size_pretty(pg_relation_size(relid))       AS table_size,
       pg_size_pretty(pg_indexes_size(relid))        AS indexes_size,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM   pg_stat_user_tables
ORDER  BY pg_total_relation_size(relid) DESC;
```

---

## 4. Статистика индексов: pg_stat_user_indexes

```sql
SELECT relname      AS table_name,
       indexrelname AS index_name,
       idx_scan,                                     -- 0 = кандидат на проверку
       idx_tup_read,
       idx_tup_fetch,
       pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM   pg_stat_user_indexes
ORDER  BY idx_scan ASC, pg_relation_size(indexrelid) DESC;
```

`idx_scan = 0` — повод проверить индекс, а не удалять сразу. Перед удалением убедитесь, что:

- статистика накоплена за достаточный период (недели, включая отчётные дни месяца);
- индекс не обеспечивает ограничение `PRIMARY KEY` или `UNIQUE`;
- индекс не используется на репликах (у реплик своя статистика).

---

## 5. Статистика запросов: pg_stat_statements

Лог (раздел 8) видит только запросы дольше порога `log_min_duration_statement`.
Расширение `pg_stat_statements` считает **все** запросы. Частый быстрый запрос
(5 мс × 1 000 000 вызовов) нагружает сервер сильнее, чем редкий медленный — и в лог он не попадёт.

Подключение (однократно, нужен перезапуск службы):

```ini
# postgresql.conf
shared_preload_libraries = 'pg_stat_statements'
```

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

Топ-10 запросов по суммарному времени:

```sql
SELECT calls,
       ROUND(total_exec_time::numeric, 0) AS total_ms,
       ROUND(mean_exec_time::numeric, 1)  AS mean_ms,
       rows,
       ROUND(100.0 * shared_blks_hit
             / NULLIF(shared_blks_hit + shared_blks_read, 0), 1) AS hit_pct,
       LEFT(query, 80) AS query_preview
FROM   pg_stat_statements
ORDER  BY total_exec_time DESC
LIMIT  10;
```

| Сортировка по       | Что находим                                      |
|---------------------|--------------------------------------------------|
| `total_exec_time`   | Что сильнее всего нагружает сервер в целом       |
| `mean_exec_time`    | Самые медленные запросы «за один вызов»          |
| `calls`             | Самые частые запросы (кандидаты на кэширование)  |

Сброс статистики: `SELECT pg_stat_statements_reset();`

---

## 6. Фоновые процессы: checkpointer и bgwriter

**Checkpoint** — момент, когда все изменённые страницы из памяти записываются на диск.
Плановый checkpoint запускается по таймеру `checkpoint_timeout`.
Внеплановый — когда объём WAL достигает `max_wal_size`.

> **PostgreSQL 17+.** Статистика checkpoint перенесена из `pg_stat_bgwriter` в `pg_stat_checkpointer`.
> Столбцы `checkpoints_timed`, `checkpoints_req`, `buffers_checkpoint` и `buffers_backend`
> из `pg_stat_bgwriter` удалены. Запросы из старых статей и учебников на PG 17–18 выдадут ошибку.

```sql
-- PostgreSQL 17+
SELECT num_timed,          -- плановые checkpoint
       num_requested,      -- внеплановые: много = увеличить max_wal_size
       buffers_written,    -- страниц записано при checkpoint
       write_time,         -- мс на запись
       sync_time,          -- мс на fsync
       stats_reset
FROM   pg_stat_checkpointer;
```

```sql
-- Фоновая запись (PostgreSQL 17+)
SELECT buffers_clean,      -- страниц записал bgwriter
       maxwritten_clean,   -- сколько раз bgwriter остановился по лимиту
       buffers_alloc       -- выделено буферов
FROM   pg_stat_bgwriter;
```

Кто ещё пишет страницы на диск — представление `pg_stat_io` (PostgreSQL 16+):

```sql
SELECT backend_type, writes, write_bytes, fsyncs
FROM   pg_stat_io
WHERE  object  = 'relation'   -- страницы таблиц и индексов (в PG 18 есть ещё строки object = 'wal')
  AND  context = 'normal'     -- обычная работа через shared_buffers
  AND  writes  > 0
ORDER  BY writes DESC;
-- много writes у 'client backend' = shared_buffers мал,
-- обычные сессии сами сбрасывают страницы на диск вместо bgwriter
```

В PostgreSQL 18 в `pg_stat_io` добавлены столбцы `read_bytes`, `write_bytes`, `extend_bytes` и строки для WAL;
столбец `op_bytes` удалён. Запись WAL клиентскими сессиями — норма, поэтому фильтр `object = 'relation'` обязателен.

| Признак                                    | Интерпретация и действие                                              |
|--------------------------------------------|-----------------------------------------------------------------------|
| `num_requested` > 30 % от `num_timed`      | WAL заполняется быстрее таймера — увеличить `max_wal_size`            |
| Большой `write_time` при checkpoint        | Пик записи — проверить `checkpoint_completion_target` (норма 0.9)     |
| Много `writes` у `client backend`          | Мал `shared_buffers` или bgwriter не успевает                         |

`checkpoint_completion_target` растягивает запись checkpoint во времени и сглаживает пик нагрузки на диск.
**Частоту** checkpoint он не меняет.

`num_requested` считает также ручные `CHECKPOINT`, checkpoint при `CREATE DATABASE` и запуске резервного копирования.
Перед выводом «мал `max_wal_size`» проверьте в логе (`log_checkpoints = on`, по умолчанию включён) причину: `checkpoint starting: wal`.

<details>
<summary>Для PostgreSQL 16 и ниже</summary>

```sql
SELECT checkpoints_timed, checkpoints_req,
       buffers_checkpoint, buffers_clean, buffers_backend, buffers_alloc
FROM   pg_stat_bgwriter;
```

</details>

---

## 7. Метрика кэша: cache hit ratio

```sql
SELECT datname,
       ROUND(blks_hit::numeric / NULLIF(blks_hit + blks_read, 0) * 100, 2) AS cache_hit_pct
FROM   pg_stat_database
WHERE  datname IS NOT NULL
ORDER  BY cache_hit_pct;
```

| Значение | Интерпретация                                                          |
|----------|------------------------------------------------------------------------|
| > 99 %   | Норма для OLTP: рабочие данные в памяти                                |
| 95–99 %  | Требует внимания: часть данных читается с диска                        |
| < 95 %   | Проблема: мал `shared_buffers`, данных больше, чем памяти, или идут массовые полные сканы |

Две оговорки:

- `blks_read` — чтение «мимо» `shared_buffers`. Часть таких чтений обслуживает кэш ОС,
  поэтому до диска доходит меньше, чем показывает метрика.
- Для аналитической (OLAP) нагрузки низкий hit ratio — норма: большие таблицы читаются целиком.

---

## 8. Настройка журналирования

### 8.1. Ключевые параметры postgresql.conf

```ini
logging_collector              = on     # требует перезапуска службы
log_directory                  = 'log'
log_filename                   = 'postgresql-%Y-%m-%d.log'
log_rotation_age               = 1d
log_rotation_size              = 100MB

# Формат строки (важен для pgBadger)
log_line_prefix                = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '

# Медленные запросы
log_min_duration_statement     = 1000   # запросы дольше 1 секунды (production)

# Дополнительные события
log_lock_waits                 = on     # ожидание блокировки дольше deadlock_timeout (1 с); по умолчанию off
log_temp_files                 = 10240  # временные файлы больше 10 МБ (значение в кБ)
log_autovacuum_min_duration    = 250    # autovacuum дольше 250 мс
log_connections                = on     # PG 18: список опций; on = receipt,authentication,authorization
log_disconnections             = on
```

Порог `log_min_duration_statement` зависит от среды. Для production обычно 1000 мс и выше,
чтобы не перегружать лог. В учебной среде (лаб. 05) используем 500 мс.

### 8.2. Применение настроек

| Параметр                               | Как применить                     |
|----------------------------------------|-----------------------------------|
| `logging_collector`, `shared_preload_libraries` | Только перезапуск службы  |
| Остальные параметры раздела 8.1        | `SELECT pg_reload_conf();`        |

```powershell
# PowerShell от имени администратора
Get-Service postgresql*
Restart-Service postgresql-x64-18
```

```sql
-- Проверить, что параметры применены без ошибок
SELECT name, setting, pending_restart
FROM   pg_settings
WHERE  name IN ('logging_collector', 'log_min_duration_statement', 'log_lock_waits');

SELECT name, setting, error
FROM   pg_file_settings
WHERE  error IS NOT NULL;

-- Где лежит текущий лог-файл (путь относительно data_directory)
SELECT pg_current_logfile();
```

### 8.3. Поиск в логе

PowerShell запускайте от имени администратора: каталог данных закрыт для обычных пользователей.

```powershell
$logDir = "C:\Program Files\PostgreSQL\18\data\log"   # каталог из SHOW data_directory
Get-ChildItem $logDir | Sort-Object LastWriteTime -Descending | Select-Object -First 1 |
    Select-String -Pattern "duration|still waiting for" |
    Select-Object -Last 20
```

Для системного анализа логов используют pgBadger (лаб. 06). Ему нужен `log_line_prefix` из раздела 8.1.

---

## 9. Ключевые метрики и пороги

| Метрика                       | Как получить                                                  | Внимание       | Тревога                    |
|-------------------------------|---------------------------------------------------------------|----------------|----------------------------|
| Cache hit ratio (OLTP)        | `pg_stat_database`                                            | < 99 %         | < 95 %                     |
| Активных соединений           | `pg_stat_activity WHERE state = 'active'`                     | > 50 % от `max_connections` | > 80 % от `max_connections` |
| Транзакции без активности     | `pg_stat_activity WHERE state LIKE 'idle in transaction%'`    | > 1 мин        | > 5 мин                    |
| Доля мёртвых строк            | `pg_stat_user_tables`                                         | > 10 %         | > 20 %                     |
| Внеплановых checkpoint        | `pg_stat_checkpointer.num_requested`                          | > 10 % от `num_timed` | > 30 % от `num_timed` |
| Ожидающих блокировку          | `pg_stat_activity WHERE wait_event_type = 'Lock'`             | > 0 дольше 10 с | > 0 дольше 1 мин         |
| Ошибки архивирования WAL      | `pg_stat_archiver.failed_count`                               | —              | > 0 и растёт               |

Пороги — ориентир. Для конкретной системы их уточняют по базовой линии: значениям в обычный рабочий день.

---

## 10. Что передавать DBA при проблеме с производительностью

Отчёт = **время + симптом + числа с нормой для сравнения + приложения + контекст**.
Фраза «всё тормозит» — не отчёт.

```markdown
## Отчёт о проблеме производительности

Среда: production
Время начала деградации: 2026-09-01 14:30 MSK
Симптом: запросы на создание заказа выполняются > 30 сек (обычно < 200 мс)

Метрики на момент проблемы:
- Cache hit ratio: 87 % (обычно > 99 %)
- Активных соединений: 95 из 100 (max_connections)
- Транзакции без активности: 3 сессии idle in transaction > 15 мин
- Ожидают блокировку: 41 сессия, блокировщик pid 18342 (idle in transaction)
- Медленные запросы в логе: INSERT INTO orders ... — 28 000 мс

Прикреплено:
- Вывод pg_stat_activity (клиентские сессии)
- Вывод запроса на блокировки
- Топ-10 из pg_stat_statements
- Фрагмент лога с медленными запросами

Был ли деплой / миграция перед началом проблемы: да / нет / не знаю
```

---

## 11. Итоги лекции

После этой лекции студент умеет:

- **Найти блокировку** через `pg_stat_activity` + `pg_blocking_pids()` и снять её правильным способом:
  `pg_terminate_backend` для блокировщика в `idle in transaction`, `pg_cancel_backend` — для долгого активного запроса.
- **Оценить мёртвые строки** по `n_dead_tup / (n_live_tup + n_dead_tup)`, выполнить `VACUUM ANALYZE`
  и объяснить, почему размер таблицы после него, как правило, не уменьшается.
- **Найти тяжёлые запросы** через `pg_stat_statements`, а не только через лог.
- **Прочитать статистику checkpoint** в `pg_stat_checkpointer` (PG 17+) и связать частые внеплановые checkpoint с `max_wal_size`.
- **Вычислить cache hit ratio** из `pg_stat_database` и объяснить причины значений < 99 %.
- **Настроить журналирование**: `log_min_duration_statement`, `log_lock_waits`, `log_line_prefix` для pgBadger;
  знать, какие параметры требуют перезапуска.
- **Составить отчёт о состоянии БД** с конкретными числами, а не общими словами.

---

## Контрольные вопросы

1. Почему `pg_cancel_backend` не снимает блокировку, если блокировщик в состоянии `idle in transaction`?
2. Что означает `wait_event_type = 'Lock'`? Чем оно отличается от `LWLock`?
3. Чем опасна долгая `idle in transaction`, если она не нагружает процессор?
4. После `VACUUM` значение `n_dead_tup` = 0. Стала ли таблица меньше на диске? Почему?
5. Много внеплановых checkpoint. Какой параметр увеличить и почему не `checkpoint_completion_target`?
6. Почему `pg_stat_statements` находит проблемы, которые не видны в логе медленных запросов?

---

## Ссылки

- Мониторинг, представления pg_stat_*: https://www.postgresql.org/docs/current/monitoring-stats.html
- pg_stat_activity: https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STAT-ACTIVITY-VIEW
- pg_stat_checkpointer: https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STAT-CHECKPOINTER-VIEW
- pg_stat_io: https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STAT-IO-VIEW
- pg_stat_statements: https://www.postgresql.org/docs/current/pgstatstatements.html
- Функции управления сеансами: https://www.postgresql.org/docs/current/functions-admin.html#FUNCTIONS-ADMIN-SIGNAL
- pg_blocking_pids: https://www.postgresql.org/docs/current/functions-info.html
- Регламентная очистка (VACUUM): https://www.postgresql.org/docs/current/routine-vacuuming.html
- Настройка журналирования: https://www.postgresql.org/docs/current/runtime-config-logging.html
- Настройка WAL и checkpoint: https://www.postgresql.org/docs/current/wal-configuration.html
