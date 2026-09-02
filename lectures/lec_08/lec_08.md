# Лекция 8. Анализ медленных запросов: EXPLAIN, pg_stat_statements, pgBadger

**Неделя:** 8

---

## Цель лекции

По итогам лекции студент:

- знает, как использовать `pg_stat_statements` для поиска самых дорогих запросов;
- умеет читать план выполнения (`EXPLAIN ANALYZE`) и выявлять узкие места;
- понимает, как `auto_explain` и `pgBadger` помогают анализировать медленные запросы;
- умеет передать DBA конкретный запрос и план для анализа.

---

## 1. pg_stat_statements: накопительная статистика запросов

`pg_stat_statements` — расширение PostgreSQL, которое накапливает статистику выполнения всех запросов.

### 1.1. Установка

```sql
-- shared_preload_libraries = 'pg_stat_statements'  (в postgresql.conf, перезапуск)
CREATE EXTENSION pg_stat_statements;
```

### 1.2. Самые дорогие запросы по суммарному времени

```sql
SELECT LEFT(query, 120)                   AS query_preview,
       calls,
       ROUND(total_exec_time::numeric, 0)  AS total_ms,
       ROUND(mean_exec_time::numeric, 1)   AS avg_ms,
       ROUND(stddev_exec_time::numeric, 1) AS stddev_ms,
       rows,
       shared_blks_hit,
       shared_blks_read                    -- много = данные не в кэше
FROM   pg_stat_statements
ORDER  BY total_exec_time DESC
LIMIT  10;
```

### 1.3. Нестабильные запросы (большой разброс времени)

```sql
SELECT LEFT(query, 120) AS query_preview,
       calls,
       ROUND(mean_exec_time::numeric, 1)  AS avg_ms,
       ROUND(stddev_exec_time::numeric, 1) AS stddev_ms,
       ROUND(max_exec_time::numeric, 1)   AS max_ms
FROM   pg_stat_statements
WHERE  calls > 100
ORDER  BY stddev_exec_time DESC
LIMIT  10;
```

### 1.4. Сброс статистики

```sql
SELECT pg_stat_statements_reset();
```

---

## 2. auto_explain: автоматическое логирование планов

`auto_explain` автоматически записывает план выполнения медленных запросов в лог — не нужно ловить их вручную.

### 2.1. Настройка

```ini
# postgresql.conf
shared_preload_libraries          = 'pg_stat_statements,auto_explain'
auto_explain.log_min_duration     = 1000   # планы для запросов > 1 с
auto_explain.log_analyze          = on     # реальное время выполнения
auto_explain.log_buffers          = on     # информация о буферах
auto_explain.log_format           = text
auto_explain.log_nested_statements = on
```

### 2.2. Пример записи в логе

```
2024-09-01 15:22:33 MSK [5678]: LOG:  duration: 3451.234 ms  plan:
Query Text: SELECT o.id, c.name FROM orders o JOIN customers c ON o.customer_id = c.id
            WHERE o.created_at > '2024-01-01'
Seq Scan on orders  (cost=0.00..98432.50 rows=2500000 width=12)
                    (actual time=0.123..3420.456 rows=2500000 loops=1)
Planning Time: 1.234 ms
Execution Time: 3451.234 ms
```

---

## 3. EXPLAIN ANALYZE: читаем план выполнения

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT o.id, c.name, o.total
FROM   orders o
JOIN   customers c ON o.customer_id = c.id
WHERE  o.created_at > '2024-01-01'
ORDER  BY o.total DESC
LIMIT  100;
```

> **Важно:** `EXPLAIN ANALYZE` **реально выполняет** запрос. Для `INSERT`/`UPDATE`/`DELETE`:
> ```sql
> BEGIN;
> EXPLAIN ANALYZE UPDATE orders SET status = 'processed' WHERE id = 1;
> ROLLBACK;
> ```

### 3.1. Ключевые узлы плана

| Узел                  | Что делает                                                       | Когда появляется             |
|-----------------------|------------------------------------------------------------------|------------------------------|
| `Seq Scan`            | Полный перебор таблицы                                           | Нет индекса или таблица мала |
| `Index Scan`          | Поиск по индексу + чтение таблицы                                | Есть индекс, выбирается мало строк |
| `Index Only Scan`     | Данные берутся только из индекса (covering index)                | Все нужные колонки в индексе |
| `Bitmap Heap Scan`    | Несколько диапазонов из индекса → читается таблица               | Много строк по индексу       |
| `Hash Join`           | Строит хеш-таблицу из меньшего набора                            | Большие JOIN без индекса     |
| `Nested Loop`         | Для каждой строки внешней — ищет во внутренней                  | Небольшие наборы с индексом  |
| `Sort`                | Сортирует результат                                              | ORDER BY, GROUP BY           |
| `Hash Aggregate`      | Агрегация через хеш-таблицу                                      | GROUP BY                     |

### 3.2. Чтение строки плана

```
Seq Scan on orders  (cost=0.00..98432.50 rows=2500000 width=12)
                    (actual time=0.123..3420.456 rows=2500000 loops=1)
  Buffers: shared hit=5432 read=93000
```

| Элемент                   | Значение                                              |
|---------------------------|-------------------------------------------------------|
| `cost=0.00..98432.50`     | Оценочная стоимость (условные единицы)                |
| `rows=2500000` (оценка)   | Оценочное количество строк (планировщик)              |
| `actual time=0.123..3420` | Реальное время (старт..финиш)                         |
| `rows=2500000` (actual)   | Реальное количество строк                             |
| `shared hit=5432`         | Блоков из кэша (shared_buffers)                      |
| `shared read=93000`       | Блоков с диска — много = нагрузка на I/O             |

### 3.3. Признаки проблем в плане

| Признак                                             | Интерпретация                                       | Действие                              |
|-----------------------------------------------------|-----------------------------------------------------|---------------------------------------|
| `rows=100` (оценка) vs `rows=2500000` (реально)     | Статистика устарела                                 | `ANALYZE table_name;`                 |
| `Seq Scan` на большой таблице                       | Нет индекса или не используется                     | Создать индекс; проверить `WHERE`     |
| `Sort` с `Batches: 5`                               | Сортировка вышла на диск; `work_mem` мал            | Увеличить `work_mem` для сеанса       |
| Много `shared read`, мало `shared hit`              | Данные не в кэше                                    | Обсудить с DBA увеличение shared_buffers |

### 3.4. Онлайн-визуализация плана

Скопировать вывод `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` и вставить на:
- https://explain.depesz.com — цветовое выделение дорогих узлов
- https://explain.tensor.ru — русскоязычная альтернатива

---

## 4. pgBadger: анализ лог-файлов

`pgBadger` читает лог-файлы PostgreSQL и генерирует HTML-отчёт с топ медленных запросов, статистикой блокировок, графиками нагрузки.

### 4.1. Требования

- Настроен `log_line_prefix` (см. лекцию 7).
- Задан `log_min_duration_statement`.

### 4.2. Команды

```bash
# Анализ одного лог-файла
pgbadger /var/log/postgresql/postgresql-2024-09-01.log -o report.html

# Анализ нескольких файлов
pgbadger /var/log/postgresql/postgresql-*.log -o report.html

# Открыть отчёт
start report.html    # Windows
open report.html     # macOS
```

---

## 5. Что передавать DBA при анализе медленного запроса

```markdown
## Запрос для анализа

### Запрос (полный текст)
SELECT o.id, c.name, o.total
FROM   orders o
JOIN   customers c ON o.customer_id = c.id
WHERE  o.created_at > '2024-01-01'
ORDER  BY o.total DESC;

### Контекст
- База: myapp_prod
- Таблица orders: ~3 млн строк
- Среднее время: 4,5 с (по pg_stat_statements)
- Частота: ~500 вызовов в сутки

### Вывод EXPLAIN ANALYZE
[вставить полный вывод EXPLAIN (ANALYZE, BUFFERS)]

### Наблюдения
- Seq Scan на orders: 3 млн строк, нет индекса по created_at
- shared_blks_read = 93000 — много чтений с диска

### Ожидание
Запрос должен выполняться < 200 мс (SLA отчёта).
```

---

## 6. Итоги лекции

После этой лекции студент умеет:

- **Найти топ дорогих запросов** через `pg_stat_statements` (сортировка по `total_exec_time`, `mean_exec_time`, `shared_blks_read`).
- **Прочитать план EXPLAIN ANALYZE**: найти `Seq Scan`, расхождение `rows` (оценка vs факт), `Batches > 1`, `shared blks read`.
- **Безопасно выполнить EXPLAIN** для DML-запроса: обернуть в `BEGIN` / `ROLLBACK`.
- **Настроить `auto_explain`** для автоматического логирования планов медленных запросов.
- **Передать артефакты DBA**: текст запроса + EXPLAIN ANALYZE + строка из pg_stat_statements.

---

## Ссылки

- pg_stat_statements: https://www.postgresql.org/docs/current/pgstatstatements.html
- EXPLAIN: https://www.postgresql.org/docs/current/sql-explain.html
- Использование EXPLAIN: https://www.postgresql.org/docs/current/using-explain.html
- auto_explain: https://www.postgresql.org/docs/current/auto-explain.html
- pgBadger: https://pgbadger.darold.net
- explain.depesz.com: https://explain.depesz.com
