# Лекция 8. Анализ медленных запросов: pg_stat_statements, EXPLAIN, auto_explain, pgBadger
 
**Неделя:** 8
**Версия PostgreSQL:** 18
**Практика:** лабораторная работа №6
 
## Цель лекции
 
По итогам лекции студент:
 
- знает, как использовать `pg_stat_statements` для поиска самых дорогих запросов;
- умеет читать план выполнения (`EXPLAIN ANALYZE`) и находить узкие места;
- понимает, как `auto_explain` и pgBadger помогают анализировать медленные запросы;
- умеет передать DBA запрос и план для анализа.
  
### Порядок анализа
 
1. **Найти** дорогой запрос — `pg_stat_statements` (или pgBadger по журналу).
2. **Объяснить**, почему он дорогой, — `EXPLAIN (ANALYZE, BUFFERS)`.
3. **Исправить** — индекс, переписать запрос, изменить параметры.
4. **Проверить** — повторный `EXPLAIN ANALYZE` и `pg_stat_statements` после сброса.
   
---
 
## 1. pg_stat_statements: накопительная статистика запросов
 
`pg_stat_statements` — расширение PostgreSQL. Оно накапливает статистику выполнения всех запросов: число вызовов, время, число прочитанных страниц.
 
Запросы группируются по структуре. Константы заменяются параметрами: запросы `WHERE status = 'pending'` и `WHERE status = 'shipped'` попадают в одну строку статистики `WHERE status = $1`.
 
### 1.1. Установка
 
Библиотека расширения должна загружаться при старте сервера. Поэтому нужен перезапуск.
 
```sql
-- 1. Проверить текущий список библиотек
SHOW shared_preload_libraries;
 
-- 2. Записать параметр. ALTER SYSTEM ЗАМЕНЯЕТ весь список:
--    если в шаге 1 есть другие библиотеки, перечислите их через запятую
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
 
-- 3. Перечитать конфигурацию и проверить: true = ждёт перезапуска
SELECT pg_reload_conf();
SELECT pending_restart FROM pg_settings WHERE name = 'shared_preload_libraries';
```
 
```powershell
# 4. Перезапустить сервер (PowerShell от имени администратора)
Restart-Service postgresql-x64-18
```
 
```sql
-- 5. Создать расширение в нужной базе
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```
 
> `ALTER SYSTEM` записывает значение в `postgresql.auto.conf`. Альтернатива — ручная правка `postgresql.conf`. Результат одинаковый, но `ALTER SYSTEM` не требует доступа к файлам сервера.
 
> `ALTER SYSTEM` нельзя выполнить внутри транзакции. В DBeaver включите режим Auto-Commit.
 
### 1.2. Самые дорогие запросы по суммарному времени
 
```sql
SELECT LEFT(regexp_replace(query, '\s+', ' ', 'g'), 80) AS query_preview,
       calls,
       ROUND(total_exec_time::numeric, 0)  AS total_ms,
       ROUND(mean_exec_time::numeric, 1)   AS avg_ms,
       ROUND(stddev_exec_time::numeric, 1) AS stddev_ms,
       rows,
       shared_blks_hit,
       shared_blks_read
FROM   pg_stat_statements
WHERE  dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
  AND  query NOT ILIKE '%pg_catalog%'
  AND  query NOT ILIKE '%pg_stat%'
ORDER  BY total_exec_time DESC
LIMIT  10;
```
 
| Колонка | Значение |
|---|---|
| `calls` | Число выполнений |
| `total_exec_time` | Суммарное время, мс. Показывает общую нагрузку на сервер |
| `mean_exec_time` | Среднее время одного выполнения, мс |
| `stddev_exec_time` | Разброс времени. Большое значение — время нестабильно |
| `rows` | Суммарное число возвращённых или изменённых строк |
| `shared_blks_hit` | Страницы (8 КБ), найденные в shared_buffers |
| `shared_blks_read` | Страницы, которых не было в shared_buffers. Они пришли с диска **или из кэша ОС** |
 
Фильтры:
- `dbid` — представление содержит статистику всех баз кластера;
- `pg_catalog` — исключает служебные запросы клиентов (DBeaver, pgAdmin);
- `pg_stat` — исключает сам запрос к `pg_stat_statements`.
> `total_exec_time` — только время выполнения на сервере. В него не входят время планирования (учитывается отдельно при `pg_stat_statements.track_planning = on`) и передача результата клиенту по сети.
 
> Представление хранит до `pg_stat_statements.max` разных запросов (по умолчанию 5 000). При переполнении редкие запросы вытесняются. Число вытеснений и время последнего сброса показывает `SELECT * FROM pg_stat_statements_info;`. Частые вытеснения — повод увеличить `max`.
 
**Какую сортировку выбрать:**
 
| Сортировка | Что находит |
|---|---|
| `total_exec_time` | Запросы с наибольшей общей нагрузкой (часто — быстрые, но частые) |
| `mean_exec_time` | Самые медленные отдельные выполнения |
| `shared_blks_hit + shared_blks_read` | Запросы, которые читают больше всего данных |
 
**Число страниц на вызов.** Значение `(shared_blks_hit + shared_blks_read) / calls` — сколько страниц запрос читает за одно выполнение. Если оно близко к размеру таблицы (`pg_relation_size(...) / 8192`), запрос читает таблицу целиком.
 
> **Почему `shared_blks_read` остаётся большим при повторных запусках.** Если таблица больше ¼ shared_buffers (по умолчанию 128 МБ / 4 = 32 МБ), Seq Scan помещает прочитанные страницы не в общий кэш, а в малый кольцевой буфер (несколько сотен КБ). Так большой просмотр не вытесняет из кэша другие данные. Следствие: страницы такой таблицы почти не остаются в shared_buffers, и каждый Seq Scan снова даёт `read`. Страницы, попавшие в кэш другим путём (запись, Index Scan), используются и дают `hit`.
 
### 1.3. Нестабильные запросы
 
```sql
SELECT LEFT(regexp_replace(query, '\s+', ' ', 'g'), 80) AS query_preview,
       calls,
       ROUND(mean_exec_time::numeric, 1)   AS avg_ms,
       ROUND(stddev_exec_time::numeric, 1) AS stddev_ms,
       ROUND(max_exec_time::numeric, 1)    AS max_ms,
       ROUND((stddev_exec_time / NULLIF(mean_exec_time, 0))::numeric, 2) AS cv
FROM   pg_stat_statements
WHERE  calls >= 5          -- на рабочем сервере: >= 100
ORDER  BY cv DESC NULLS LAST
LIMIT  10;
```
 
`cv` (коэффициент вариации) = stddev / mean. Значение больше 1 означает, что время сильно меняется от вызова к вызову.
 
Возможные причины:
- первые вызовы читают данные вне кэша, следующие — из кэша;
- разные значения параметров `$1` отбирают разное число строк;
- конкуренция с другими сеансами за блокировки, CPU, диск.
> Порог `calls >= 5` подходит для учебного стенда. На рабочем сервере используйте `>= 100`: при малом числе вызовов статистика ненадёжна.
 
### 1.4. Сброс статистики
 
```sql
SELECT pg_stat_statements_reset();
```
 
Сбрасывайте статистику до и после изменения (например, создания индекса). Иначе старые медленные вызовы смешаются с новыми.
 
---
 
## 2. EXPLAIN ANALYZE: чтение плана выполнения
 
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.id, c.name, o.total_amount
FROM   orders o
JOIN   customers c ON o.customer_id = c.id
WHERE  o.created_at > now() - interval '30 days'
ORDER  BY o.total_amount DESC
LIMIT  100;
```
 
| Вариант | Что делает |
|---|---|
| `EXPLAIN` | Показывает план и **оценки**. Запрос не выполняется |
| `EXPLAIN ANALYZE` | **Выполняет** запрос и добавляет фактическое время и число строк |
| `BUFFERS` | Добавляет число прочитанных страниц. В PostgreSQL 18 включается автоматически вместе с `ANALYZE` |
 
**Важно: `EXPLAIN ANALYZE` выполняет запрос.** Для INSERT/UPDATE/DELETE используйте транзакцию с откатом:
 
```sql
BEGIN;
EXPLAIN ANALYZE UPDATE orders SET status = 'cancelled' WHERE id = 1;
ROLLBACK;
```
 
> Выполняйте блок целиком. Если в режиме Auto-Commit выполнить только строку `EXPLAIN ANALYZE UPDATE ...`, изменение зафиксируется.
 
### 2.1. Структура плана
 
План — дерево узлов. Каждый узел получает строки от дочерних узлов (с отступом ниже), обрабатывает их и передаёт выше. **Читайте план снизу вверх:** нижние узлы читают таблицы, верхние соединяют, группируют и сортируют.
 
### 2.2. Чтение строки плана
 
Пример из eshop (таблица `orders`, 200 000 строк, без индекса по дате):
 
```text
Parallel Seq Scan on orders o  (cost=0.00..4012.49 rows=5021 width=25)
                               (actual time=0.027..65.418 rows=8114.00 loops=1)
  Filter: (created_at > (now() - '30 days'::interval))
  Rows Removed by Filter: 191886
  Buffers: shared hit=1865
```
 
| Элемент | Значение |
|---|---|
| `cost=0.00..4012.49` | Оценочная стоимость в условных единицах: до первой строки .. до последней. Используется только для сравнения вариантов плана |
| `rows=5021` (в скобках `cost`) | **Оценка** планировщика: число строк. Для параллельного узла — на один процесс |
| `width=25` | Средний размер строки, байт |
| `actual time=0.027..65.418` | Фактическое время, мс: до первой строки .. до последней. **На один цикл**. **Включает время дочерних узлов** |
| `rows=8114.00` (в скобках `actual`) | **Фактическое** число строк на один цикл (среднее, поэтому дробное) |
| `loops=1` | Сколько раз узел выполнен. Всего строк = `rows × loops` |
| `Filter` | Условие, которое проверяется для каждой прочитанной строки |
| `Rows Removed by Filter` | Сколько строк прочитано зря. Большое значение при Seq Scan — индекс может помочь |
| `Buffers: shared hit` | Страницы из shared_buffers |
| `Buffers: shared read` | Страницы вне shared_buffers (диск или кэш ОС) |
 
**Собственное время узла** = (`actual time` × `loops`) узла − сумма (`actual time` × `loops`) его дочерних узлов. Узел с наибольшим собственным временем — узкое место.
 
> Для параллельных узлов (п. 2.4) не умножайте на `loops`: процессы работают одновременно, и `actual time` уже близко к реальному времени выполнения узла.
 
**`loops` больше 1** встречается в двух случаях:
- внутренний узел Nested Loop: выполняется по разу на каждую строку внешнего узла;
- параллельный план: по разу в каждом процессе (см. п. 2.4).
В конце плана:
 
| Строка | Значение |
|---|---|
| `Planning Time` | Время построения плана. Большое значение при первом запуске — каталог не в кэше |
| `Execution Time` | Время выполнения. Используйте для сравнения вариантов |
 
### 2.3. Основные узлы плана
 
**Доступ к таблице**
 
| Узел | Что делает | Когда появляется |
|---|---|---|
| `Seq Scan` | Читает все страницы таблицы по порядку | Нет подходящего индекса, таблица мала или нужна большая часть строк |
| `Index Scan` | Находит строки по индексу, читает их страницы таблицы | Отбирается малая часть строк (обычно единицы процентов) |
| `Index Only Scan` | Берёт данные из индекса. Таблицу читает только для страниц, которые не отмечены как полностью видимые (строка `Heap Fetches` в плане) | Все нужные колонки есть в индексе. Эффективен после `VACUUM` |
| `Bitmap Index Scan` + `Bitmap Heap Scan` | Собирает по индексу карту страниц, затем читает их по порядку | Среднее число строк (единицы–десятки процентов) или несколько условий через `BitmapAnd` / `BitmapOr` |
 
**Соединение**
 
| Узел | Что делает | Когда появляется |
|---|---|---|
| `Nested Loop` | Для каждой строки внешнего набора ищет строки во внутреннем | Внешний набор мал, по внутреннему есть индекс |
| `Hash Join` | Строит хеш-таблицу по одному набору, проверяет по ней строки другого | Большие наборы, равенство в условии соединения |
| `Merge Join` | Сливает два набора, отсортированных по ключу соединения | Оба набора отсортированы по ключу: по индексу или узлом Sort |
 
**Обработка результата**
 
| Узел | Что делает | Когда появляется |
|---|---|---|
| `Sort` | Сортирует строки | ORDER BY, подготовка к GroupAggregate или Merge Join |
| `HashAggregate` | Группирует через хеш-таблицу | GROUP BY, строки не отсортированы |
| `GroupAggregate` | Группирует отсортированный поток | GROUP BY, строки отсортированы |
| `Limit` | Останавливает выполнение после N строк | LIMIT |
 
**Параллельное выполнение** — см. п. 2.4.
 
### 2.4. Параллельные планы
 
Для таблиц больше 8 МБ (`min_parallel_table_scan_size`) PostgreSQL может запустить дополнительные рабочие процессы (parallel workers). Каждый процесс читает свою часть страниц. Ведущий процесс тоже участвует и объединяет результаты.
 
```text
Gather Merge  (... rows=2400 ...) (actual ... rows=3000.00 loops=1)
  Workers Planned: 2
  Workers Launched: 2
  ->  Sort  (... rows=1000 ...) (actual ... rows=1000.00 loops=3)
        ->  Partial HashAggregate  (...)
              ->  Parallel Seq Scan on order_items  (cost=0.00..7500.00 rows=250000 width=12)
                                                    (actual ... rows=200000.00 loops=3)
```
 
| Элемент | Значение |
|---|---|
| `Gather` / `Gather Merge` | Собирает строки от процессов. `Gather Merge` сохраняет порядок сортировки |
| `Parallel Seq Scan` | Каждый процесс читает часть страниц таблицы |
| `Partial ...` / `Finalize ...` | Агрегация в 2 этапа: частичная в каждом процессе, итоговая в ведущем |
| `Workers Planned` / `Workers Launched` | Сколько процессов запланировано / запущено |
| `loops=3` | 2 рабочих процесса + ведущий |
 
**Оценка `rows` в параллельном узле.** Для 2 рабочих процессов планировщик делит число строк на 2,4: он учитывает, что ведущий процесс участвует частично. Таблица 600 000 строк → оценка `rows=250000`, факт `rows=200000 loops=3`. Это **не** ошибка статистики.
 
**`Workers Launched` меньше `Workers Planned`** — свободных процессов не хватило, или клиент получает результат порциями (fetch size, например в DBeaver). Тогда работу выполняет ведущий процесс, и запрос идёт медленнее.
 
### 2.5. Признаки проблем в плане
 
| Признак | Интерпретация | Действие |
|---|---|---|
| Оценка `rows` отличается от факта в 10 раз и более (не параллельный узел) | Устаревшая статистика или зависимые условия | `ANALYZE table_name;`. Для зависимых колонок — `CREATE STATISTICS` |
| Seq Scan на большой таблице с большим `Rows Removed by Filter` | Нет подходящего индекса | Создать индекс по колонке фильтра |
| Seq Scan на большой таблице без фильтра | Запросу нужны все строки | Индекс не поможет. Переписать запрос, материализованное представление |
| `Hash` или `HashAggregate` с `Batches: 4` (больше 1) | Хеш-таблица не поместилась в память, данные записаны на диск | Увеличить `work_mem` для сеанса |
| `Sort Method: external merge  Disk: 4096kB` | Сортировка вышла на диск | Увеличить `work_mem` для сеанса |
| Nested Loop с большим `loops` у внутреннего Seq Scan | Внутренняя таблица читается целиком на каждую строку | Индекс по колонке соединения |
| Много `shared read` при повторных запусках | Данные не помещаются в кэш или таблица читается через кольцевой буфер (п. 1.2) | Уменьшить объём чтения (индекс). Изменение `shared_buffers` — обсудить с DBA |
 
> Лимит памяти: `work_mem` (по умолчанию 4 МБ) для сортировки; `work_mem × hash_mem_multiplier` (4 МБ × 2 = 8 МБ) для хеш-операций. Лимит действует на **каждый** узел каждого запроса. Глобальное увеличение `work_mem` опасно: при многих сеансах сервер может исчерпать память.
 
### 2.6. Пример: эффект индексов
 
Запрос eshop: заказы клиентов региона MSK за 30 дней с суммой позиций.
 
**Без индексов** (сокращено):
 
```text
Hash Join  (Hash Cond: o.customer_id = c.id)
  ->  Parallel Hash Join  (Hash Cond: oi.order_id = o.id)
        ->  Parallel Seq Scan on order_items oi   (rows=200000.00 loops=3)
        ->  Parallel Seq Scan on orders o          (Rows Removed by Filter: 191886)
  ->  Seq Scan on customers c                      (Rows Removed by Filter: 18993)
Execution Time: 197.607 ms
```
 
Чтобы найти 1 233 позиции, сервер прочитал все 600 000 строк `order_items`.
 
**С индексами** на `customers(region)`, `orders(created_at)`, `order_items(order_id)` (сокращено):
 
```text
Nested Loop
  ->  Hash Join  (Hash Cond: o.customer_id = c.id)
        ->  Bitmap Heap Scan on orders o
              ->  Bitmap Index Scan on idx_orders_created_at
        ->  Bitmap Heap Scan on customers c
              ->  Bitmap Index Scan on idx_customers_region
  ->  Index Scan using idx_order_items_order on order_items oi  (rows=3.00 loops=411)
Execution Time: 16.229 ms
```
 
Результат: в 12 раз быстрее. Для 411 заказов позиции найдены по индексу: 411 циклов по 3 строки.
 
Индекс `orders(customer_id)` тоже был создан, но планировщик его не использовал: путь через фильтр по дате оказался дешевле. **Созданный индекс не гарантирует его использование.**
 
### 2.7. Визуализация плана
 
Скопируйте вывод `EXPLAIN (ANALYZE, BUFFERS)` и вставьте на сайт:
 
- https://explain.depesz.com — выделяет цветом узлы с наибольшим собственным временем;
- https://explain.tensor.ru — русскоязычный интерфейс, рекомендации.
Оба сайта принимают текстовый формат. `FORMAT JSON` не обязателен.
 
> Не публикуйте планы рабочих систем: в них есть имена таблиц, колонок и значения из условий.
 
---
 
## 3. auto_explain: автоматическая запись планов
 
`auto_explain` записывает в журнал план запроса, который выполнялся дольше заданного порога. Не нужно повторять медленный запрос вручную: план уже в журнале, с фактическими значениями на момент выполнения.
 
### 3.1. Включение для одного сеанса
 
Подходит для учебного стенда и разовой проверки. Перезапуск не нужен.
 
```sql
LOAD 'auto_explain';                    -- права суперпользователя
SET auto_explain.log_min_duration = 0;  -- план каждого запроса
SET auto_explain.log_analyze = on;
SET auto_explain.log_buffers = on;
SET client_min_messages = log;          -- показать план в клиенте
```
 
### 3.2. Постоянное включение для сервера
 
```sql
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements,auto_explain';
ALTER SYSTEM SET auto_explain.log_min_duration = '1s';  -- запросы дольше 1 с
ALTER SYSTEM SET auto_explain.log_analyze = on;
ALTER SYSTEM SET auto_explain.log_buffers = on;
ALTER SYSTEM SET auto_explain.log_timing = off;         -- см. ниже
ALTER SYSTEM SET auto_explain.log_nested_statements = on;
-- перезапуск сервера
```
 
> **Накладные расходы `log_analyze`.** Сервер не знает заранее, превысит ли запрос порог. Поэтому при `log_analyze = on` сбор фактических данных включается для **каждого** запроса, а не только для медленных. Самая дорогая часть — замер времени для каждой строки каждого узла. На рабочем сервере:
> - `auto_explain.log_timing = off` — строки и Buffers остаются, время по узлам не замеряется;
> - `auto_explain.sample_rate = 0.1` — анализировать только 10 % запросов.
 
`log_nested_statements = on` — записывать также запросы внутри функций и процедур.
 
### 3.3. Пример записи в журнале
 
```text
2026-10-08 15:22:33 MSK [5678]: user=app,db=eshop,app=crm,client=10.0.0.5 LOG:  duration: 3451.234 ms  plan:
	Query Text: SELECT o.id, c.name FROM orders o JOIN customers c ON o.customer_id = c.id
	            WHERE o.created_at > '2024-01-01'
	Hash Join  (cost=617.00..157553.00 rows=2400000 width=40) (actual time=6.112..3302.910 rows=2412345 loops=1)
	  Hash Cond: (o.customer_id = c.id)
	  Buffers: shared hit=167 read=93000
	  ->  Seq Scan on orders o  (cost=0.00..124250.00 rows=2400000 width=16) (actual time=0.123..2795.456 rows=2412345 loops=1)
	        Filter: (created_at > '2024-01-01 00:00:00+03'::timestamp with time zone)
	        Rows Removed by Filter: 87655
	        Buffers: shared read=93000
	  ->  Hash  (cost=367.00..367.00 rows=20000 width=32) (actual time=5.801..5.802 rows=20000 loops=1)
	        Buckets: 32768  Batches: 1  Memory Usage: 1450kB
	        Buffers: shared hit=167
	        ->  Seq Scan on customers c  (cost=0.00..367.00 rows=20000 width=32) (actual time=0.010..2.215 rows=20000 loops=1)
	              Buffers: shared hit=167
```
 
Как читать: время уходит на `Seq Scan on orders` (2,8 с из 3,3 с), страницы читаются вне кэша (`read=93000`). Фильтр отсекает всего 3,5 % строк, поэтому индекс по `created_at` здесь **не** поможет: запросу нужна почти вся таблица.
 
---
 
## 4. pgBadger: анализ журнала
 
pgBadger читает журнал PostgreSQL и строит HTML-отчёт: самые медленные и самые частые запросы, блокировки, ошибки, графики нагрузки по времени.
 
**Отличие от `pg_stat_statements`:**
 
| | pg_stat_statements | pgBadger |
|---|---|---|
| Источник | Память сервера | Файлы журнала |
| Данные | Сводные (сумма, среднее) по всем запросам | Каждый запрос, записанный в журнал (дольше порога), с моментом выполнения и параметрами |
| Ответ на вопрос | «Какой запрос самый дорогой?» | «Что было медленным вчера в 15:20?» |
| Требует | Расширение | Настроенный журнал |
 
### 4.1. Требования к журналу
 
```sql
ALTER SYSTEM SET logging_collector = on;   -- запись в файлы (требует перезапуска)
ALTER SYSTEM SET log_line_prefix = '%t [%p]: user=%u,db=%d,app=%a,client=%h ';
ALTER SYSTEM SET lc_messages = 'C';        -- сообщения на английском
ALTER SYSTEM SET log_min_duration_statement = 500;  -- запросы дольше 500 мс
SELECT pg_reload_conf();
```
 
- `logging_collector` — в установке PostgreSQL для Windows включён по умолчанию.
- `log_line_prefix` — формат префикса строки (см. лекцию 7). pgBadger определяет по нему время, пользователя, базу.
- `lc_messages = 'C'` — **обязательно для русской локали.** pgBadger ищет английские строки `duration:`, `statement:`. С русскими сообщениями отчёт будет пустым.
- `log_min_duration_statement` — порог записи запросов. `0` — все запросы (только для учебного стенда: журнал быстро растёт).
> `lc_messages` и `log_line_prefix` после `pg_reload_conf()` действуют для **новых** сеансов. Переподключитесь, прежде чем создавать нагрузку.
 
Для полного отчёта pgBadger (блокировки, временные файлы, контрольные точки, автоочистка) включите также:
 
```sql
ALTER SYSTEM SET log_lock_waits = on;                  -- ожидания блокировок дольше deadlock_timeout
ALTER SYSTEM SET log_temp_files = 0;                   -- все временные файлы (выход сортировок и хешей на диск)
ALTER SYSTEM SET log_checkpoints = on;
ALTER SYSTEM SET log_autovacuum_min_duration = 0;
SELECT pg_reload_conf();
```
 
`log_temp_files = 0` связывает журнал с п. 2.5: каждая запись — запрос, которому не хватило `work_mem`.
 
### 4.2. Установка и запуск в Windows
 
pgBadger — скрипт на Perl. Нужен [Strawberry Perl](https://strawberryperl.com/) и скрипт из https://github.com/darold/pgbadger/releases (распаковать в `C:\pgbadger`).
 
Путь к файлу журнала:
 
```sql
SELECT current_setting('data_directory') AS data_dir,
       pg_current_logfile()              AS current_log;
```
 
Отчёт (PowerShell от имени администратора):
 
```powershell
perl C:\pgbadger\pgbadger "C:\Program Files\PostgreSQL\18\data\log\postgresql-2026-10-08_002924.log" -o $env:TEMP\report.html
Start-Process $env:TEMP\report.html
```
 
> PowerShell не раскрывает маску `*` для внешних программ. Указывайте полное имя файла. Для нескольких файлов — перечислите их через пробел.
 
Разделы отчёта для анализа медленных запросов: **Slowest individual queries**, **Time consuming queries**, **Most frequent queries**.
 
---
 
## 5. Что передавать DBA при анализе медленного запроса
 
DBA не может воспроизвести вашу ситуацию без контекста. Передайте всё одним документом.
 
```markdown
## Запрос для анализа
 
### Запрос (полный текст, с реальными значениями параметров)
SELECT o.id, c.name, o.total_amount
FROM   orders o
JOIN   customers c ON o.customer_id = c.id
WHERE  o.created_at > '2024-01-01'
ORDER  BY o.total_amount DESC;
 
### Окружение
- Версия: PostgreSQL 18.0 (SELECT version();)
- База: eshop
- work_mem = 4MB, shared_buffers = 128MB
 
### Таблицы
- orders: 3 млн строк, 230 МБ (pg_relation_size)
- Индексы orders: orders_pkey (id), idx_orders_customer_id (customer_id)
 
### Статистика (строка из pg_stat_statements)
- calls = 500 в сутки, mean_exec_time = 4 500 мс, stddev = 300 мс
- shared_blks_read / calls = 93 000 страниц
 
### Вывод EXPLAIN (ANALYZE, BUFFERS)
[полный вывод, без сокращений]
 
### Наблюдения
- Seq Scan на orders, Rows Removed by Filter = 87 655 из 3 млн:
  фильтр по created_at отсекает 3 % строк
- Buffers: read = 93 000 при повторных запусках — таблица больше кэша
 
### Ожидание
Запрос должен выполняться < 200 мс (SLA отчёта).
```
 
Правила:
- **Полный план, без сокращений.** Важные детали часто в глубине дерева.
- **Реальные значения параметров**, а не `$1`. План зависит от значений.
- **Разделяйте источники:** `shared_blks_read` — колонка `pg_stat_statements` (сумма за все вызовы); `Buffers: read` — строка плана (один вызов).
---
 
## 6. Итоги лекции
 
После этой лекции студент умеет:
 
1. Подключить `pg_stat_statements` (`ALTER SYSTEM`, перезапуск, `CREATE EXTENSION`) и найти дорогие запросы по `total_exec_time`, `mean_exec_time`, числу страниц на вызов.
2. Прочитать план `EXPLAIN ANALYZE` снизу вверх: найти узел с наибольшим собственным временем, учесть `loops`, сравнить оценку и факт `rows`.
3. Распознать параллельный план и не принять делитель 2,4 за ошибку статистики.
4. Найти признаки проблем: Seq Scan с большим `Rows Removed by Filter`, `Batches > 1`, `external merge`, большое `read`.
5. Безопасно выполнить `EXPLAIN ANALYZE` для DML: `BEGIN` / `ROLLBACK`.
6. Включить `auto_explain` и учесть накладные расходы `log_analyze`.
7. Настроить журнал для pgBadger (`log_line_prefix`, `lc_messages`) и построить отчёт.
8. Передать DBA запрос, план, окружение и строку из `pg_stat_statements`.
## Ссылки
 
- pg_stat_statements: https://www.postgresql.org/docs/current/pgstatstatements.html
- EXPLAIN: https://www.postgresql.org/docs/current/sql-explain.html
- Использование EXPLAIN: https://www.postgresql.org/docs/current/using-explain.html
- Параллельные запросы: https://www.postgresql.org/docs/current/parallel-query.html
- auto_explain: https://www.postgresql.org/docs/current/auto-explain.html
- ALTER SYSTEM: https://www.postgresql.org/docs/current/sql-altersystem.html
- pgBadger: https://pgbadger.darold.net
- explain.depesz.com: https://explain.depesz.com
- explain.tensor.ru: https://explain.tensor.ru
