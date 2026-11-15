# Отчёт о здоровье БД eshop

**Группа:** [Группа]  
**Студент:** [ФИО]  
**Дата:** [Дата]  
**Инстанс:** localhost:5432

## 1. Подключения

```sql
SELECT count(*) AS total_connections,
       count(*) FILTER (WHERE state = 'active') AS active,
       count(*) FILTER (WHERE state = 'idle') AS idle,
       count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_tx
FROM pg_stat_activity;
```

| Метрика | Значение |
|---------|----------|
| Всего подключений | [число] |
| Активные | [число] |
| Idle | [число] |
| Idle in transaction | [число] |

## 2. Кэш

```sql
SELECT sum(heap_blks_read) AS heap_read,
       sum(heap_blks_hit)  AS heap_hit,
       sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read))::real AS ratio
FROM pg_statio_user_tables;
```

| Метрика | Значение |
|---------|----------|
| heap_read | [число] |
| heap_hit | [число] |
| Cache hit ratio | [0.xx] |

## 3. Dead tuples

| Таблица | dead_tuples | n_dead_tup (pg_stat) |
|---------|-------------|---------------------|
| customers | [число] | [число] |
| products | [число] | [число] |
| orders | [число] | [число] |
| order_items | [число] | [число] |

## 4. Эксперимент VACUUM (таблица products)

| Шаг | size | dead_tuples | n_dead_tup |
|-----|------|-------------|------------|
| До UPDATE | [размер] | [число] | [число] |
| После UPDATE 100 строк | [размер] | [число] | [число] |
| После VACUUM ANALYZE | [размер] | [число] | [число] |
| После VACUUM FULL | [размер] | [число] | [число] |

**Вывод:** [Объяснение результатов]

## 5. Неиспользуемые индексы

```sql
SELECT indexrelname, idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0;
```

| Индекс | idx_scan |
|--------|----------|
| [индекс] | 0 |

Количество неиспользуемых индексов: [число]

## 6. Журналирование

| Параметр | Значение |
|----------|----------|
| log_min_duration_statement | [мс] |
| log_statement | [level] |
| log_line_prefix | [строка] |

Медленных запросов (>= 500ms): [число]

## 7. Выводы и рекомендации

1. [Рекомендация 1]
2. [Рекомендация 2]
3. [Рекомендация 3]
