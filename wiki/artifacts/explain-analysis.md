# Анализ медленного запроса (EXPLAIN ANALYZE)

**Источник:** лаб. 06 — «Оптимизация запросов»  
**Кто создаёт:** системный аналитик  
**Назначение:** структурированный анализ медленного запроса: диагностика → гипотеза → решение → измерение эффекта

---

## Зачем этот документ

`EXPLAIN ANALYZE` без структуры — поток цифр. Отчёт заставляет зафиксировать: что было, что сделали, что стало. Без измерений «до» и «после» невозможно доказать, что индекс помог.

> **Запомнить:** любое изменение производительности должно быть измерено **до** и **после**. Иначе оптимизация — это угадывание.

---

## Как правильно запустить EXPLAIN ANALYZE

```sql
-- Для SELECT:
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT * FROM orders WHERE customer_id = 42;

-- Для DML (UPDATE/DELETE) — ОБЯЗАТЕЛЬНО в транзакции с ROLLBACK:
BEGIN;
EXPLAIN (ANALYZE, BUFFERS)
DELETE FROM order_items WHERE order_id = 100;
ROLLBACK;
-- Без ROLLBACK DELETE реально выполнится!
```

> **Ловушка:** `EXPLAIN ANALYZE` для DML **реально выполняет** запрос. Всегда оборачивать в `BEGIN/ROLLBACK`.

---

## Шаблон: отчёт по медленному запросу

```markdown
# Анализ запроса: [краткое описание]

Дата: __________

## Запрос

```sql
-- Вставить исследуемый запрос
SELECT o.id, o.status, c.name
FROM orders o
JOIN customers c ON c.id = o.customer_id
WHERE o.status = 'pending'
  AND o.created_at > now() - interval '7 days';
```

## Источник (pg_stat_statements)

```sql
SELECT query, calls, mean_exec_time, stddev_exec_time, total_exec_time
FROM pg_stat_statements
WHERE query ILIKE '%orders%'
ORDER BY mean_exec_time DESC
LIMIT 10;
```

| query_preview         | calls | mean_ms | stddev_ms | total_ms |
|-----------------------|-------|---------|-----------|----------|
|                       |       |         |           |          |

## EXPLAIN ANALYZE — до оптимизации

```
[вставить вывод EXPLAIN (ANALYZE, BUFFERS)]
```

Тип скана:               ____________________  
Buffers hit/read:        hit=____ read=____  
Actual rows:             ____  
Estimated rows (плановик):____  
Execution time:          ____ ms  

## Проблема

[описать: почему запрос медленный — Seq Scan вместо Index Scan, nested loops на большой таблице, планировщик промахнулся]

## Решение

```sql
-- Создать индекс / переписать запрос / обновить статистику
CREATE INDEX CONCURRENTLY idx_orders_status_created
    ON orders(status, created_at)
    WHERE status = 'pending';

-- Или: обновить статистику
ANALYZE orders;
```

## EXPLAIN ANALYZE — после оптимизации

```
[вставить вывод EXPLAIN (ANALYZE, BUFFERS) после изменения]
```

Тип скана:               ____________________  
Buffers hit/read:        hit=____ read=____  
Execution time:          ____ ms  

## Итог

| Метрика           | До   | После | Изменение |
|-------------------|------|-------|-----------|
| Execution time, ms|      |       | -____%    |
| Тип скана         |      |       |           |
| Buffers read      |      |       |           |

## Причина / Решение / Эффект

| Причина            | Решение             | Эффект               |
|--------------------|---------------------|----------------------|
| Seq Scan на orders | Индекс по status    | -80% execution time  |
```

---

## Словарь терминов EXPLAIN

| Термин | Значение |
|--------|----------|
| `Seq Scan` | Последовательное чтение всей таблицы. Нормально для маленьких таблиц или выборок > 10–20% |
| `Index Scan` | Чтение через индекс с обращением к heap (heap fetch). Хорошо для < 5–10% строк |
| `Index Only Scan` | Все нужные данные есть в индексе, heap не читается. Лучший вариант |
| `Bitmap Heap Scan` | Сначала собирает bitmap страниц через индекс, потом читает heap. Компромисс |
| `Nested Loop` | JOIN: для каждой строки внешней таблицы ищет в внутренней. Хорош при малом внешнем |
| `Hash Join` | JOIN через хэш-таблицу. Хорош для средних таблиц |
| `Merge Join` | JOIN через слияние отсортированных потоков. Хорош для больших отсортированных |
| `cost=X..Y` | Оценка стоимости: X = до первой строки, Y = полная. Условные единицы |
| `rows=N` | Оценка планировщика. Если сильно расходится с actual rows — устаревшая статистика |
| `actual rows=N` | Реально выбрано строк |
| `Buffers: hit=N` | N страниц из shared_buffers (в памяти) — хорошо |
| `Buffers: read=N` | N страниц с диска — медленно |
| `loops=N` | Сколько раз выполнялся этот узел |

---

## Признаки проблем в плане

| Симптом | Вероятная причина | Решение |
|---------|-------------------|---------|
| `Seq Scan` на большой таблице | Нет индекса или планировщик не использует | Создать индекс; проверить `ANALYZE` |
| `rows` >> `actual rows` | Устаревшая статистика | `ANALYZE table` |
| `rows` << `actual rows` | Планировщик недооценил | Увеличить `default_statistics_target` |
| Много `Buffers: read` | Данные не в кэше | Увеличить `shared_buffers`; добавить индекс |
| `Nested Loop` с большим `loops` | Неэффективный JOIN | Добавить индекс на колонку FK; переписать |
| `Filter: (rows removed by filter=N)` | Индекс есть, но фильтрация после чтения | Нужен composite index с этой колонкой |

---

## pg_stat_statements: что за колонки

```sql
-- Сначала проверить, что расширение подключено:
SELECT * FROM pg_extension WHERE extname = 'pg_stat_statements';

-- Топ медленных запросов:
SELECT
    left(query, 80) AS query_preview,
    calls,
    round(mean_exec_time::numeric, 2)   AS mean_ms,
    round(stddev_exec_time::numeric, 2) AS stddev_ms,
    round(total_exec_time::numeric, 2)  AS total_ms
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 20;
```

| Колонка | Значение |
|---------|----------|
| `calls` | Сколько раз запрос выполнялся |
| `mean_exec_time` | Среднее время выполнения (мс) |
| `stddev_exec_time` | Стандартное отклонение — если велико, время нестабильно |
| `total_exec_time` | Суммарное время всех вызовов |
| `shared_blks_hit` | Обращений к кэшу |
| `shared_blks_read` | Обращений к диску |

> **Запомнить:** `stddev_exec_time` >> `mean_exec_time` — признак нестабильности. Значит, запрос иногда попадает в кэш, иногда нет.

---

> **Связанные страницы:** [[concepts/indexes]], [[artifacts/db-health-report]], [[tools/dbeaver]]
