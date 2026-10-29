# Проблема N+1 запросов

Проблема N+1 возникает когда приложение получает список из N объектов одним запросом, а затем выполняет ещё по одному запросу на каждый объект — итого N+1 запросов вместо 2. Главный источник — ORM с ленивой загрузкой связей (Django ORM, Hibernate, ActiveRecord).

Пользователь не видит N+1 как один «медленный запрос» — он видит лагающий экран. Каждый отдельный запрос быстрый (0,05 мс), но их 100–10 000 за один рендер страницы, плюс сетевые round-trip между приложением и БД.

---

## Как выглядит в pg_stat_statements

Признаки N+1: второй запрос вызывается ровно в N раз чаще первого, `avg_ms` маленький, `total_ms` — большой.

| query_preview                                              | calls   | avg_ms | total_ms |
| ---------------------------------------------------------- | ------- | ------ | -------- |
| `SELECT … FROM orders WHERE customer_id = $1 LIMIT $2`     | 1 200   | 0,4    | 480      |
| `SELECT … FROM order_items WHERE order_id = $1`            | 120 000 | 0,05   | 6 000    |

`calls` второго запроса ровно в 100 раз больше первого → каждый из 1 200 вызовов возвращал список из 100 заказов и затем запрашивал позиции каждого.

`pg_stat_statements` показывает только серверное время. Сетевые задержки не учитываются — реальное время ожидания пользователя выше.

---

## Пример из eshop

```sql
-- Запрос 1 (×1): получить заказы клиента
SELECT id, status, total_amount, created_at
FROM   orders
WHERE  customer_id = $1
ORDER  BY created_at DESC
LIMIT  50;

-- Запросы 2..51 (×50): позиции каждого заказа по отдельности
SELECT product_id, quantity, unit_price
FROM   order_items
WHERE  order_id = $1;   -- вызывается 50 раз

-- ✅ Решение: один батч-запрос
SELECT product_id, quantity, unit_price, order_id
FROM   order_items
WHERE  order_id = ANY($1);   -- $1 = массив из 50 id заказов
```

---

## Как обнаружить

```sql
-- Запросы, подозрительно частые — потенциальный N+1
SELECT LEFT(regexp_replace(query, '\s+', ' ', 'g'), 80) AS query_preview,
       calls,
       ROUND(mean_exec_time::numeric, 2) AS avg_ms,
       ROUND(total_exec_time::numeric, 0) AS total_ms
FROM   pg_stat_statements
WHERE  dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
  AND  query NOT ILIKE '%pg_%'
ORDER  BY calls DESC
LIMIT  20;
```

Ищите: `calls` одного запроса кратно `calls` другого (множитель = размер списка), `avg_ms` < 1 мс, `total_ms` значительный.

---

## Решения

### 1. Батч-запрос с `ANY`

```sql
-- Приложение собирает массив order_id из результата первого запроса
-- и передаёт его одним параметром
SELECT order_id, product_id, quantity, unit_price
FROM   order_items
WHERE  order_id = ANY($1::bigint[]);
```

Было: 1 + 50 запросов. Стало: 2 запроса.

### 2. JOIN в одном запросе

```sql
SELECT o.id, o.status, oi.product_id, oi.quantity, oi.unit_price
FROM   orders o
JOIN   order_items oi ON oi.order_id = o.id
WHERE  o.customer_id = $1
ORDER  BY o.created_at DESC, o.id;
```

Подходит когда список и вложенные данные нужны вместе. Недостаток: дублирование полей заказа в каждой строке результата.

### 3. Требование от SA

Проблема N+1 часто появляется из-за неточного требования: «показать список заказов с позициями». Правильная формулировка:

> Экран «Заказы клиента»: показать последние 50 заказов. Позиции каждого заказа — одним батч-запросом, не по одному. Приёмочный критерий: не более 3 запросов к БД на открытие экрана при любом размере списка.

---

## Связь с индексами

После исправления N+1 оставшиеся 2 запроса могут сами стать медленными — теперь виден их план. Проверьте индекс по `order_items(order_id)`: без него батч-запрос на 50 id сделает Seq Scan всей таблицы.

```sql
-- Проверить наличие индекса
SELECT indexname, indexdef
FROM   pg_indexes
WHERE  tablename = 'order_items' AND indexdef ILIKE '%order_id%';
```

---

> **Связанные страницы:** [[monitoring]] · [[indexes]] · [[../artifacts/explain-analysis|EXPLAIN Analysis]]  
> **Источники:** [[../lectures/lec_08]]
