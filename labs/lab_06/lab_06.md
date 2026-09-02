# Лабораторная работа №6
## Анализ запросов eshop: EXPLAIN ANALYZE, pg_stat_statements, pgBadger

**Неделя:** 8  
**Ориентировочное время:** 2 занятия (≈ 4 ак. ч.)

---

## Цель работы

- Подключить и использовать расширение `pg_stat_statements`.
- Читать планы выполнения запросов через `EXPLAIN ANALYZE`.
- Идентифицировать дорогостоящие запросы в `eshop` и понять их причины.
- (опционально) Сформировать HTML-отчёт pgBadger из лог-файла.

---

## Предварительные требования

- Завершена лаб. 05: журналирование настроено (`log_min_duration_statement = 500`).
- Прочитана лек. 08.
- В базе `eshop` есть минимум 100 заказов (создать, если нужно):
  ```sql
  INSERT INTO orders (customer_id, status, total_amount)
  SELECT (random()*2+1)::int, 'pending', random()*10000
  FROM   generate_series(1, 100);
  ```

---

## Часть 1. pg_stat_statements

### 1.1. Установить расширение

```sql
-- Выполнить под postgres в базе eshop
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Добавить в postgresql.conf и перезапустить:
-- shared_preload_libraries = 'pg_stat_statements'
-- pg_stat_statements.max  = 10000
-- pg_stat_statements.track = top
```

После изменения `shared_preload_libraries` необходим **перезапуск** PostgreSQL.

```sql
-- Проверить подключение расширения
SELECT * FROM pg_stat_statements LIMIT 1;
```

### 1.2. Сбросить статистику и создать нагрузку

```sql
-- Обнулить накопленную статистику
SELECT pg_stat_statements_reset();

-- Выполнить несколько «аналитических» запросов
SELECT c.name, COUNT(o.id) AS order_count, SUM(o.total_amount) AS revenue
FROM   customers c
LEFT   JOIN orders o ON o.customer_id = c.id
GROUP  BY c.name
ORDER  BY revenue DESC;

SELECT * FROM orders WHERE status = 'pending' ORDER BY created_at;

SELECT p.name, SUM(oi.quantity) AS total_sold
FROM   products p
JOIN   order_items oi ON oi.product_id = p.id
GROUP  BY p.name
ORDER  BY total_sold DESC;
```

Повторите каждый запрос 5–10 раз для накопления статистики.

### 1.3. Читать pg_stat_statements

```sql
-- Топ запросов по суммарному времени выполнения
SELECT LEFT(query, 60)            AS query_preview,
       calls,
       ROUND(total_exec_time::numeric, 2) AS total_ms,
       ROUND(mean_exec_time::numeric,  2) AS mean_ms,
       ROUND(stddev_exec_time::numeric,2) AS stddev_ms,
       shared_blks_read           AS disk_reads
FROM   pg_stat_statements
WHERE  query NOT ILIKE '%pg_stat%'
ORDER  BY total_exec_time DESC
LIMIT  10;
```

Запишите в таблицу:

| query_preview | calls | mean_ms | stddev_ms |
|---------------|-------|---------|-----------|
| ...           | ...   | ...     | ...       |

---

## Часть 2. EXPLAIN ANALYZE

### 2.1. Базовый синтаксис

**Правило безопасности**: для DML-запросов оборачивайте в BEGIN/ROLLBACK.

```sql
BEGIN;
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT c.name, COUNT(o.id)
FROM   customers c
LEFT   JOIN orders o ON o.customer_id = c.id
GROUP  BY c.name;
ROLLBACK;
```

### 2.2. Читать план

В выводе найдите:
- `Seq Scan on orders` — полный перебор таблицы (плохо при большом объёме)
- `cost=0.00..1.03` — оценочная стоимость: до первой строки / до последней
- `actual time=0.012..0.025` — реальное время
- `rows=103 width=8` — оценочное/реальное число строк
- `Buffers: shared hit=5 read=0` — сколько страниц из кэша / с диска

### 2.3. Запрос с медленным JOIN

```sql
-- Запрос без подходящих индексов
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.id, o.status, c.email, c.region,
       SUM(oi.unit_price * oi.quantity) AS total
FROM   orders o
JOIN   customers c ON c.id = o.customer_id
JOIN   order_items oi ON oi.order_id = o.id
WHERE  c.region = 'MSK'
  AND  o.created_at > now() - interval '30 days'
GROUP  BY o.id, o.status, c.email, c.region
ORDER  BY total DESC;
```

Найдите в плане:
- Какой тип JOIN выбрал планировщик (`Hash Join` / `Nested Loop`)?
- Есть ли `Seq Scan`? На какой таблице?
- Какова `actual rows` vs `rows` (расхождение = проблема статистики)?

Запишите ответы в тетрадь/файл.

### 2.4. Сравнение с индексом

```sql
-- Создать индекс
CREATE INDEX idx_customers_region ON customers(region);
CREATE INDEX idx_orders_created_at ON orders(created_at);
CREATE INDEX idx_orders_customer_id ON orders(customer_id);

-- Повторить EXPLAIN ANALYZE
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.id, o.status, c.email, c.region,
       SUM(oi.unit_price * oi.quantity) AS total
FROM   orders o
JOIN   customers c ON c.id = o.customer_id
JOIN   order_items oi ON oi.order_id = o.id
WHERE  c.region = 'MSK'
  AND  o.created_at > now() - interval '30 days'
GROUP  BY o.id, o.status, c.email, c.region
ORDER  BY total DESC;
```

Сравните планы:

| Метрика                      | Без индексов | С индексами |
|------------------------------|--------------|-------------|
| Узел сканирования orders     | ?            | ?           |
| actual time (total), мс      | ?            | ?           |
| shared blks read             | ?            | ?           |

### 2.5. auto_explain (опционально)

```sql
-- Включить для текущего сеанса
LOAD 'auto_explain';
SET auto_explain.log_min_duration = 0;
SET auto_explain.log_analyze = on;

-- Выполнить любой запрос — план появится в лог-файле PostgreSQL
SELECT COUNT(*) FROM order_items;
```

---

## Часть 3. pgBadger (опционально)

### 3.1. Установка

```bash
# Linux (Debian/Ubuntu)
apt-get install pgbadger

# Windows: pgBadger — Perl-скрипт, требует Strawberry Perl
# https://github.com/darold/pgbadger
```

### 3.2. Генерация отчёта

Убедитесь, что `log_min_duration_statement = 0` (или любое малое значение).
Создайте нагрузку (повторите запросы из части 1–2).

```bash
pgbadger /var/log/postgresql/postgresql-$(date +%Y-%m-%d).log \
    -o /tmp/eshop_report.html

# Открыть
xdg-open /tmp/eshop_report.html   # Linux
start /tmp/eshop_report.html       # Windows
```

В отчёте найдите раздел **"Slowest individual queries"** и **"Most frequent queries"**.

---

## Часть 4. Анализ проблемного запроса (итоговое задание)

Найдите в `pg_stat_statements` запрос с наибольшим `mean_exec_time`. Для него:

1. Выполните `EXPLAIN ANALYZE BUFFERS`.
2. Объясните, почему запрос медленный (Seq Scan / плохие оценки / work_mem?).
3. Предложите решение (индекс / переписать JOIN / увеличить work_mem).
4. Если предложили индекс — создайте и сравните планы.

Оформите вывод как таблицу:

| Запрос | Причина медленной работы | Решение | Эффект |
|--------|--------------------------|---------|--------|
| ...    | ...                      | ...     | ...    |

---

## Чек-лист «работа зачтена»

- [ ] `pg_stat_statements` установлен; `SELECT * FROM pg_stat_statements` возвращает строки.
- [ ] Таблица топ-10 запросов заполнена.
- [ ] `EXPLAIN ANALYZE` выполнен до и после добавления индексов; таблица сравнения заполнена.
- [ ] Итоговый анализ проблемного запроса оформлен.

---

## Самостоятельное задание

1. Найдите запрос с наибольшим `stddev_exec_time / mean_exec_time` (нестабильное время). Что это может означать?
2. Что такое `Batches > 1` в узле Hash Join и что это значит для `work_mem`?
3. Почему планировщик иногда предпочитает `Seq Scan` вместо `Index Scan`, даже если индекс существует?

---

## Ссылки

- pg_stat_statements: https://www.postgresql.org/docs/current/pgstatstatements.html
- EXPLAIN: https://www.postgresql.org/docs/current/sql-explain.html
- auto_explain: https://www.postgresql.org/docs/current/auto-explain.html
- pgBadger: https://github.com/darold/pgbadger
