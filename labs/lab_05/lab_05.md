# Лабораторная работа №5
## Мониторинг базы eshop: pg_stat_*, блокировки, журналирование

**Неделя:** 7  
**Ориентировочное время:** 2 занятия (≈ 4 ак. ч.)  
**Среда:** Windows, PowerShell, PostgreSQL 18, DBeaver / psql

---

## Цель работы

- Научиться читать ключевые системные представления PostgreSQL.
- Выявлять долгие запросы, блокировки и мёртвые строки (dead tuples) в таблицах.
- Настроить журналирование для последующего анализа медленных запросов.
- Составить отчёт о состоянии БД.

---

## Предварительные требования

- Завершена лаб. 02: база `eshop` с ролями существует.
- Прочитана лек. 07.

> **DBeaver и транзакции.** По умолчанию DBeaver работает в режиме auto-commit.
> Для шагов 1.2–1.4 переключите редактор в режим **Manual Commit**
> (кнопка на панели инструментов) или используйте `psql`.
> Иначе транзакция завершится сразу и блокировка не возникнет.

---

## Часть 1. pg_stat_activity: текущая активность

### 1.1. Общий обзор соединений

Подключитесь к `eshop` под `postgres` и выполните:

```sql
SELECT pid, usename, application_name, state,
       wait_event_type, wait_event,
       now() - xact_start  AS tx_duration,
       now() - query_start AS query_duration,
       LEFT(query, 80)     AS query_preview
FROM   pg_stat_activity
WHERE  backend_type = 'client backend'   -- только клиентские сессии
  AND  pid <> pg_backend_pid()           -- кроме собственной
ORDER  BY tx_duration DESC NULLS LAST;
```

Скорее всего, вы увидите только служебные соединения DBeaver в состоянии `idle`.

Уберите условие `backend_type = 'client backend'` и выполните запрос снова.
Появятся фоновые процессы: `autovacuum launcher`, `checkpointer`, `background writer` и др.
У них пустой `usename` и нет запроса.

### 1.2. Симуляция долгой транзакции

Откройте **второе** окно (psql или редактор DBeaver в режиме Manual Commit) и выполните.
COMMIT **не** делайте:

```sql
-- Сеанс 2: начать транзакцию и оставить её открытой
BEGIN;
UPDATE orders SET status = 'processing' WHERE id = 1;
-- COMMIT не выполняем
```

В **первом** окне:

```sql
-- Найти транзакцию, которая открыта, но ничего не выполняет
SELECT pid, usename, state,
       now() - xact_start AS tx_duration,
       LEFT(query, 80)    AS last_query
FROM   pg_stat_activity
WHERE  state = 'idle in transaction';
```

Запишите PID сеанса 2 (блокировщика): ___

> `idle in transaction` — сессия открыла транзакцию и ждёт следующей команды от клиента.
> Запрос в столбце `query` — это **последний выполненный**, а не текущий.
> Такая сессия держит блокировки и мешает autovacuum удалять мёртвые строки.

### 1.3. Симуляция блокировки

В **третьем** окне:

```sql
-- Сеанс 3: обновить ту же строку — запрос будет ждать
UPDATE orders SET status = 'shipped' WHERE id = 1;
-- Запрос зависнет
```

В **первом** окне:

```sql
-- Кто кого блокирует
SELECT blocked.pid          AS blocked_pid,
       blocked.usename      AS blocked_user,
       blocked.wait_event_type,
       blocker.pid          AS blocker_pid,
       blocker.usename      AS blocker_user,
       blocker.state        AS blocker_state,
       LEFT(blocked.query, 60) AS blocked_query,
       LEFT(blocker.query, 60) AS blocker_last_query
FROM   pg_stat_activity AS blocked
JOIN   pg_stat_activity AS blocker
       ON blocker.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE  cardinality(pg_blocking_pids(blocked.pid)) > 0;
```

Запишите: `blocked_pid` = ___, `blocker_pid` = ___, `blocker_state` = ___

### 1.4. Разрешить блокировку

Две функции работают по-разному:

| Функция | Что делает | Транзакция | Сессия |
|---|---|---|---|
| `pg_cancel_backend(pid)` | Прерывает **текущий запрос** процесса | Остаётся открытой (переходит в aborted) | Остаётся |
| `pg_terminate_backend(pid)` | Закрывает **сессию** | Откатывается, блокировки снимаются | Закрывается |

Права: суперпользователь, член роли `pg_signal_backend` или владелец сессии (для своих процессов).

**Шаг А. Попробуйте cancel на блокировщике:**

```sql
SELECT pg_cancel_backend(<blocker_pid>);
```

Функция вернёт `true`, но сеанс 3 **продолжит ждать**.
Повторите запрос из 1.3 — блокировщик на месте.

Причина: блокировщик находится в `idle in transaction`. Текущего запроса у него нет, отменять нечего.
Транзакция осталась открытой, блокировка строки — тоже.

**Шаг Б. Снимите блокировку правильно.** Выберите один вариант:

```sql
-- Вариант 1: в сеансе 2 завершить транзакцию самому
ROLLBACK;

-- Вариант 2: из первого окна закрыть сессию блокировщика
SELECT pg_terminate_backend(<blocker_pid>);
```

Сеанс 3 сразу выполнит свой UPDATE. Проверьте запросом из 1.3 — результат пустой.
Завершите транзакцию в сеансе 3 (`COMMIT` или `ROLLBACK`).

> **Справочно.** `pg_cancel_backend(<blocked_pid>)` отменит **ожидающий** запрос сеанса 3.
> Сеанс 3 получит ошибку, а блокировщик останется. Так снимают симптом, а не причину.

---

## Часть 2. Статистика таблиц и индексов

### 2.1. pg_stat_user_tables

```sql
SELECT relname,
       seq_scan, idx_scan,
       n_live_tup, n_dead_tup,
       ROUND(n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0) * 100, 1) AS dead_pct,
       last_vacuum, last_autovacuum, last_autoanalyze
FROM   pg_stat_user_tables
ORDER  BY relname;
```

Запишите значения для таблицы `orders`: n_live_tup = ___, n_dead_tup = ___

> Счётчики `pg_stat_*` накопительные и обновляются с небольшой задержкой.
> Если значения не изменились сразу после операции, подождите 1–2 секунды и повторите запрос.

### 2.2. Создать мёртвые строки

Отключите autovacuum для таблицы, чтобы он не убрал мёртвые строки раньше вас:

```sql
ALTER TABLE products SET (autovacuum_enabled = false);
```

Запишите размер таблицы до эксперимента:

```sql
SELECT pg_size_pretty(pg_relation_size('products')) AS size_before;
```

Размер до: ___

Создайте мёртвые строки. Каждый UPDATE в PostgreSQL создаёт новую версию строки, а старая становится мёртвой:

```sql
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
SELECT relname, n_live_tup, n_dead_tup,
       ROUND(n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0) * 100, 1) AS dead_pct,
       pg_size_pretty(pg_relation_size('products')) AS size_now
FROM   pg_stat_user_tables
WHERE  relname = 'products';
-- dead_pct и размер должны вырасти
```

dead_pct: ___ %, размер: ___

### 2.3. Запустить VACUUM и проверить

```sql
VACUUM ANALYZE products;

SELECT relname, n_dead_tup, last_vacuum,
       pg_size_pretty(pg_relation_size('products')) AS size_after_vacuum
FROM   pg_stat_user_tables
WHERE  relname = 'products';
```

Ожидаемый результат:

- `n_dead_tup` упал до 0 или близко к 0;
- `last_vacuum` заполнен;
- **размер таблицы почти не изменился**.

Обычный VACUUM помечает место мёртвых строк как свободное для повторного использования, но файл таблицы не уменьшает.
Вернуть место операционной системе может только `VACUUM FULL` (блокирует таблицу целиком) или расширение `pg_repack`.

```sql
VACUUM FULL products;
SELECT pg_size_pretty(pg_relation_size('products')) AS size_after_full;
```

Размер после VACUUM: ___, после VACUUM FULL: ___

Верните autovacuum:

```sql
ALTER TABLE products RESET (autovacuum_enabled);
```

### 2.4. Неиспользуемые индексы

```sql
SELECT relname      AS table_name,
       indexrelname AS index_name,
       idx_scan,
       pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM   pg_stat_user_indexes
ORDER  BY idx_scan ASC, pg_relation_size(indexrelid) DESC;
```

Индексы с `idx_scan = 0` — кандидаты на проверку. Учебная база работает недавно,
поэтому 0 здесь не означает, что индекс не нужен. На production решение принимают по статистике за несколько недель.

### 2.5. Cache hit ratio

```sql
SELECT ROUND((SUM(blks_hit)::numeric
       / NULLIF(SUM(blks_hit) + SUM(blks_read), 0) * 100), 2) AS cache_hit_pct
FROM   pg_stat_database
WHERE  datname = 'eshop';
```

Запишите значение: ___ %.

Пороги: > 99 % — норма; < 99 % — повод разобраться (мал `shared_buffers` или данных больше, чем памяти).
Учебная база целиком помещается в память, поэтому значение будет близко к 100 %.

---

## Часть 3. Настройка журналирования

### 3.1. Найти конфигурацию и логи

```sql
SHOW config_file;          -- путь к postgresql.conf
SHOW data_directory;       -- каталог данных
SHOW logging_collector;    -- на Windows обычно уже on
SELECT pg_current_logfile();  -- текущий лог-файл (путь относительно data_directory)
```

### 3.2. Параметры в postgresql.conf

Откройте `postgresql.conf` в редакторе **от имени администратора** и добавьте или измените строки:

```ini
logging_collector           = on
log_directory               = 'log'
log_filename                = 'postgresql-%Y-%m-%d.log'
log_rotation_age            = 1d

# Формат строки для pgBadger (понадобится в лаб. 06)
log_line_prefix             = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '

# Медленные запросы: логировать всё, что дольше 500 мс (учебный порог)
log_min_duration_statement  = 500

# Полезные события
log_lock_waits              = on      # ожидание блокировки дольше deadlock_timeout (1 с)
log_temp_files              = 10240   # временные файлы больше 10 МБ (значение в кБ)
log_autovacuum_min_duration = 250     # работа autovacuum дольше 250 мс
```

Примените настройки.

Если `logging_collector` был `off`, нужен **перезапуск службы**. `pg_reload_conf()` этот параметр не применяет.
В PowerShell от имени администратора:

```powershell
Get-Service postgresql*                  # узнать имя службы
Restart-Service postgresql-x64-18
```

Остальные параметры применяются без перезапуска:

```sql
SELECT pg_reload_conf();
SHOW log_min_duration_statement;    -- должно показать 500ms
SHOW log_lock_waits;                -- on
```

Если значение не изменилось, проверьте ошибки в файле:

```sql
SELECT name, setting, error
FROM   pg_file_settings
WHERE  error IS NOT NULL;
```

### 3.3. Создать «медленный» запрос и найти его в логе

```sql
SELECT pg_sleep(0.7), count(*) FROM orders;
```

В PowerShell:

```powershell
$logDir = "C:\Program Files\PostgreSQL\18\data\log"   # подставьте data_directory из 3.1
Get-ChildItem $logDir | Sort-Object LastWriteTime -Descending | Select-Object -First 1 |
    Select-String -Pattern "duration" |
    Select-Object -Last 10
```

Найденная строка: ___

> В production порог обычно выше — 1000 мс и более. В учебной среде используем 500 мс,
> чтобы быстрее увидеть результат.

---

## Часть 4. Отчёт о состоянии БД

Заполните шаблон и сохраните как `C:\backup\eshop\db_health_report.md`.
Пишите числа, а не оценки: «dead_pct = 34 %», а не «много мёртвых строк».

```markdown
## Отчёт о состоянии БД eshop

**Дата и время замера:** ___
**PostgreSQL version:** (SELECT version();) ___

### Соединения
- Всего клиентских соединений: ___ из max_connections = ___
- Активных запросов (state = 'active'): ___
- Idle in transaction: ___ (самая долгая: ___ мин)

### Кэш
- Cache hit ratio: ___ %

### Мёртвые строки
| Таблица     | n_live_tup | n_dead_tup | dead_pct | last_autovacuum |
|-------------|------------|------------|----------|-----------------|
| customers   |            |            |          |                 |
| orders      |            |            |          |                 |
| order_items |            |            |          |                 |
| products    |            |            |          |                 |

### Эксперимент с VACUUM (products)
| Момент             | n_dead_tup | Размер таблицы |
|--------------------|------------|----------------|
| До UPDATE          |            |                |
| После UPDATE       |            |                |
| После VACUUM       |            |                |
| После VACUUM FULL  |            |                |

### Индексы
- Индексов с idx_scan = 0: ___ (список: ___)

### Журналирование
- logging_collector: ___
- log_min_duration_statement: ___
- log_lock_waits: ___
- Медленных запросов в текущем логе: ___

### Выводы и рекомендации
1. ___
2. ___
```

---

## Чек-лист «работа зачтена»

- [ ] Блокировка смоделирована: запрос из 1.3 показал `blocker_pid` в состоянии `idle in transaction`.
- [ ] Показано, что `pg_cancel_backend` на блокировщике **не** снимает блокировку, и объяснено почему.
- [ ] Блокировка снята через `ROLLBACK` или `pg_terminate_backend`.
- [ ] Мёртвые строки созданы и убраны `VACUUM ANALYZE products`; зафиксировано, что размер таблицы уменьшил только `VACUUM FULL`.
- [ ] `log_min_duration_statement = 500ms` применён; медленный запрос найден в логе.
- [ ] `db_health_report.md` заполнен числами.

---

## Самостоятельное задание

1. Напишите SQL-запрос, который выводит топ-5 таблиц по доле мёртвых строк.
2. Проверьте, что `log_lock_waits = on`. Создайте блокировку (шаги 1.2–1.3) и подождите не меньше 2 секунд:
   запись появится после `deadlock_timeout` (по умолчанию 1 с). Снимите блокировку и найдите в логе строку
   со словами `still waiting for`.
3. Объясните: что означает `wait_event_type = 'Lock'` в `pg_stat_activity`? Чем отличается от `LWLock` и `IO`?
4. Почему `pg_cancel_backend` помог бы, если бы блокировщик в момент вызова выполнял долгий запрос
   (`state = 'active'`)? Что стало бы с его транзакцией?

---

## Ссылки

- pg_stat_activity: https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STAT-ACTIVITY-VIEW
- Функции управления сеансами (pg_cancel_backend, pg_terminate_backend): https://www.postgresql.org/docs/current/functions-admin.html#FUNCTIONS-ADMIN-SIGNAL
- pg_blocking_pids: https://www.postgresql.org/docs/current/functions-info.html
- Журналирование: https://www.postgresql.org/docs/current/runtime-config-logging.html
- VACUUM: https://www.postgresql.org/docs/current/sql-vacuum.html
- Регламентная очистка (VACUUM vs VACUUM FULL): https://www.postgresql.org/docs/current/routine-vacuuming.html
