# Отчёт о состоянии БД

**Источник:** лаб. 05 — «Мониторинг производительности»  
**Кто создаёт:** системный аналитик (заполняет запросами к pg_stat_*)  
**Периодичность:** еженедельно или после инцидента

---

## Зачем этот документ

Мониторинг без отчёта — наблюдение без памяти. Отчёт фиксирует базовый уровень (baseline), от которого отсчитываются деградации. Через 3–4 недели заполненных отчётов видны тренды: растущий bloat, снижение cache hit ratio, накопление idle in transaction.

> **Запомнить:** отчёт не сигнализирует «плохо/хорошо» сам по себе. Важна **динамика**: если cache hit ratio упал с 99% до 94% — это тревожный сигнал, даже если 94% само по себе «неплохо».

---

## Шаблон отчёта

```markdown
# Отчёт о состоянии БД eshop

Дата: __________  
PostgreSQL: SELECT version();  

---

## 1. Соединения

Запрос:
```sql
SELECT state, count(*)
FROM pg_stat_activity
WHERE datname = 'eshop'
GROUP BY state;
```

| Параметр                   | Значение |
|----------------------------|----------|
| Всего соединений           |          |
| active                     |          |
| idle                       |          |
| idle in transaction        |          |
| Макс. длительность запроса |          |
| max_connections (лимит)    |          |

---

## 2. Cache Hit Ratio

Запрос:
```sql
SELECT
    sum(blks_hit) * 100.0 / nullif(sum(blks_hit) + sum(blks_read), 0) AS cache_hit_ratio
FROM pg_stat_database
WHERE datname = 'eshop';
```

| Метрика          | Значение |
|------------------|----------|
| Cache Hit Ratio  |          |
| Целевой порог    | ≥ 99%    |

---

## 3. Dead Tuples (таблично-уровневый bloat)

Запрос:
```sql
SELECT
    relname,
    n_live_tup,
    n_dead_tup,
    round(n_dead_tup * 100.0 / nullif(n_live_tup + n_dead_tup, 0), 1) AS dead_pct,
    last_autovacuum
FROM pg_stat_user_tables
WHERE relname IN ('customers','orders','order_items','products')
ORDER BY dead_pct DESC;
```

| Таблица     | n_live_tup | n_dead_tup | dead_pct | last_autovacuum |
|-------------|-----------|------------|----------|-----------------|
| customers   |           |            |          |                 |
| orders      |           |            |          |                 |
| order_items |           |            |          |                 |
| products    |           |            |          |                 |

> Порог: dead_pct > 10% — рассмотреть ручной VACUUM или снизить autovacuum_vacuum_scale_factor.

---

## 4. Эксперимент VACUUM

```sql
-- Создать нагрузку:
UPDATE orders SET status = status WHERE status = 'new';

-- Проверить до:
SELECT n_live_tup, n_dead_tup FROM pg_stat_user_tables WHERE relname = 'orders';

-- Запустить VACUUM:
VACUUM orders;

-- Проверить после:
SELECT n_live_tup, n_dead_tup FROM pg_stat_user_tables WHERE relname = 'orders';
```

| Этап              | n_live_tup | n_dead_tup |
|-------------------|-----------|------------|
| До UPDATE         |           |            |
| После UPDATE      |           |            |
| После VACUUM      |           |            |
| После VACUUM FULL |           |            |

---

## 5. Неиспользуемые индексы

Запрос:
```sql
SELECT
    schemaname,
    relname AS table_name,
    indexrelname AS index_name,
    idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND indexrelname NOT LIKE 'pg_%'
ORDER BY relname;
```

| Таблица | Индекс | idx_scan |
|---------|--------|----------|
|         |        | 0        |

> Индексы с idx_scan = 0 — кандидаты на удаление (проверить: может, ещё не было нагрузки на этот запрос).

---

## 6. Настройки логирования

Запрос:
```sql
SHOW log_min_duration_statement;  -- логировать медленные запросы
SHOW log_connections;
SHOW log_disconnections;
SHOW log_line_prefix;
```

| Параметр                     | Значение | Рекомендация        |
|------------------------------|----------|---------------------|
| log_min_duration_statement   |          | 1000 (1 сек)        |
| log_connections              |          | on                  |
| log_disconnections           |          | on                  |

---

## 7. Выводы и рекомендации

```markdown
- [ ] Cache hit ratio: ____% — [норма / ниже порога — увеличить shared_buffers]
- [ ] Bloat: таблица ____ dead_pct = ____% — [норма / требует VACUUM]
- [ ] Unused indexes: _____ — [оставить / удалить]
- [ ] Передать DBA: ____________________
```
```

---

## Ключевые запросы для запоминания

| Что измеряем | Системный каталог | Колонки |
|---|---|---|
| Активные соединения | `pg_stat_activity` | `state`, `query_start`, `query` |
| Кэш-попадания | `pg_stat_database` | `blks_hit`, `blks_read` |
| Bloat таблиц | `pg_stat_user_tables` | `n_dead_tup`, `n_live_tup`, `last_autovacuum` |
| Использование индексов | `pg_stat_user_indexes` | `idx_scan`, `idx_tup_read` |
| Медленные запросы | `pg_stat_statements` | `mean_exec_time`, `calls`, `total_exec_time` |

---

> **Связанные страницы:** [[concepts/monitoring]], [[concepts/wal-mvcc]], [[artifacts/explain-analysis]]
