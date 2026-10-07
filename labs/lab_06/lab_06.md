# Лабораторная работа №6. Анализ запросов eshop: pg_stat_statements, EXPLAIN ANALYZE, pgBadger
 
**Неделя:** 8
**Ориентировочное время:** 2 занятия (≈ 4 ак. ч.)
**Версия PostgreSQL:** 18
 
## Цель работы
 
1. Подключить и использовать расширение `pg_stat_statements`.
2. Читать планы выполнения запросов через `EXPLAIN ANALYZE`.
3. Найти дорогостоящие запросы в eshop и определить их причины.
4. (опционально) Сформировать HTML-отчёт pgBadger из лог-файла.
   
## Предварительные требования
 
- Работа выполняется под ролью `postgres` в базе `eshop`.
- В DBeaver включён режим **Auto-Commit** — см. ниже.
  
#### Режим Auto-Commit в DBeaver
 
DBeaver выполняет команды в одном из двух режимов:
 
| Режим | Как работает |
|---|---|
| **Auto-Commit** | Каждая команда сразу фиксируется (сохраняется) в базе |
| **Manual Commit** | Команды накапливаются в открытой транзакции. Изменения сохраняются только после кнопки Commit, отменяются кнопкой Rollback |
 
Для этой работы нужен **Auto-Commit**. Причины:
 
1. Команды `ALTER SYSTEM` и `VACUUM` нельзя выполнять внутри транзакции. В режиме Manual Commit сервер выдаёт ошибку: `ALTER SYSTEM cannot run inside a transaction block`.
2. В режиме Manual Commit скрипт наполнения данных не сохранится, пока вы не нажмёте Commit. Открытая транзакция с `TRUNCATE` блокирует таблицы: запросы из других вкладок будут ждать.
**Как проверить режим.** На главной панели инструментов DBeaver есть кнопка режима транзакций. В режиме Manual Commit рядом с ней активны кнопки Commit и Rollback. В режиме Auto-Commit они неактивны (серые).
 
**Как включить Auto-Commit:**
- нажать кнопку режима транзакций на панели инструментов и выбрать Auto-Commit; или
- для постоянной настройки: правый клик по подключению → Edit Connection → Connection settings → Initialization → флажок **Auto-commit**.
> Если вы выполнили команды в режиме Manual Commit и получили ошибку — сначала нажмите **Rollback**. После ошибки транзакция в PostgreSQL прервана, и любые следующие команды в ней тоже завершатся ошибкой.

### Наполнение базы тестовыми данными
 
#### Почему нужен большой объём данных
 
На малом объёме (сотни строк) таблица занимает 1–2 страницы. Планировщик выбирает Seq Scan[^seqscan] даже при наличии индекса: Index Scan[^indexscan] для такой таблицы дороже. Все запросы выполняются за доли миллисекунды, и `pg_stat_statements` не показывает разницы между ними. Параллельные планы и `Batches` в хеш-операциях не появляются. Подробнее — лекция 8, п. 2.3–2.5.
 
Скрипт ниже создаёт объём, при котором эти механизмы видны:
 
| Таблица | Строк | Размер |
|---|---|---|
| `customers` | 20 000 | ≈ 2 МБ |
| `products` | 1 000 | < 0,1 МБ |
| `orders` | 200 000 | ≈ 14 МБ |
| `order_items` | 600 000 | ≈ 39 МБ |
 
[^seqscan]: **Seq Scan** (Sequential Scan, последовательное сканирование) — способ доступа к таблице, при котором PostgreSQL читает все страницы таблицы по порядку и проверяет условие `WHERE` для каждой строки. Время пропорционально размеру таблицы, а не числу строк в результате. Seq Scan оптимален, когда запросу нужна большая часть строк таблицы, или таблица мала.
 
[^indexscan]: **Index Scan** (сканирование по индексу) — способ доступа к таблице через индекс. PostgreSQL спускается по дереву B-tree от корня к листу, находит ссылки на нужные строки и читает только те страницы таблицы, где эти строки лежат. Время пропорционально числу строк в результате, а не размеру таблицы. Каждая строка может лежать на своей странице, поэтому чтение страниц таблицы — случайное (в разном порядке), а не последовательное. Index Scan выгоден, когда условие отбирает малую часть строк (обычно единицы процентов). Если нужна большая часть таблицы, Seq Scan быстрее.
 
    В планах встречаются ещё 2 варианта:
 
    - **Bitmap Index Scan + Bitmap Heap Scan** — PostgreSQL сначала собирает по индексу карту нужных страниц, затем читает эти страницы по порядку. Промежуточный вариант для средней селективности (от единиц до десятков процентов).
    - **Index Only Scan** — все нужные колонки есть в самом индексе. Страницы таблицы не читаются (если таблица недавно обработана `VACUUM`).
 
Проверьте текущий объём:
 
```sql
SELECT (SELECT count(*) FROM customers)   AS customers,
       (SELECT count(*) FROM products)    AS products,
       (SELECT count(*) FROM orders)      AS orders,
       (SELECT count(*) FROM order_items) AS order_items;
```
 
Если значения меньше 20 000 / 1 000 / 200 000 / 600 000 — выполните скрипт целиком (в DBeaver: `Alt+X`):
 
```sql
-- 0. Очистка.
--    TRUNCATE удаляет все строки 4 таблиц.
--    RESTART IDENTITY сбрасывает счётчики id: генератор ниже рассчитывает,
--    что id идут подряд с 1.
--    CASCADE очищает также таблицы, которые ссылаются на эти по FK.
TRUNCATE order_items, orders, products, customers RESTART IDENTITY CASCADE;
 
-- 1. Фиксированное зерно генератора random().
--    Одинаковое зерно -> одинаковая последовательность случайных чисел
--    -> у всех студентов одинаковые данные и сопоставимые планы.
--    Действует до конца сеанса. Скрипт выполнять целиком, в одном сеансе.
SELECT setseed(0.42);
 
-- 2. Клиенты: 20 000 строк.
--    generate_series(1, 20000) - источник 20 000 строк, g - номер строки.
--    email уникален (c1@..., c2@...) - так требует ограничение UNIQUE.
--    Регион: с вероятностью 5 % - 'MSK', иначе один из 4 регионов поровну.
--    Малая доля MSK нужна, чтобы фильтр region = 'MSK' был селективным
--    и индекс по region давал эффект.
INSERT INTO customers (name, email, region)
SELECT 'Клиент ' || g, 'c' || g || '@example.com',
       CASE WHEN random() < 0.05 THEN 'MSK'
            ELSE (ARRAY['SPB','NSK','EKB','KZN'])[1 + floor(random()*4)::int] END
FROM generate_series(1, 20000) g;
 
-- 3. Товары: 1 000 строк.
--    Цена 100..10 000, остаток 0..499.
--    Значения удовлетворяют CHECK (price > 0, stock_qty >= 0).
INSERT INTO products (name, price, stock_qty)
SELECT 'Товар ' || g,
       round((100 + random()*9900)::numeric, 2),
       floor(random()*500)::int
FROM generate_series(1, 1000) g;
 
-- 4. Заказы: 200 000 строк.
--    customer_id: случайный id из диапазона min(id) .. min(id) + 19 999.
--      Подзапрос (SELECT min(id) ...) выполняется 1 раз, random() - для каждой строки.
--    status: один из 5 значений, разрешённых CHECK-ограничением, поровну (по 20 %).
--    created_at: случайный момент за последние 2 года (730 дней).
--      За последние 30 дней попадает ~ 30/730 ~ 4 % заказов -
--      фильтр по дате селективный, индекс по created_at даёт эффект.
INSERT INTO orders (customer_id, status, total_amount, created_at)
SELECT (SELECT min(id) FROM customers) + floor(random()*20000)::int,
       (ARRAY['pending','processing','shipped','delivered','cancelled'])[1 + floor(random()*5)::int],
       round((random()*10000)::numeric, 2),
       now() - random() * interval '730 days'
FROM generate_series(1, 200000);
 
-- 5. Позиции заказов: 600 000 строк (по 3 на заказ).
--    FROM orders o, generate_series(1, 3) - декартово произведение:
--    каждый заказ повторяется 3 раза.
--    product_id - случайный товар, quantity 1..5, цена 1..5 000
--    (минимум 1 - чтобы округление не дало 0 и не нарушило CHECK unit_price > 0).
--    Самый долгий шаг: для каждой строки проверяются 2 внешних ключа.
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT o.id,
       (SELECT min(id) FROM products) + floor(random()*1000)::int,
       1 + floor(random()*5)::int,
       round((1 + random()*4999)::numeric, 2)
FROM orders o, generate_series(1, 3);
 
-- 6. Обновить статистику всех таблиц.
--    Без ANALYZE планировщик не знает о новом объёме и распределении данных,
--    оценки rows в планах будут неверными.
ANALYZE;
```
 
Время выполнения: 30–60 с (зависит от диска и процессора). Основное время занимает вставка 600 000 строк в `order_items`: для каждой строки проверяются 2 внешних ключа. Характеристики данных:
 
| Параметр | Значение |
|---|---|
| Клиенты из региона MSK | 1 007 (≈ 5 %) |
| Заказы за последние 30 дней | ≈ 8 100 (≈ 4 %; зависит от момента запуска) |
| Позиций на заказ | 3 |
 
> `TRUNCATE ... CASCADE` удаляет также строки в таблицах, которые ссылаются на эти таблицы по внешнему ключу (например, таблицы аудита из прошлых лабораторных). Скрипт можно запускать повторно: результат будет тем же.
 
> `ANALYZE` в конце обязателен. Без свежей статистики оценки `rows` в планах будут неверными.
 
---
 
## Часть 1. pg_stat_statements
 
### 1.1. Подключить расширение
 
Расширение работает только при загрузке библиотеки во время старта сервера. Порядок шагов важен.
 
**Шаг 1.** Проверить текущее значение параметра:
 
```sql
SHOW shared_preload_libraries;
```
 
Параметр `shared_preload_libraries` содержит список библиотек, которые сервер загружает при старте. Команда `ALTER SYSTEM` в шаге 2 **заменяет** весь список, а не добавляет в него. Поэтому сначала посмотрите, что в списке уже есть.
 
| Результат `SHOW` | Команда для шага 2 |
|---|---|
| Пустая строка (обычно после установки PostgreSQL) | `ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';` |
| Есть значение, например `auto_explain` | `ALTER SYSTEM SET shared_preload_libraries = 'auto_explain,pg_stat_statements';` |
| Уже есть `pg_stat_statements` | Ничего не менять. Пропустите шаги 2–4, перейдите к шагу 5 |
 
Во втором случае укажите все библиотеки из результата `SHOW` и добавьте `pg_stat_statements` через запятую. Если указать только `pg_stat_statements`, библиотека `auto_explain` перестанет загружаться.
 
**Шаг 2.** Записать параметр — команду из таблицы шага 1 (отдельной командой, в режиме Auto-Commit). Для пустого значения:
 
```sql
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
```
 
Команда записывает значение в `postgresql.auto.conf`. Ручная правка `postgresql.conf` не нужна.
 
**Шаг 3.** Проверить, что значение записано и ждёт перезапуска:
 
```sql
SELECT pg_reload_conf();
 
SELECT pending_restart FROM pg_settings
WHERE  name = 'shared_preload_libraries';
```
 
`ALTER SYSTEM` только записывает файл `postgresql.auto.conf`. Сервер не перечитывает его автоматически. `pg_reload_conf()` заставляет сервер перечитать конфигурацию. Параметр `shared_preload_libraries` нельзя применить без перезапуска, поэтому сервер отмечает его `pending_restart = true`.
 
Должно быть `true`. Если `false` — шаг 2 не выполнен (проверьте Auto-Commit).
 
> Без `pg_reload_conf()` значение `pending_restart` остаётся `false` даже после успешного `ALTER SYSTEM`.
 
**Шаг 4.** Перезапустить сервер. `SELECT pg_reload_conf()` для этого параметра не подходит.
 
PowerShell от имени администратора:
 
```powershell
Get-Service postgres*              # проверить имя службы
Restart-Service postgresql-x64-18
```
 
> В Windows PowerShell 5.1 оператор `&&` не работает. Используйте `Restart-Service` или разделитель `;`.
 
**Шаг 5.** В DBeaver переподключиться к базе (правый клик по подключению → Invalidate/Reconnect). Затем:
 
```sql
SELECT pg_postmaster_start_time() AS server_started,
       current_setting('shared_preload_libraries') AS preload_now;
 
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
 
SELECT count(*) FROM pg_stat_statements;
```
 
`server_started` должно соответствовать времени перезапуска. Последний запрос должен выполниться без ошибки.
 
| Ошибка | Причина |
|---|---|
| `pg_stat_statements must be loaded via "shared_preload_libraries"` | Сервер не перезапущен или параметр не записан |
| `relation "pg_stat_statements" does not exist` | Расширение создано в другой базе. Проверьте `SELECT current_database();` |
| Сервер не стартует после перезапуска | Опечатка в имени библиотеки. Удалите строку из `postgresql.auto.conf` в каталоге данных |
 
 
### 1.2. Сбросить статистику и создать нагрузку
 
```sql
SELECT pg_stat_statements_reset();
```
 
> Функция возвращает время сброса.
 
Выполните каждый запрос 5–10 раз:
 
```sql
-- Q1. Выручка по клиентам
SELECT c.name, COUNT(o.id) AS order_count, SUM(o.total_amount) AS revenue
FROM   customers c
LEFT   JOIN orders o ON o.customer_id = c.id
GROUP  BY c.id, c.name
ORDER  BY revenue DESC NULLS LAST;
 
-- Q2. Заказы в статусе pending
SELECT * FROM orders WHERE status = 'pending' ORDER BY created_at;
 
-- Q3. Продажи по товарам
SELECT p.name, SUM(oi.quantity) AS total_sold
FROM   products p
JOIN   order_items oi ON oi.product_id = p.id
GROUP  BY p.id, p.name
ORDER  BY total_sold DESC;
```
 
> **Q1:** при `LEFT JOIN` у клиентов без заказов `revenue = NULL`. При `ORDER BY ... DESC` значения NULL идут первыми. `NULLS LAST` ставит их в конец.
> Группировка по `c.id` нужна: группировка только по `name` объединит разных клиентов с одинаковым именем.
 
> **Q2** возвращает ≈ 40 000 строк. DBeaver показывает первые 200, но сервер выполняет запрос полностью. Статистика корректна.
 
### 1.3. Читать pg_stat_statements
 
```sql
SELECT LEFT(regexp_replace(query, '\s+', ' ', 'g'), 60) AS query_preview,
       calls,
       ROUND(total_exec_time::numeric, 2)  AS total_ms,
       ROUND(mean_exec_time::numeric, 2)   AS mean_ms,
       ROUND(stddev_exec_time::numeric, 2) AS stddev_ms,
       shared_blks_hit                     AS blks_hit,
       shared_blks_read                    AS blks_read
FROM   pg_stat_statements
WHERE  dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
  AND  query NOT ILIKE '%pg_stat%'
  AND  query NOT ILIKE '%pg_catalog%'
ORDER  BY total_exec_time DESC
LIMIT  10;
```
 
Пояснения к запросу:
 
- `dbid` — представление содержит статистику всех баз кластера. Фильтр оставляет только текущую.
- `pg_catalog` — исключает служебные запросы DBeaver и других клиентов.
- `regexp_replace` — убирает переносы строк из текста запроса.
Пояснения к колонкам:
 
| Колонка | Значение |
|---|---|
| `query_preview` | Первые 60 символов текста запроса. Константы заменены параметрами: `status = $1` |
| `calls` | Сколько раз запрос выполнен после сброса статистики |
| `total_ms` | Суммарное время всех выполнений, мс |
| `mean_ms` | Среднее время одного выполнения, мс |
| `stddev_ms` | Стандартное отклонение времени, мс. Большое значение — время нестабильно |
| `blks_hit` | Страницы (по 8 КБ), найденные в shared_buffers (кэш PostgreSQL). Сумма за все вызовы |
| `blks_read` | Страницы, которых не было в shared_buffers. Они пришли с диска или из кэша ОС. Сумма за все вызовы |
 
> **Почему `blks_read` может быть больше 0 при повторных запусках.** После перезапуска сервера shared_buffers пусты, первый запуск читает всё вне кэша. Кроме того, таблицу больше ¼ shared_buffers (по умолчанию 128 МБ / 4 = 32 МБ) PostgreSQL читает через малый кольцевой буфер (256 КБ), чтобы не вытеснить из кэша другие данные. Такая таблица не остаётся в shared_buffers, и каждый Seq Scan читает её заново. В eshop это `order_items` (≈ 39 МБ).
 
**Оформление отчёта.** Создайте файл `lab06_report.md`. Переносите в него все таблицы и ответы этой работы. Начните с таблицы топ-запросов:
 
```markdown
# Лабораторная работа №6 — отчёт
Студент: <ФИО>, группа: <номер>
 
## 1.3. Топ запросов
 
| query_preview | calls | mean_ms | stddev_ms | страниц / calls |
|---|---|---|---|---|
| ... | ... | ... | ... | ... |
```
 
`страниц / calls` = (`blks_hit` + `blks_read`) / `calls` — сколько страниц запрос читает за одно выполнение. Учитывайте обе колонки: при холодном кэше большая часть страниц попадает в `blks_read`.
 
Пример заполнения (эталонный прогон, 9 вызовов):
 
| query_preview | calls | mean_ms | stddev_ms | страниц / calls |
|---|---|---|---|---|
| `SELECT p.name, SUM(oi.quantity) AS total_sold FROM products` | 9 | 651.53 | 128.40 | (3 466 + 41 624) / 9 ≈ 5 010 |
| `SELECT c.name, COUNT(o.id) AS order_count, SUM(o.total_amoun` | 9 | 388.72 | 122.86 | (16 043 + 2 005) / 9 ≈ 2 005 |
| `SELECT * FROM orders WHERE status = $1 ORDER BY created_at` | 9 | 68.42 | 31.55 | (16 095 + 0) / 9 ≈ 1 788 |
 
### 1.4. Оценка полного чтения без EXPLAIN
 
Сравните `страниц / calls` из таблицы п. 1.3 с размером таблиц:
 
```sql
SELECT relname,
       pg_relation_size(oid) / 8192 AS pages,
       pg_size_pretty(pg_relation_size(oid)) AS size
FROM   pg_class
WHERE  relname IN ('orders', 'order_items', 'customers', 'products');
```
 
Если число страниц на один вызов примерно равно размеру таблицы — запрос читает таблицу целиком.
 
Ответьте: какие из запросов Q1–Q3 читают таблицы целиком?
 
---
 
## Часть 2. EXPLAIN ANALYZE
 
### 2.1. Базовый синтаксис
 
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.name, COUNT(o.id)
FROM   customers c
LEFT   JOIN orders o ON o.customer_id = c.id
GROUP  BY c.id, c.name;
```
 
> `BUFFERS` выводится по умолчанию при `ANALYZE`. Опция указана явно для наглядности.
 
> В DBeaver выполняйте через `Ctrl+Enter`. Кнопка «Explain execution plan» (`Ctrl+Shift+E`) показывает дерево без `actual time` и `Buffers`.
 
**Правило безопасности.** `EXPLAIN ANALYZE` **выполняет** запрос. Для DML (INSERT/UPDATE/DELETE) используйте транзакцию с откатом:
 
```sql
BEGIN;
EXPLAIN (ANALYZE, BUFFERS)
UPDATE orders SET status = 'cancelled' WHERE created_at < now() - interval '700 days';
ROLLBACK;
```
 
> Выполняйте блок **целиком** (`Alt+X`). Если выполнить только строку с `EXPLAIN` (`Ctrl+Enter`) в режиме Auto-Commit, изменение зафиксируется: ≈ 8 200 заказов получат статус `cancelled`, и данные перестанут совпадать с эталоном. Проверка после блока: `SELECT count(*) FROM orders WHERE status = 'cancelled';` — значение не должно измениться.
 
Сохраняйте планы всех запросов части 2 в файл `lab06_report.md` (блок ```` ```text ````). Они нужны для сравнения в п. 2.4.
 
### 2.2. Элементы плана
 
| Элемент | Значение |
|---|---|
| `Seq Scan on orders` | Полное чтение таблицы. Оптимально, если нужна большая часть строк. Проблема — если нужна малая часть |
| `cost=0.00..1.03` | Оценочная стоимость в условных единицах: до первой строки .. до последней |
| `rows=103 width=8` (в скобках `cost`) | **Оценка** планировщика: число строк и средний размер строки в байтах |
| `actual time=0.012..0.025` | Реальное время в мс: до первой строки .. до последней. **На один цикл**. Включает время всех дочерних узлов: собственное время узла = его время − время дочерних |
| `actual ... rows=100 loops=3` | **Реальное** число строк на один цикл и число циклов. Всего строк = rows × loops |
| `Buffers: shared hit=5 read=0` | Страницы из shared_buffers / страницы вне shared_buffers (диск или кэш ОС) |
| `Workers Launched: 2` | Параллельное выполнение: 2 рабочих процесса + ведущий процесс |
| `Rows Removed by Filter: 190000` | Сколько прочитанных строк не прошло условие `WHERE`. Большое значение при Seq Scan — признак, что индекс может помочь |
| `Planning Time` / `Execution Time` | Время построения плана / время выполнения запроса, мс. Для сравнения вариантов используйте `Execution Time` |
 
> Фактическое `rows` выводится с дробной частью (`rows=1000.00`): это среднее значение на один цикл.
 
### 2.3. Запрос с фильтром и двумя JOIN
 
Проверьте существующие индексы (часть могла остаться после прошлых лабораторных):
 
```sql
SELECT tablename, indexname, indexdef
FROM   pg_indexes
WHERE  schemaname = 'public'
  AND  tablename IN ('orders', 'order_items', 'customers');
```
 
Ожидаемо 4 индекса: `customers_pkey`, `customers_email_key`, `orders_pkey`, `order_items_pkey`. Если есть индексы `idx_*` — удалите их (`DROP INDEX ...`), иначе сравнение в п. 2.4 потеряет смысл.
 
Выполните запрос 3 раза, сохраните план последнего запуска:
 
```sql
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
 
Фильтр отбирает ≈ 5 % клиентов и ≈ 4 % заказов — в результате несколько сотен заказов из 200 000.
 
Найдите в плане и запишите:
 
1. Тип JOIN (Hash Join / Nested Loop / Merge Join).
2. Узлы Seq Scan. На каких таблицах?
3. Сравните оценку `rows` и фактические `rows × loops` для узлов сканирования.
> **Расхождение оценки и факта.** Большое расхождение (в разы и более) указывает на устаревшую статистику или корреляцию условий.
> Исключение — параллельные узлы. Для 2 рабочих процессов планировщик делит число строк на 2.4 (учитывает частичное участие ведущего процесса). Пример: таблица 600 000 строк → оценка `rows=250000` на цикл, факт `rows=200000 loops=3`. Это **не** ошибка статистики.
 
### 2.4. Сравнение с индексами
 
```sql
CREATE INDEX IF NOT EXISTS idx_customers_region   ON customers(region);
CREATE INDEX IF NOT EXISTS idx_orders_created_at  ON orders(created_at);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_items_order  ON order_items(order_id);
```
 
> `idx_order_items_order` обслуживает главное соединение запроса. Без него эффект от остальных индексов минимален.
 
> `ANALYZE` после `CREATE INDEX` не нужен: статистика таблиц не изменилась, а планировщик видит новый индекс сразу.
 
Повторите `EXPLAIN (ANALYZE, BUFFERS)` из п. 2.3.
 
**Эффект кэша.** Повторный запуск обычно быстрее, так как страницы уже в памяти. Для честного сравнения выполните каждый вариант 3 раза и берите последнее значение. Сравнивайте сумму `hit + read`, а не только `read`: при Seq Scan таблицы `order_items` значение `read` не станет 0 и при повторных запусках (кольцевой буфер, см. п. 1.3).
 
| Метрика | Без индексов | С индексами |
|---|---|---|
| Узел сканирования orders | ? | ? |
| Узел сканирования order_items | ? | ? |
| Тип JOIN | ? | ? |
| Execution Time, мс | ? | ? |
| Buffers: shared hit + read (верхний узел) | ? | ? |
 
### 2.5. auto_explain (опционально)
 
```sql
LOAD 'auto_explain';                    -- требует прав суперпользователя
SET auto_explain.log_min_duration = 0;  -- записывать план каждого запроса
SET auto_explain.log_analyze = on;      -- с фактическим временем (как EXPLAIN ANALYZE)
SET auto_explain.log_buffers = on;      -- со строками Buffers
SET client_min_messages = log;          -- показать план в клиенте, а не только в логе
 
SELECT COUNT(*) FROM order_items;
```
 
`client_min_messages = log` позволяет увидеть план без доступа к лог-файлу сервера. В DBeaver план появится на панели вывода сервера (кнопка «Show server output» на панели результатов).
 
> **`Workers Launched: 0` при `Workers Planned: 2`.** DBeaver получает результат порциями (fetch size). Если клиент запрашивает результат с ограничением числа строк, PostgreSQL выполняет параллельный план без рабочих процессов: всю работу делает ведущий процесс (`loops=1`). Поэтому время больше, чем у `EXPLAIN ANALYZE` того же запроса в п. 2.3. Дополнительно `log_analyze = on` замеряет время для каждой строки. Уменьшить эти накладные расходы: `SET auto_explain.log_timing = off;`.
 
Настройки действуют только в текущем сеансе. В этом сеансе в вывод попадут также служебные запросы DBeaver. После опыта переподключитесь (Invalidate/Reconnect): `log_analyze = on` замедляет каждый запрос.
 
---
 
## Часть 3. pgBadger (опционально)
 
### 3.1. Установка
 
pgBadger — скрипт на языке Perl. Для запуска в Windows нужен интерпретатор Perl.
 
1. Установите [Strawberry Perl](https://strawberryperl.com/) (установщик `.msi`, параметры по умолчанию).
2. Скачайте архив последнего релиза pgBadger: https://github.com/darold/pgbadger/releases (Source code, zip).
3. Распакуйте архив в `C:\pgbadger`. Файл `pgbadger` (без расширения) должен лежать в `C:\pgbadger\pgbadger`.
4. Проверьте в новом окне PowerShell:
```powershell
perl -v
perl C:\pgbadger\pgbadger --version
```
 
### 3.2. Настройка журнала
 
pgBadger разбирает лог по префиксу строки. Без совместимого формата отчёт будет пустым.
 
Сначала запишите текущие значения в `lab06_report.md` — они нужны для возврата настроек в п. 3.4:
 
```sql
SELECT name, setting
FROM   pg_settings
WHERE  name IN ('logging_collector', 'log_line_prefix',
                'lc_messages', 'log_min_duration_statement');
```
 
`logging_collector` должен быть `on`. Если `off` — журнал в файлы не пишется, pgBadger нечего анализировать. Включение: `ALTER SYSTEM SET logging_collector = on;` и перезапуск сервера (как в п. 1.1, шаг 4).
 
Задайте параметры для pgBadger:
 
```sql
ALTER SYSTEM SET log_line_prefix = '%t [%p]: user=%u,db=%d,app=%a,client=%h ';
ALTER SYSTEM SET lc_messages = 'C';               -- сообщения на английском
ALTER SYSTEM SET log_min_duration_statement = 0;  -- логировать все запросы
SELECT pg_reload_conf();
```
 
> С русской локалью сообщений (`lc_messages = 'ru_RU...'`) pgBadger не распознаёт строки `duration:`.
 
Создайте нагрузку: повторите запросы из частей 1–2.
 
### 3.3. Генерация отчёта
 
Найдите файл лога:
 
```sql
SELECT current_setting('data_directory') AS data_dir,
       current_setting('log_directory')  AS log_dir,
       pg_current_logfile()              AS current_log;
```
 
`current_log` — путь относительно `data_dir`, например `log/postgresql-2026-10-08_002924.log`.
 
Сформируйте и откройте отчёт (PowerShell; подставьте имя файла из `current_log`):
 
```powershell
perl C:\pgbadger\pgbadger "C:\Program Files\PostgreSQL\18\data\log\postgresql-2026-10-08_002924.log" -o $env:TEMP\eshop_report.html
Start-Process $env:TEMP\eshop_report.html
```
 
> PowerShell не раскрывает маску `*` для внешних программ. Указывайте полное имя файла.
 
> Чтение каталога `data\log` требует прав администратора. Запускайте PowerShell от имени администратора.
 
В отчёте найдите разделы «Slowest individual queries» и «Most frequent queries».
 
### 3.4. Вернуть настройки
 
Значение `log_min_duration_statement = 0` записывает в журнал каждый запрос и быстро заполняет диск. Верните значения, записанные в п. 3.2. Пример для значения `500` из лаб. 05:
 
```sql
ALTER SYSTEM SET log_min_duration_statement = 500;
SELECT pg_reload_conf();
```
 
Если до п. 3.2 параметр имел значение по умолчанию (`-1`, журналирование длительности выключено), удалите его из конфигурации:
 
```sql
ALTER SYSTEM RESET log_min_duration_statement;
SELECT pg_reload_conf();
```
 
`log_line_prefix` и `lc_messages` можно оставить: они не влияют на объём журнала.
 
---
 
## Часть 4. Анализ проблемного запроса (итоговое задание)
 
К этому моменту статистика содержит служебные команды частей 1–3: `CREATE INDEX`, `EXPLAIN`, `ANALYZE`. Они выполнялись долго и займут верх списка. Поэтому сначала соберите чистую статистику:
 
```sql
SELECT pg_stat_statements_reset();
```
 
Выполните запросы Q1–Q3 из п. 1.2 по 5 раз. Затем найдите запрос с наибольшим `mean_exec_time` (запрос из п. 1.3, сортировка по `mean_exec_time DESC`).
 
> Индексы из п. 2.4 к этому моменту созданы. Запрос, который был самым медленным в части 1, может стать быстрым. Анализируйте тот, который самый медленный **сейчас**.
 
> **Нормализованный текст.** В `pg_stat_statements` константы заменены параметрами (`WHERE status = $1`). Такой текст нельзя выполнить. Варианты:
> - подставьте значения вручную;
> - используйте `EXPLAIN (GENERIC_PLAN) <текст с $1>`. Этот вариант показывает план без выполнения, без `ANALYZE`.
 
Для выбранного запроса:
 
1. Выполните `EXPLAIN (ANALYZE, BUFFERS)`.
2. Определите причину медленной работы.
3. Предложите решение.
4. Реализуйте решение и сравните планы.
Типовые причины и решения:
 
| Признак в плане | Причина | Возможное решение |
|---|---|---|
| Seq Scan, фильтр отбирает малую часть строк | Нет подходящего индекса | Индекс по колонке фильтра или соединения |
| Seq Scan, нужны все строки таблицы | Объём работы определён смыслом запроса | Индекс не поможет. Переписать запрос, материализованное представление |
| Оценка `rows` отличается от факта в разы (не параллельный узел) | Устаревшая статистика | `ANALYZE`, расширенная статистика (`CREATE STATISTICS`) |
| `Batches > 1` в Hash / HashAggregate, `Sort Method: external merge` | Не хватает `work_mem` | Увеличить `work_mem` для сеанса |
| JOIN выполняется над большим числом строк до агрегации | Неоптимальный порядок операций | Агрегировать в подзапросе до JOIN |
 
Оформите вывод:
 
| Запрос | Причина медленной работы | Решение | Эффект |
|---|---|---|---|
| ... | ... | ... | ... |
 
### Пример оформления
 
Запрос Q3 (продажи по товарам). План: Parallel Seq Scan по `order_items` (вся таблица), Hash Join 600 000 строк с `products`, затем агрегация. Индекс не поможет: запросу нужны все строки `order_items`.
 
Решение — агрегировать до соединения:
 
```sql
SELECT p.name, s.total_sold
FROM  (SELECT product_id, SUM(quantity) AS total_sold
       FROM   order_items
       GROUP  BY product_id) s
JOIN   products p ON p.id = s.product_id
ORDER  BY s.total_sold DESC;
```
 
| Запрос | Причина медленной работы | Решение | Эффект |
|---|---|---|---|
| Q3: продажи по товарам | Полная агрегация 600 000 строк; Hash Join выполняется до агрегации | Агрегация `order_items` в подзапросе до JOIN | Hash Join: 600 000 → 1 000 строк. Время ≈ −40 % (293 → 171 мс в эталонном прогоне). Объём чтения не изменился |
 
---
 
## Чек-лист «работа зачтена»
 
- [ ] `pg_stat_statements` подключён: `SELECT count(*) FROM pg_stat_statements` выполняется без ошибки.
- [ ] Файл отчёта `lab06_report.md` создан; все таблицы и ответы перенесены в него.
- [ ] Таблица топ-запросов (п. 1.3) заполнена, включая `страниц / calls`.
- [ ] Для запросов Q1–Q3 определено, какие читают таблицы целиком (п. 1.4).
- [ ] `EXPLAIN ANALYZE` выполнен до и после создания индексов; таблица сравнения (п. 2.4) заполнена.
- [ ] Итоговый анализ проблемного запроса (часть 4) оформлен.
- [ ] Значение `log_min_duration_statement` возвращено к исходному (если выполнялась часть 3).
## Самостоятельное задание
 
1. Найдите запрос с наибольшим отношением `stddev_exec_time / mean_exec_time`. Что означает нестабильное время? Проверьте гипотезы: прогрев кэша при первых запусках, конкуренция с другими сеансами, разные значения параметров `$1`.
2. Что означает `Batches > 1` в узле Hash Join? Воспроизведите:
```sql
   SET work_mem = '64kB';
   EXPLAIN (ANALYZE, BUFFERS) <запрос из п. 2.3>;
   RESET work_mem;
```
   Выполняйте до создания индексов в п. 2.4 или удалите их (`DROP INDEX idx_...`). С индексами планировщик, скорее всего, выберет Nested Loop без хеш-таблицы, и `Batches` не появится.
   Сравните `Batches` и `Execution Time` со значением `work_mem` по умолчанию.
3. Почему планировщик иногда выбирает Seq Scan, хотя индекс существует? Проверьте на запросе Q2 (`status = 'pending'`, ≈ 20 % строк): создайте индекс по `status` и посмотрите, будет ли он использован.
4. PostgreSQL создаёт индексы автоматически только для PRIMARY KEY и UNIQUE, но не для внешних ключей. Найдите внешние ключи без индексов (выполните до п. 2.4):
```sql
   SELECT c.conrelid::regclass AS tbl,
          a.attname            AS fk_column
   FROM   pg_constraint c
   JOIN   pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
   WHERE  c.contype = 'f'
     AND  NOT EXISTS (
            SELECT 1 FROM pg_index i
            WHERE  i.indrelid = c.conrelid
              AND  i.indkey[0] = c.conkey[1]);
```
   Ожидаемо: `orders.customer_id`, `order_items.order_id`, `order_items.product_id`. Объясните, как отсутствие индекса на `order_items.order_id` влияет на удаление заказа. Проверьте:
```sql
   BEGIN;
   DELETE FROM order_items WHERE order_id = 1;        -- сначала удалить позиции, иначе FK запретит удаление
   EXPLAIN (ANALYZE) DELETE FROM orders WHERE id = 1;
   ROLLBACK;
```
   Найдите в выводе строку `Trigger for constraint order_items_order_id_fkey: time=...`. Повторите после создания индекса `idx_order_items_order` и сравните время.
 
## Ссылки
 
- pg_stat_statements: https://www.postgresql.org/docs/current/pgstatstatements.html
- EXPLAIN: https://www.postgresql.org/docs/current/sql-explain.html
- Использование EXPLAIN: https://www.postgresql.org/docs/current/using-explain.html
- auto_explain: https://www.postgresql.org/docs/current/auto-explain.html
- ALTER SYSTEM: https://www.postgresql.org/docs/current/sql-altersystem.html
- pgBadger: https://github.com/darold/pgbadger
 
