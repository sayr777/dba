# Лабораторная работа №7
## Индексы, autovacuum, PgBouncer для eshop

**Неделя:** 9  
**Ориентировочное время:** 2 занятия (≈ 4 ак. ч.)  
**Среда:** Windows, PowerShell, PostgreSQL 18, DBeaver / psql

---

## Цель работы

- Создавать частичные, составные и функциональные индексы под конкретные запросы.
- Контролировать autovacuum и настраивать его для активных таблиц.
- Установить и настроить PgBouncer, переключить подключение на пул соединений.

## Ход работы

| Часть | Что делаем | Время |
|---|---|---|
| 0 | Проверяем базу после лаб. 06 и делаем распределение статусов реалистичным | 10 мин |
| 1 | Создаём индексы разных видов и сравниваем планы до и после | 60 мин |
| 2 | Наблюдаем, когда запускается autovacuum, и настраиваем его для `orders` | 20 мин |
| 3 | Устанавливаем PgBouncer, проверяем пул под нагрузкой и ограничения | 70 мин |
| 4 | Составляем обоснование PgBouncer по своим измерениям | 20 мин |

---

## Предварительные требования

- Завершена лаб. 06: база наполнена (20 000 / 1 000 / 200 000 / 600 000 строк), индексы из п. 2.4 созданы, `pg_stat_statements` подключён.
- Прочитана [Лек. 09 — Оптимизация производительности. Индексы. Connection Pooling](../../lectures/lec_09/lec_09.md).
- Роль `app_backend` из лаб. 02 существует (пароль `backend_pass_2024`). Через роль `eshop_app` у неё есть `SELECT` на `orders`.
- Части 0–2 выполняются под `postgres` в базе `eshop`, часть 3 — под `app_backend`.

> **DBeaver.** Все шаги частей 0–2 выполняйте в режиме **Auto-Commit**.
> Пункт **Smart commit mode** в меню кнопки режима транзакций должен быть **выключен**: иначе после первого `UPDATE`
> DBeaver сам переключится в Manual Commit, и `VACUUM` / `CREATE INDEX CONCURRENTLY` выдадут ошибку
> «не может выполняться внутри блока транзакции». Если ошибка возникла: **Rollback** → Auto-Commit → повторить шаг.
>
> **EXPLAIN.** Выполняйте `EXPLAIN (ANALYZE, BUFFERS)` через `Ctrl+Enter`. Кнопка «Explain execution plan» не показывает
> `Execution Time` и `Buffers`.
>
> **psql в PowerShell.** Каталог `bin` PostgreSQL обычно не добавлен в `PATH`. Задайте переменную один раз на сеанс:
>
> ```powershell
> $pg = "C:\Program Files\PostgreSQL\18\bin"
> & "$pg\psql.exe" --version
> ```

---

## Часть 0. Подготовка данных

### 0.1. Проверить исходное состояние

**Шаг 1. Проверить объём данных:**

```sql
SELECT (SELECT count(*) FROM customers)   AS customers,     -- 20 000
       (SELECT count(*) FROM products)    AS products,      --  1 000
       (SELECT count(*) FROM orders)      AS orders,        -- 200 000
       (SELECT count(*) FROM order_items) AS order_items;   -- 600 000
```

Если значения меньше — выполните скрипт наполнения из лаб. 06 («Наполнение базы тестовыми данными»).

**Шаг 2. Проверить, какие индексы уже есть:**

```sql
SELECT tablename, indexname, indexdef
FROM   pg_indexes
WHERE  schemaname = 'public'
  AND  tablename IN ('orders', 'order_items', 'customers', 'products')
ORDER  BY 1, 2;
```

Ожидаемо: ключи (`*_pkey`, `customers_email_key`) и индексы из лаб. 06, п. 2.4:
`idx_customers_region`, `idx_orders_created_at`, `idx_orders_customer_id`, `idx_order_items_order`. Их **не удаляйте**.

**Шаг 3. Удалить индекс по `status`, если он есть** (мог остаться после самостоятельного задания 3 лаб. 06).
Иначе в шаге 1.1 не будет видно работы без индекса.

```sql
SELECT indexname, indexdef
FROM   pg_indexes
WHERE  tablename = 'orders'
  AND  indexdef LIKE '%(status%';   -- индексы, где status — первый столбец
```

Если запрос вернул строки — удалите каждый найденный индекс по имени из `indexname`, например:

```sql
DROP INDEX idx_orders_status;
```

### 0.2. Реалистичное распределение статусов

В лаб. 06 статусы распределены поровну, по 20 %. На 20 % строк индекс по `status` не помогает — это вывод самостоятельного задания 3 лаб. 06.
В реальном магазине активных заказов мало, а доставленных большинство.

**Шаг 1. Перераспределить статусы** (скрипт целиком, `Alt+X`):

```sql
SELECT setseed(0.42);   -- одинаковые данные у всех студентов

UPDATE orders o
SET    status = CASE
                    WHEN g.r < 0.02 THEN 'pending'      --  2 %
                    WHEN g.r < 0.05 THEN 'processing'   --  3 %
                    WHEN g.r < 0.10 THEN 'shipped'      --  5 %
                    WHEN g.r < 0.95 THEN 'delivered'    -- 85 %
                    ELSE                 'cancelled'    --  5 %
                END
FROM   (SELECT id, random() AS r FROM orders) AS g
WHERE  g.id = o.id;

VACUUM ANALYZE orders;   -- UPDATE оставил 200 000 мёртвых версий строк; ANALYZE обновляет статистику

SELECT status, count(*) FROM orders GROUP BY status ORDER BY 2 DESC;
```

> `random()` вычисляется один раз на строку в подзапросе `g`, поэтому все ветки `CASE` сравнивают одно и то же значение.

**Шаг 2. Сверить результат.** Данные одинаковые у всех, поэтому числа должны совпасть точно:

| status | count |
|---|---|
| delivered | 170 033 |
| cancelled | 10 098 |
| shipped | 10 036 |
| processing | 5 911 |
| pending | 3 922 |

Если числа другие — данные лаб. 06 отличаются от эталона. Выполните скрипт наполнения из лаб. 06 заново, затем шаг 0.2.

---

## Часть 1. Индексы

> Сравнивайте не только `Execution Time`, но и `Buffers: shared hit/read`. Время зависит от кэша и колеблется между запусками,
> а число прочитанных страниц стабильно.
>
> В PostgreSQL 18 `EXPLAIN ANALYZE` выводит `Buffers` по умолчанию. Параметр `BUFFERS` оставлен для совместимости с PG 16–17.

### 1.1. Запрос без индекса

Отправная точка: как PostgreSQL ищет активные заказы, когда индекса по `status` нет.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE status = 'pending';
```

Запишите: тип узла = ___, `Execution Time` = ___ ms, `Buffers: shared hit` = ___, `Rows Removed by Filter` = ___

Ожидаемо: `Seq Scan`, `Rows Removed by Filter` = 196 078 — прочитана вся таблица ради 2 % строк.

> Планировщик может выбрать **параллельный** план: `Gather` → `Parallel Seq Scan`, `Workers Launched: 2`.
> Тогда таблицу читают 3 процесса, и `Rows Removed by Filter` показан **на один процесс** (≈ 65 359, `loops=3`).
> Всего отброшено 65 359 × 3 ≈ 196 078 строк — столько же, сколько при обычном Seq Scan.

### 1.2. Обычный B-tree индекс

**B-tree** — индекс по умолчанию в PostgreSQL. Он хранит значения столбца в отсортированном дереве
и ссылку на строку таблицы для каждого значения. По дереву PostgreSQL находит нужные строки без чтения всей таблицы.

**Шаг 1. Создать индекс по `status`:**

```sql
CREATE INDEX idx_orders_status ON orders(status);
```

**Шаг 2. Повторить запрос из 1.1 и сравнить план:**

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE status = 'pending';
```

Запишите: тип узла = ___, `Execution Time` = ___ ms, `Buffers: shared hit` = ___. Ускорение относительно 1.1: × ___

Скорее всего, вы увидите **Bitmap Heap Scan** с вложенным **Bitmap Index Scan**, а не Index Scan.

Индекс не обязывает PostgreSQL его использовать. Планировщик оценивает, сколько строк вернёт запрос,
и выбирает самый дешёвый способ чтения. Представьте книгу на 3 640 страниц с предметным указателем в конце:

| Узел | Как ищем в книге | Когда выгодно |
|---|---|---|
| **Seq Scan** | Читаем книгу целиком, страницу за страницей | Нужна большая часть книги. Перелистывать указатель дольше, чем читать подряд |
| **Index Scan** | По указателю находим страницу, открываем, возвращаемся в указатель, открываем следующую… | Нужно несколько строк. Или нужен порядок указателя (`ORDER BY … LIMIT`) |
| **Bitmap Heap Scan** | Сначала выписываем из указателя **все** номера страниц, сортируем список, потом открываем страницы по порядку, каждую один раз | Нужны сотни или тысячи строк: так не прыгаем по книге туда-обратно |
| **Index Only Scan** | Ответ есть прямо в указателе, книгу не открываем | Запросу нужны только столбцы, которые есть в индексе |

План читается **снизу вверх**: узел со стрелкой `->` выполняется первым.

```text
Bitmap Heap Scan on orders                     ← шаг 2: читаем страницы таблицы по списку
  Heap Blocks: exact=1639                         открыли 1 639 страниц, каждую один раз
  ->  Bitmap Index Scan on idx_orders_status   ← шаг 1: по индексу составили список страниц
        Buffers: shared hit=6                     в индексе прочитали всего 6 страниц
```

Запросу нужны 3 922 строки, и они лежат на 1 639 разных страницах. Index Scan ходил бы в таблицу 3 922 раза
в случайном порядке, на одни и те же страницы по нескольку раз. Bitmap Heap Scan открывает каждую страницу один раз.

**Шаг 3. Узнать размер индекса** (понадобится для сравнения в 1.3):

```sql
SELECT pg_size_pretty(pg_relation_size('idx_orders_status')) AS size_full;
```

Размер индекса: ___

> Индекс содержит запись для **каждой** из 200 000 строк, хотя запросу нужны только `pending` (2 %).
> 85 % записей относятся к `delivered`, а для них индекс бесполезен: планировщик всё равно выбирает Seq Scan.

### 1.3. Частичный индекс

**Частичный индекс** — индекс с условием `WHERE`. Он хранит записи только для строк, которые подходят под это условие.
Остальные строки в индекс не попадают.

Активные заказы (`pending`, `processing`) — самая частая выборка: их обрабатывают менеджеры и приложение.
Но в таблице их всего 5 %. Индексировать остальные 95 % строк не нужно.

**Шаг 1. Удалить полный индекс из 1.2:**

```sql
DROP INDEX idx_orders_status;
```

Иначе планировщик выберет полный индекс, и сравнение потеряет смысл.

**Шаг 2. Создать частичный индекс только по активным заказам:**

```sql
CREATE INDEX idx_orders_active ON orders(status)
    WHERE status IN ('pending', 'processing');
```

**Шаг 3. Узнать размер частичного индекса:**

```sql
SELECT pg_size_pretty(pg_relation_size('idx_orders_active')) AS size_partial;
```

Размер полного индекса (из 1.2): ___, частичного: ___. Во сколько раз меньше: ___

**Шаг 4. Проверить запрос по активному статусу:**

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE status = 'pending';
```

Запишите: тип узла = ___, имя индекса = ___, `Execution Time` = ___ ms.

Планировщик проверяет: `status = 'pending'` входит в условие индекса `status IN ('pending', 'processing')`.
Значит, все нужные строки есть в индексе, и его можно использовать.

**Шаг 5. Проверить запрос по неактивному статусу:**

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE status = 'delivered';
```

Запишите: тип узла = ___.

Ожидаемо Seq Scan. Строк `delivered` в частичном индексе нет. Даже полный индекс здесь бесполезен:
запросу нужно 85 % таблицы, и прочитать её целиком быстрее.

**Вывод.** Частичный индекс в разы меньше полного и так же ускоряет нужный запрос.
Он меньше занимает в кэше и меньше замедляет `INSERT` и `UPDATE`.

> **Ограничение.** Частичный индекс используется, только если условие запроса **логически входит** в условие индекса.
> Запрос `WHERE status = $1` из приложения (значение параметра неизвестно при планировании) может его не использовать:
> планировщик не может доказать, что `$1` — это `pending` или `processing`.

### 1.4. Составной индекс: порядок столбцов

**Составной индекс** — индекс по нескольким столбцам. Записи в нём отсортированы сначала по первому столбцу,
внутри одинаковых значений — по второму. Поэтому порядок столбцов важен.

Типичный запрос менеджера: новые заказы за последние 30 дней.
Условие на `status` — равенство (≈ 2 % строк), на `created_at` — диапазон (≈ 4 % строк). Вместе — ≈ 0,1 %, около 150 заказов.

**Шаг 1. Выполнить запрос с одностолбцовыми индексами** (`idx_orders_created_at` из лаб. 06 и `idx_orders_active` из 1.3):

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
WHERE  status = 'pending'
  AND  created_at >= now() - INTERVAL '30 days';
```

Ожидаемо: узел `BitmapAnd`. Планировщик читает два индекса — около 3 900 и 8 100 записей —
и оставляет только строки, которые есть в обоих результатах.

**Шаг 2. Создать составной индекс (равенство первым, диапазон вторым):**

```sql
CREATE INDEX idx_orders_status_created ON orders(status, created_at);
```

**Шаг 3. Повторить запрос из шага 1:**

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
WHERE  status = 'pending'
  AND  created_at >= now() - INTERVAL '30 days';
```

Ожидаемо: `Index Scan using idx_orders_status_created`.

| Вариант | Узел и индекс | Buffers (hit + read) | Execution Time, мс |
|---------|---------------|----------------------|--------------------|
| Шаг 1: одностолбцовые индексы |  |  |  |
| Шаг 3: `(status, created_at)` |  |  |  |

Правило: **сначала столбцы с равенством, потом столбец с диапазоном**.
В индексе `(status, created_at)` записи `pending` за 30 дней лежат подряд: индекс читает только нужные ≈ 150 записей.

**Шаг 4 (опционально). Проверить правило на обратном порядке:**

```sql
CREATE INDEX idx_orders_created_status ON orders(created_at, status);

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
WHERE  status = 'pending'
  AND  created_at >= now() - INTERVAL '30 days';

DROP INDEX idx_orders_created_status;
```

Индекс `(created_at, status)` пришлось бы просматривать по всем ≈ 8 000 заказам за 30 дней и отбрасывать остальные статусы.
Ожидаемо: планировщик его **не выбирает** и снова использует `idx_orders_status_created` — он оценил обратный порядок дороже.

### 1.5. CREATE INDEX CONCURRENTLY (безопасное создание в production)

Обычный `CREATE INDEX` берёт блокировку `SHARE`: чтение работает, запись в таблицу ждёт до конца построения.
`CREATE INDEX CONCURRENTLY` не блокирует запись, но работает дольше: таблица читается дважды,
и команда ждёт завершения текущих транзакций. Внутри транзакции команда не выполняется.

В лаб. 06 (самостоятельное задание 4) найден внешний ключ без индекса: `order_items.product_id`.
Таблица `order_items` — самая большая в базе (600 000 строк).

**Шаг 1. Выполнить запрос без индекса** — продажи одного товара:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(quantity) FROM order_items WHERE product_id = 42;
```

Запишите: тип узла = ___, `Buffers: shared hit` = ___, `Execution Time` = ___ ms.

Ожидаемо: `Parallel Seq Scan` — прочитаны все 600 000 строк ради ≈ 600.

**Шаг 2. Создать индекс без блокировки записи:**

```sql
CREATE INDEX CONCURRENTLY idx_order_items_product ON order_items(product_id);
```

**Шаг 3. Проверить, что индекс корректный:**

```sql
SELECT c.relname AS index_name,
       i.indisvalid,      -- false = индекс не используется планировщиком
       i.indisready
FROM   pg_index i
JOIN   pg_class c ON c.oid = i.indexrelid
WHERE  i.indrelid = 'order_items'::regclass
ORDER  BY 1;
```

Ожидаемо: у `idx_order_items_product` `indisvalid = true`.

> Если `indisvalid = false` (построение прервалось), индекс не используется, но замедляет запись.
> Удалите его командой `DROP INDEX CONCURRENTLY idx_order_items_product;` и выполните шаг 2 заново.
> При `indisvalid = true` ничего удалять не нужно.

**Шаг 4. Повторить запрос из шага 1:**

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(quantity) FROM order_items WHERE product_id = 42;
```

Запишите: тип узла = ___, `Buffers: shared hit` = ___, `Execution Time` = ___ ms.

Ожидаемо: `Bitmap Heap Scan` по `idx_order_items_product`, страниц прочитано примерно в 9 раз меньше.

### 1.6. Функциональный индекс (индекс по выражению)

**Индекс по выражению** хранит не значение столбца, а результат функции от него, например `LOWER(email)`.

Обычный индекс по `email` не помогает запросу `WHERE LOWER(email) = …`: в нём лежат исходные значения, а не результат `LOWER`.

Ситуация: пользователь ввёл email с заглавными буквами — `C42@Example.com`. В базе хранится `c42@example.com`.

**Шаг 1. Поиск без учёта регистра без индекса по выражению:**

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM customers WHERE LOWER(email) = LOWER('C42@Example.com');
```

**Шаг 2. Создать индекс по выражению:**

```sql
CREATE INDEX idx_customers_email_lower ON customers(LOWER(email));
ANALYZE customers;   -- собрать статистику по выражению
```

**Шаг 3. Повторить запрос из шага 1:**

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM customers WHERE LOWER(email) = LOWER('C42@Example.com');
```

**Шаг 4. Поиск без `LOWER`:**

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM customers WHERE email = 'C42@Example.com';
```

| Шаг | Узел и индекс | Строк найдено (`rows`) |
|-----|---------------|------------------------|
| 1. `LOWER(email) = …` без индекса по выражению |  |  |
| 3. `LOWER(email) = …` с индексом по выражению |  |  |
| 4. `email = …` |  |  |

Ожидаемо:

- шаг 1 — `Seq Scan` по 20 000 строк, найдена 1 строка;
- шаг 3 — `Index Scan using idx_customers_email_lower`, найдена 1 строка;
- шаг 4 — `Index Scan using customers_email_key`, найдено **0 строк**: регистр не совпадает.
  Индекс по `LOWER(email)` этому запросу не подходит.

> **Когда применять:** условие `WHERE` содержит функцию над столбцом: `LOWER`, `DATE_TRUNC`, `jsonb->>'key'` и т. п.
> Выражение в запросе должно **точно совпадать** с выражением в индексе.
> Выражение с оператором берут в двойные скобки: `CREATE INDEX ON t ((data->>'key'));`

### 1.7. Неиспользуемые индексы

Каждый индекс занимает место и замедляет запись. Индекс, который не используют запросы, — чистые затраты.

**Шаг 1. Найти индексы, которые ни разу не использовались:**

```sql
SELECT s.relname      AS table_name,
       s.indexrelname AS index_name,
       pg_size_pretty(pg_relation_size(s.indexrelid)) AS index_size,
       s.idx_scan
FROM   pg_stat_user_indexes s
JOIN   pg_index i ON i.indexrelid = s.indexrelid
WHERE  s.idx_scan = 0
  AND  NOT i.indisunique                                          -- PK и UNIQUE нужны для ограничений
  AND  NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = s.indexrelid)
ORDER  BY pg_relation_size(s.indexrelid) DESC;
```

Запишите найденные индексы: ___

> Статистика использования индексов обновляется с задержкой до 1 секунды. Если индекс только что использовался,
> а `idx_scan = 0`, повторите запрос через несколько секунд.

> **Осторожно:** индекс, который ещё не использовал ни один запрос, имеет `idx_scan = 0`.
> На production решение об удалении принимают по статистике за несколько недель, включая отчётные дни.

---

## Часть 2. Autovacuum

**Autovacuum** — фоновый процесс, который запускает `VACUUM` и `ANALYZE` автоматически.
Он проверяет таблицы раз в минуту (`autovacuum_naptime`) и очищает таблицу, когда мёртвых строк больше порога:

```text
порог = autovacuum_vacuum_threshold + autovacuum_vacuum_scale_factor × reltuples
      = 50 + 0.2 × reltuples   (по умолчанию)
```

Для `orders` (200 000 строк) это ~40 000 мёртвых строк. Для активной таблицы это слишком поздно:
мёртвые строки занимают место, а запросы читают лишние страницы.

### 2.1. Проверить порог по умолчанию

**Шаг 1. Посмотреть текущее состояние таблицы.** Этот запрос понадобится несколько раз — сохраните его во вкладке:

```sql
SELECT s.n_live_tup,
       s.n_dead_tup,
       round(50 + 0.2  * c.reltuples) AS threshold_default,
       round(50 + 0.01 * c.reltuples) AS threshold_tuned,
       s.autovacuum_count,
       s.last_autovacuum
FROM   pg_stat_user_tables s
JOIN   pg_class c ON c.oid = s.relid
WHERE  s.relname = 'orders';
```

Запишите `autovacuum_count` = ___ и `threshold_default` = ___

> Autovacuum мог уже срабатывать на этой таблице раньше. Поэтому следите за **ростом** `autovacuum_count`.
> Ручной `VACUUM` из части 0 увеличивает `vacuum_count`, а не `autovacuum_count`.

**Шаг 2. Создать ~1000 мёртвых строк:**

```sql
-- Обновляется индексированный столбец, поэтому UPDATE оставляет мёртвую версию каждой строки
UPDATE orders SET created_at = created_at + INTERVAL '1 second'
WHERE  id % 200 = 0;
```

**Шаг 3. Подождать 2 минуты и повторить запрос из шага 1.**

Ожидаемо: `n_dead_tup` ≈ 1000, `autovacuum_count` **не изменился** — порог ~40 000 не достигнут.

> `n_dead_tup` может оказаться немного меньше числа обновлённых строк:
> PostgreSQL очищает часть мёртвых версий «по ходу» при чтении страниц (pruning).

### 2.2. Настроить autovacuum для таблицы

**Шаг 1. Снизить порог для `orders`:**

```sql
ALTER TABLE orders SET (
    autovacuum_vacuum_scale_factor  = 0.01,   -- 1 % вместо 20 %
    autovacuum_analyze_scale_factor = 0.005   -- 0.5 % вместо 10 %
);

SELECT relname, reloptions FROM pg_class WHERE relname = 'orders';
```

Настройка действует только для `orders`. Остальные таблицы работают с порогом по умолчанию.

**Шаг 2. Создать ещё ~4000 мёртвых строк.** Вместе с шагом 2.1 их станет ~5000 — больше нового порога (~2050):

```sql
UPDATE orders SET created_at = created_at + INTERVAL '1 second'
WHERE  id % 50 = 0;
```

**Шаг 3. Подождать 1–2 минуты.** Пока autovacuum работает, его можно увидеть:

```sql
SELECT pid, relid::regclass AS table_name, phase
FROM   pg_stat_progress_vacuum;
```

**Шаг 4. Повторить запрос из 2.1 и заполнить таблицу:**

| Момент | n_dead_tup | autovacuum_count |
|--------|------------|------------------|
| До обновлений (2.1, шаг 1) |  |  |
| После 1000 обновлений (порог 20 % ≈ 40 000) |  |  |
| После ещё 4000 обновлений (порог 1 % ≈ 2050) |  |  |

Ожидаемо: `autovacuum_count` вырос на 1, `n_dead_tup` упал до 0.

### 2.3. Ручной VACUUM ANALYZE

Ручной запуск нужен после массовых изменений, когда ждать autovacuum нельзя.

Для одной таблицы:

```sql
VACUUM (ANALYZE, VERBOSE) orders;
```

Для всей базы — утилита `vacuumdb` (PowerShell):

```powershell
& "$pg\vacuumdb.exe" -h localhost -U postgres -d eshop --analyze --verbose
```

---

## Часть 3. PgBouncer

**PgBouncer** — пул соединений между приложением и PostgreSQL. Каждое подключение к PostgreSQL — отдельный процесс
(5–10 МБ памяти). PgBouncer принимает много клиентских подключений и обслуживает их через несколько реальных соединений.

> **Подготовка преподавателя.** Проверьте установку PgBouncer на учебном компьютере **до занятия**.
> Нужны права администратора Windows и доступ в интернет.

### 3.1. Установка

> **Обратите внимание.** Загрузка через Stack Builder / EnterpriseDB на многих компьютерах блокируется (ошибка HTTP `403 Forbidden` через CloudFront) или зависает на этапе подключения к серверу. 
> Поэтому рекомендуется **прямая установка официальной сборки с GitHub Releases**.

**Основной способ — официальный релиз с GitHub (рекомендуется):**

Выполните в PowerShell (скачивание и распаковка в `C:\pgbouncer`):

```powershell
$zip = "$env:TEMP\pgbouncer.zip"
curl.exe -L -o $zip "https://github.com/pgbouncer/pgbouncer/releases/download/pgbouncer_1_26_1/pgbouncer-1.26.1-windows-x86_64.zip"
Expand-Archive -Path $zip -DestinationPath "$env:TEMP\pgbouncer" -Force
New-Item -ItemType Directory -Path "C:\pgbouncer" -Force
Copy-Item -Path "$env:TEMP\pgbouncer\pgbouncer-*\*" -Destination "C:\pgbouncer" -Recurse -Force
```

Убедитесь, что файлы на месте:

```powershell
Get-ChildItem C:\pgbouncer
& "C:\pgbouncer\pgbouncer.exe" --version
```

<details>
<summary>Альтернативный способ — через Stack Builder (если доступ к серверам EDB не заблокирован)</summary>

1. Пуск → PostgreSQL 18 → **Application Stack Builder** (от имени администратора).
2. Выберите сервер `PostgreSQL 18 on port 5432`.
3. Раздел **Add-ons, tools and utilities** → **pgBouncer**.
4. В мастере укажите: хост `localhost`, роль `postgres`, её пароль, порт PostgreSQL `5432`, порт PgBouncer `6432`.
5. Найдите путь к `pgbouncer.ini`:
   ```powershell
   Get-ChildItem "C:\Program Files", "C:\Program Files (x86)" -Recurse -Filter pgbouncer.ini -ErrorAction SilentlyContinue | Select-Object FullName
   ```
</details>

Каталог установки: **`C:\pgbouncer`**  
Конфигурационный файл: **`C:\pgbouncer\pgbouncer.ini`**

### 3.2. Настройка pgbouncer.ini

Создайте или перезапишите файл `C:\pgbouncer\pgbouncer.ini` одной командой в PowerShell:

```powershell
@'
[databases]
eshop = host=127.0.0.1 port=5432 dbname=eshop

[pgbouncer]
logfile              = C:\pgbouncer\pgbouncer.log
pidfile              = C:\pgbouncer\pgbouncer.pid
listen_addr          = 127.0.0.1
listen_port          = 6432
auth_type            = scram-sha-256
auth_file            = C:\pgbouncer\userlist.txt

pool_mode            = transaction
max_client_conn      = 200
default_pool_size    = 10
min_pool_size        = 2
reserve_pool_size    = 5
reserve_pool_timeout = 5

; DBeaver (JDBC) при подключении передаёт этот параметр.
; Без строки ниже PgBouncer отклоняет подключение: unsupported startup parameter
ignore_startup_parameters = extra_float_digits

; Подготовленные запросы на уровне протокола (драйверы JDBC, Npgsql); по умолчанию 200 с PgBouncer 1.24
max_prepared_statements  = 200

log_connections      = 1
log_disconnections   = 1

; Административная консоль
admin_users          = pgbouncer_admin
'@ | Set-Content -Path "C:\pgbouncer\pgbouncer.ini" -Encoding ascii
```

| Параметр | Значение |
|---|---|
| `pool_mode = transaction` | Соединение выдаётся клиенту на одну транзакцию и сразу возвращается в пул |
| `max_client_conn = 200` | Сколько клиентов может подключиться к PgBouncer |
| `default_pool_size = 10` | Сколько реальных соединений к PostgreSQL на пару «база + пользователь» |
| `reserve_pool_size = 5` | Дополнительные соединения, если клиент ждёт дольше `reserve_pool_timeout` секунд |

### 3.3. Файл пользователей userlist.txt и запуск

PgBouncer сам проверяет пароль клиента. Для этого ему нужен список пользователей и хэшей паролей.

**Шаг 1. Получить SCRAM-хэш пароля `app_backend`** (под `postgres`, в DBeaver или psql):

```sql
SELECT format('"%s" "%s"', rolname, rolpassword) AS userlist_line
FROM   pg_authid
WHERE  rolname = 'app_backend';
```

Строка должна начинаться так: `"app_backend" "SCRAM-SHA-256$4096:…"`.
Если хэш начинается с `md5`, пароль задан в старом формате. Задайте пароль заново: `ALTER ROLE app_backend PASSWORD 'backend_pass_2024';`

**Шаг 2. Создать `userlist.txt` в каталоге `C:\pgbouncer`:**

Выполните в PowerShell (подставьте полученную строку со SCRAM-хэшем):

```powershell
@(
    '"app_backend" "SCRAM-SHA-256$4096:...вставьте строку целиком..."'
    '"pgbouncer_admin" "admin_pass"'
) | Set-Content -Path "C:\pgbouncer\userlist.txt" -Encoding ascii
```

> **Кодировка.** В Windows PowerShell 5.1 `-Encoding utf8` записывает метку BOM в начало файла.
> PgBouncer не распознаёт первую строку с BOM, и пользователь `app_backend` «не существует».
> Всегда используйте `-Encoding ascii` или сохраняйте через Блокнот в кодировке UTF-8 без BOM.
>
> Строку с хэшем берите в **одинарные** кавычки: в двойных PowerShell подставит переменные вместо `$4096` и т. п.

Пароль `pgbouncer_admin` хранится открытым текстом. Это допустимо только в учебной среде.

**Шаг 3. Запуск PgBouncer**

Выберите один из двух способов запуска:

* **Вариант А. Служба Windows (требует запуска PowerShell от имени Администратора):**
  ```powershell
  & "C:\pgbouncer\pgbouncer.exe" --regservice "C:\pgbouncer\pgbouncer.ini"
  Start-Service pgbouncer
  Get-Service pgbouncer     # Status = Running
  ```
  *(Если потребуется перезапустить службу после изменений в конфиге: `Restart-Service pgbouncer`)*

* **Вариант Б. Фоновый процесс (не требует прав администратора):**
  ```powershell
  Start-Process "C:\pgbouncer\pgbouncer.exe" "C:\pgbouncer\pgbouncer.ini" -WindowStyle Hidden
  Get-Process pgbouncer     # убедиться, что процесс pgbouncer запущен
  ```
  *(Если потребуется перезапустить процесс: `Stop-Process -Name pgbouncer -Force`, затем выполнить `Start-Process` заново)*

Если PgBouncer не стартует, проверьте лог-файл:
```powershell
Get-Content "C:\pgbouncer\pgbouncer.log" -Tail 20
```

### 3.4. Архитектура

```mermaid
flowchart LR
    subgraph Clients["Клиенты (до 200 соединений)"]
        C1([App instance 1])
        C2([App instance 2])
        C3([App instance N])
    end

    PGB["PgBouncer :6432<br/>transaction mode<br/>default_pool_size = 10"]

    subgraph PG["PostgreSQL :5432"]
        B1([backend 1])
        B2([backend 2])
        B3([backend … 10])
    end

    C1 --> PGB
    C2 --> PGB
    C3 --> PGB
    PGB --> B1
    PGB --> B2
    PGB --> B3
```

Клиенты подключаются к PgBouncer (порт 6432) так же, как к PostgreSQL. PgBouncer передаёт их запросы
через 10 соединений к PostgreSQL (порт 5432). Если все 10 заняты, клиент ждёт в очереди.

### 3.5. Подключение и административная консоль

**Шаг 1. Проверить подключение через PgBouncer** (порт 6432 вместо 5432):

```powershell
& "$pg\psql.exe" -h 127.0.0.1 -p 6432 -U app_backend -d eshop -c "SELECT count(*) FROM orders;"
```

Ожидаемо: 200000.

**Шаг 2. Открыть окно A** — интерактивный сеанс через PgBouncer. Оставьте его открытым:

```powershell
& "$pg\psql.exe" -h 127.0.0.1 -p 6432 -U app_backend -d eshop
```

**Шаг 3. Открыть окно Б — административную консоль.** Используйте psql: DBeaver к консоли PgBouncer не подключается.

```powershell
& "$pg\psql.exe" -h 127.0.0.1 -p 6432 -U pgbouncer_admin -d pgbouncer
```

```sql
SHOW POOLS;     -- пулы: клиенты (cl_*) и соединения с PostgreSQL (sv_*)
SHOW CLIENTS;   -- подключённые клиенты
SHOW SERVERS;   -- соединения PgBouncer с PostgreSQL
SHOW STATS;     -- счётчики запросов и транзакций
```

Запишите из `SHOW POOLS` для пула `eshop` / `app_backend`: `cl_active` = ___, `sv_active` + `sv_idle` = ___

> Сеанс `psql -c` из шага 1 закрывается сразу после запроса, поэтому в `SHOW POOLS` он не виден.
> `cl_active = 1` — это открытый сеанс в окне A.

Подключение из DBeaver: создайте копию подключения к `eshop` с портом **6432** и пользователем `app_backend`.

### 3.6. Нагрузочный тест: 50 клиентов → 10 соединений

**Шаг 1. Создать сценарий для `pgbench` и запустить 50 клиентов через PgBouncer на 30 секунд:**

```powershell
Set-Content -Path "$env:TEMP\select.sql" -Encoding ascii `
    -Value "SELECT count(*) FROM orders WHERE status = 'pending';"

$env:PGPASSWORD = "backend_pass_2024"   # пароль app_backend из лаб. 02
& "$pg\pgbench.exe" -h 127.0.0.1 -p 6432 -U app_backend -d eshop `
    -n -c 50 -j 4 -T 30 -f "$env:TEMP\select.sql"
```

`-n` отключает VACUUM служебных таблиц pgbench: в `eshop` их нет.

**Шаг 2. Пока тест идёт,** в DBeaver под `postgres` (порт 5432) посчитайте процессы `app_backend` на сервере:

```sql
SELECT count(*) AS backends
FROM   pg_stat_activity
WHERE  usename = 'app_backend';
```

И в окне Б: `SHOW POOLS;` — смотрите `cl_active`, `cl_waiting`, `sv_active`.

**Шаг 3. Повторить тест напрямую в PostgreSQL** (порт 5432) и снова посчитать `backends`:

```powershell
& "$pg\pgbench.exe" -h 127.0.0.1 -p 5432 -U app_backend -d eshop `
    -n -c 50 -j 4 -T 30 -f "$env:TEMP\select.sql"
Remove-Item Env:PGPASSWORD
```

**Шаг 4. Заполнить таблицу** (`tps` и `latency average` — из итогов pgbench):

| Подключение | Клиентов | Backend-процессов PostgreSQL | tps | latency average, ms |
|-------------|----------|------------------------------|-----|---------------------|
| Через PgBouncer :6432 | 50 |  |  |  |
| Напрямую :5432        | 50 |  |  |  |

Ожидаемо: через PgBouncer backend-процессов не больше 15 (`default_pool_size` 10 + `reserve_pool_size` 5), напрямую — около 50.

### 3.7. Ограничения transaction mode

В transaction mode клиент получает серверное соединение только на время транзакции.
Следующая транзакция того же клиента может пойти через **другое** соединение.

Откройте два сеанса через PgBouncer — **клиент 1** и **клиент 2**:

```powershell
& "$pg\psql.exe" -h 127.0.0.1 -p 6432 -U app_backend -d eshop
```

**Эксперимент 1. SET «утекает» к другому клиенту**

```sql
-- Клиент 1
SELECT pg_backend_pid();
SET work_mem = '64MB';

-- Клиент 2
SELECT pg_backend_pid();   -- часто тот же PID, что у клиента 1
SHOW work_mem;             -- 64MB: настройку клиента 1 получил клиент 2
```

Причина: `SET` изменил параметр **серверного соединения**. Соединение вернулось в пул и досталось клиенту 2.
В transaction mode PgBouncer по умолчанию не сбрасывает параметры сеанса между клиентами.

Верните значение (у клиента 2): `RESET ALL;`

> Если PID у клиентов разные, повторите `SELECT pg_backend_pid();` и `SHOW work_mem;` у клиента 2 ещё 2–3 раза.

**Эксперимент 2. SQL-команда PREPARE**

```sql
-- Клиент 1: подготовить запрос (транзакция закончилась, соединение вернулось в пул)
PREPARE q(int) AS SELECT id, status FROM orders WHERE id = $1;

-- Клиент 2: занять это соединение открытой транзакцией
BEGIN;
SELECT pg_backend_pid();

-- Клиент 1: выполнить подготовленный запрос — он попадёт на другое соединение
EXECUTE q(1);
-- ERROR: prepared statement "q" does not exist

-- Клиент 2
COMMIT;
```

> **Важно.** С PgBouncer 1.21 подготовленные запросы **на уровне протокола** (их отправляют драйверы JDBC, Npgsql, psycopg)
> работают в transaction mode, если `max_prepared_statements > 0`. SQL-команды `PREPARE` / `EXECUTE` по-прежнему не поддерживаются.

Также в transaction mode не работают: `LISTEN` / `NOTIFY`, временные таблицы, которые живут дольше транзакции,
сессионные advisory-блокировки (`pg_advisory_lock`).

---

## Часть 4. Обоснование архитектурного изменения

Составьте документ `pgbouncer_justification.md` на основе **своих** измерений из 3.6:

```markdown
## Обоснование введения PgBouncer для eshop

### Проблема
- 50 одновременных клиентов открывают 50 соединений к PostgreSQL (измерено: ___ backend-процессов).
- Каждое соединение — отдельный процесс Windows. Оценка: 5–10 МБ памяти на процесс.
  50 × ___ МБ = ___ МБ.

### Решение
- PgBouncer, pool_mode = transaction, default_pool_size = 10, reserve_pool_size = 5.

### Эффект (измерено pgbench, 50 клиентов, 30 с)
| Показатель                    | Напрямую :5432 | Через PgBouncer :6432 |
|-------------------------------|----------------|-----------------------|
| Backend-процессов PostgreSQL  |                |                       |
| tps                           |                |                       |
| Средняя задержка, мс          |                |                       |

### Ограничения
- SQL-команды PREPARE/EXECUTE не поддерживаются; подготовленные запросы драйверов — при max_prepared_statements > 0.
- SET действует на серверное соединение и может перейти к другому клиенту. Используйте SET LOCAL внутри транзакции.
- Не работают LISTEN/NOTIFY, сессионные advisory-блокировки, временные таблицы вне транзакции.
- Дополнительный компонент: нужен мониторинг (SHOW POOLS) и отказоустойчивость.
```

> Учебный тест с простым запросом может показать tps через PgBouncer **ниже**, чем напрямую: добавляется один сетевой переход.
> Выигрыш PgBouncer — в числе процессов и памяти, а на production — в защите от исчерпания `max_connections`.
> Запишите фактические числа и объясните их.

---

## Чек-лист «работа зачтена»

- [ ] Статусы перераспределены, числа совпали с эталоном 0.2, выполнен `VACUUM ANALYZE orders`.
- [ ] Частичный индекс `idx_orders_active` создан; его размер сравнён с полным; `EXPLAIN` для `'pending'` показывает `Bitmap Index Scan` или `Index Scan` по `idx_orders_active`.
- [ ] `idx_orders_status_created` создан; планы до и после сравнены по Buffers; объяснено правило порядка столбцов.
- [ ] `idx_order_items_product` создан через `CONCURRENTLY`, `indisvalid = true`; планы до и после сравнены.
- [ ] Показано, что `idx_customers_email_lower` используется только для `LOWER(email) = …`.
- [ ] `autovacuum_vacuum_scale_factor = 0.01` выставлен на `orders`; показан рост `autovacuum_count` после превышения нового порога.
- [ ] PgBouncer запущен на порту 6432; `SELECT count(*)` через 6432 работает.
- [ ] `SHOW POOLS` показывает пул `eshop` с `cl_active > 0`.
- [ ] Таблица из 3.6 заполнена; через PgBouncer backend-процессов ≤ 15.
- [ ] `pgbouncer_justification.md` создан с измеренными числами.

---

## Самостоятельное задание

1. Создайте функциональный индекс `ON products(LOWER(name))` и проверьте, что запрос
   `WHERE LOWER(name) = 'товар 42'` его использует. Таблица `products` маленькая (1000 строк), поэтому для проверки
   выполните запрос после `SET enable_seqscan = off;` и затем `RESET enable_seqscan;`.
   Объясните, почему без индекса по выражению индекс по `name` не может быть использован.
2. Переключите PgBouncer в режим `session` (`pool_mode = session`, перезапуск службы).
   Повторите эксперименты 1 и 2 из 3.7. Объясните, почему теперь `PREPARE` работает, а `SET` не переходит к другому клиенту.
   Повторите тест 3.6: сколько backend-процессов теперь и сколько клиентов ждут (`cl_waiting`)?
3. Сведите в таблицу режимы session / transaction / statement: когда соединение возвращается в пул,
   что работает, что не работает, типичное применение.

---

## Ссылки

- Индексы PostgreSQL: https://www.postgresql.org/docs/current/indexes.html
- Частичные индексы: https://www.postgresql.org/docs/current/indexes-partial.html
- Индексы по выражениям: https://www.postgresql.org/docs/current/indexes-expressional.html
- CREATE INDEX CONCURRENTLY: https://www.postgresql.org/docs/current/sql-createindex.html#SQL-CREATEINDEX-CONCURRENTLY
- Autovacuum: https://www.postgresql.org/docs/current/routine-vacuuming.html#AUTOVACUUM
- pgbench: https://www.postgresql.org/docs/current/pgbench.html
- PgBouncer, настройки: https://www.pgbouncer.org/config.html
- PgBouncer, ограничения режимов: https://www.pgbouncer.org/features.html
- Релизы PgBouncer (включая Windows x86_64): https://github.com/pgbouncer/pgbouncer/releases
- EDB PgBouncer для Windows: https://www.enterprisedb.com/docs/pgbouncer/1/installing/windows/
- Установка PgBouncer (Windows): [wiki/tools/pgbouncer.md](../../wiki/tools/pgbouncer.md)
