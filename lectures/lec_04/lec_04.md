# Лекция 4. Привилегии, схемы, разграничение доступа. RLS. Уровни изоляции

**Неделя:** 4  
**Версия PostgreSQL:** 18  
**Практика:** лабораторная работа №2 «Роли, привилегии, схемы. Проект eshop» (части 2–4)

---

## Цель лекции

По итогам лекции студент:

- знает иерархию привилегий PostgreSQL — от базы данных до колонки;
- умеет применять `GRANT`/`REVOKE` и настраивать привилегии по умолчанию для будущих объектов;
- понимает роль схем в изоляции объектов и управление `search_path`;
- знает принцип Row-Level Security и когда его применять;
- понимает уровни изоляции транзакций и умеет выбрать нужный;
- умеет подготовить матрицу доступа для передачи DBA.

---

## Зачем это системному аналитику

Аналитик не пишет `GRANT`-скрипты в production. Но он определяет **кто и что должен видеть**. От этой формулировки зависит:

- увидит ли менеджер заказы только своего региона;
- сможет ли BI-инструмент прочитать персональные данные клиентов;
- получит ли приложение право удалить заказ;
- не окажется ли новая таблица, созданная миграцией, доступной всем желающим.

Ошибка в матрице доступа — это либо инцидент ИБ (слишком широкие права), либо инцидент production (слишком узкие права, приложение падает на `permission denied`). Оба варианта дороже, чем 20 минут на проектирование.

> **Ключевая мысль.** Привилегии — не «галочки в интерфейсе». Это контракт между бизнес-требованием и физической возможностью роли. Если контракт не описан, DBA выдаст права «как получится».

---

## 1. Вводный кейс

> **Кейс из практики.**  
> В `eshop` добавили таблицу `promo_codes` (промокоды) миграцией Flyway. Через неделю выяснилось:
> - приложение не может прочитать промокоды: `permission denied for table promo_codes`;
> - при этом BI-роль, которая читает `orders`, внезапно получила доступ к новой таблице;
> - менеджер регионального отделения видит промокоды всех регионов;
> - аналитик случайно выполнил `SELECT * FROM orders` и увидел заказы всех клиентов, хотя по требованиям должен видеть только агрегаты.

**Вопросы аудитории:**
1. Почему приложение не видит новую таблицу, если ему когда-то выдали права на «все таблицы схемы»?
2. Почему BI-роль получила доступ, хотя никто ничего не выдавал?
3. Какие два механизма нужны, чтобы менеджер видел только свой регион?

К концу лекции мы разберём иерархию привилегий, схему `public` в PostgreSQL 14+, `ALTER DEFAULT PRIVILEGES` и RLS.

---

## 2. Иерархия привилегий PostgreSQL

Привилегии организованы по уровням. Доступ к объекту нижнего уровня требует разрешений на всех вышестоящих уровнях.

```
Уровень кластера
  └── Уровень базы данных   (CONNECT, CREATE, TEMP)
        └── Уровень схемы   (USAGE, CREATE)
              ├── Таблица / представление  (SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER)
              ├── Колонка                  (SELECT, INSERT, UPDATE, REFERENCES)
              ├── Последовательность       (USAGE, SELECT, UPDATE)
              └── Функция / процедура      (EXECUTE)
```

> **Частая ошибка:** выдать `SELECT` на таблицу, не выдав `USAGE` на схему. Пользователь получит ошибку `permission denied for schema public`, даже имея явный `GRANT SELECT ON TABLE`.

### 2.1. Что означает каждый уровень

| Уровень | Привилегия | Что разрешает |
|---|---|---|
| База | `CONNECT` | Подключаться к базе |
| База | `CREATE` | Создавать схемы в базе |
| База | `TEMP` | Создавать временные таблицы |
| Схема | `USAGE` | «Видеть» объекты схемы, обращаться к ним по имени |
| Схема | `CREATE` | Создавать объекты в схеме |
| Таблица | `SELECT` / `INSERT` / `UPDATE` / `DELETE` | Чтение и изменение строк |
| Таблица | `TRUNCATE` | Быстро очистить таблицу |
| Таблица | `REFERENCES` | Создавать внешние ключи на таблицу |
| Таблица | `TRIGGER` | Создавать триггеры |
| Колонка | `SELECT` / `INSERT` / `UPDATE` / `REFERENCES` | Доступ к отдельным колонкам |
| Последовательность | `USAGE`, `SELECT`, `UPDATE` | Получать `nextval()`, читать/менять текущее значение |
| Функция | `EXECUTE` | Вызывать функцию |

> Подробный справочник по `GRANT`/`REVOKE`, владению и default privileges — в статье [Привилегии](../../wiki/concepts/privileges.md).

---

## 3. `GRANT` и `REVOKE`

### 3.1. Синтаксис `GRANT`

```sql
-- База данных
GRANT CONNECT ON DATABASE myapp TO app_user;
GRANT CONNECT ON DATABASE myapp TO app_readonly;

-- Схема
GRANT USAGE  ON SCHEMA public TO app_readonly;    -- разрешить «видеть» схему
GRANT USAGE  ON SCHEMA public TO app_readwrite;
GRANT CREATE ON SCHEMA public TO app_admin;        -- разрешить создавать объекты

-- Таблицы (уже существующие в схеме)
GRANT SELECT                              ON ALL TABLES IN SCHEMA public TO app_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE      ON ALL TABLES IN SCHEMA public TO app_readwrite;

-- Последовательности (нужны для INSERT в таблицы с SERIAL / BIGSERIAL / IDENTITY)
GRANT USAGE, SELECT                       ON ALL SEQUENCES IN SCHEMA public TO app_readwrite;

-- Функции
GRANT EXECUTE ON FUNCTION calculate_tax(numeric) TO app_readwrite;
```

### 3.2. `WITH GRANT OPTION`

Грантополучатель может передавать привилегию другим ролям:

```sql
GRANT SELECT ON TABLE reports TO analyst_ivanova WITH GRANT OPTION;
-- analyst_ivanova теперь может сама выдавать SELECT на reports
```

> Использовать осторожно: усложняет аудит цепочки прав. Для большинства команд `WITH GRANT OPTION` не нужен — права выдаёт только DBA.

### 3.3. `REVOKE`

```sql
-- Отозвать конкретную привилегию
REVOKE INSERT ON TABLE orders FROM app_readonly;

-- Отозвать все привилегии
REVOKE ALL PRIVILEGES ON TABLE orders FROM app_readonly;

-- Каскадный отзыв (если привилегия была передана дальше через GRANT OPTION)
REVOKE SELECT ON TABLE reports FROM analyst_ivanova CASCADE;
```

> **`REVOKE` не удаляет объекты.** Он снимает право. Таблица остаётся, данные остаются — меняется только доступ.

### 3.4. Просмотр привилегий

```sql
-- Привилегии на таблицы через information_schema
SELECT grantee, table_schema, table_name, privilege_type
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public'
ORDER  BY grantee, table_name, privilege_type;

-- Привилегии в psql
\dp orders      -- привилегии на конкретную таблицу
\dn+            -- схемы с привилегиями
```

### 3.5. Владение объектом

Владелец объекта (`owner`) может делать с ним всё, включая `DROP`, и может выдавать права. Поэтому вопрос «кому принадлежит таблица» не менее важен, чем «кому выданы права».

```sql
-- Кто владеет таблицами
SELECT schemaname, tablename, tableowner
FROM   pg_tables
WHERE  schemaname = 'public'
ORDER  BY tablename;
```

> **Антипаттерн.** Все объекты принадлежат `postgres`, а приложение работает под `app_user`. Тогда любая миграция от `migration_runner` может неожиданно упасть на правах. В команде договариваются о роли-владельце схемы и о `ALTER DEFAULT PRIVILEGES FOR ROLE`.

---

## 4. Привилегии по умолчанию (`ALTER DEFAULT PRIVILEGES`)

`GRANT ON ALL TABLES` выдаёт права только на **уже существующие** объекты. Новые таблицы, созданные позже, привилегий не получают.

Именно поэтому в кейсе приложение не увидело `promo_codes`: миграция создала таблицу после того, как был выполнен `GRANT ... ON ALL TABLES`.

Решение — `ALTER DEFAULT PRIVILEGES`:

```sql
-- Для всех таблиц, которые schema_owner создаст в будущем в public,
-- автоматически выдавать SELECT роли app_readonly
ALTER DEFAULT PRIVILEGES FOR ROLE schema_owner IN SCHEMA public
  GRANT SELECT ON TABLES TO app_readonly;

-- Аналогично для последовательностей
ALTER DEFAULT PRIVILEGES FOR ROLE schema_owner IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO app_readwrite;

-- Для функций
ALTER DEFAULT PRIVILEGES FOR ROLE schema_owner IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO app_readwrite;
```

> **Важно:** `ALTER DEFAULT PRIVILEGES` привязана к роли-создателю (`FOR ROLE`). Если объекты создаёт другой пользователь, нужна отдельная настройка для него. При описании требований к доступу укажите DBA: нужны ли права на будущие объекты и кто их создаёт.

### 4.1. Проверка default privileges

```sql
SELECT pg_get_userbyid(defaclrole) AS owner,
       nspname AS schema,
       defaclobjtype AS object_type,
       defaclacl AS privileges
FROM   pg_default_acl
JOIN   pg_namespace ON pg_namespace.oid = defaclnamespace;
```

### 4.2. Почему BI-роль получила доступ

В PostgreSQL 14+ схема `public` больше не даёт `CREATE` всем ролям, но исторически сложившиеся `GRANT SELECT ON ALL TABLES` могли быть выданы широкой роли. Если новая таблица создана в той же схеме и владелец не настроил default privileges, поведение зависит от конкретных грантов. Вывод: **не полагайтесь на «само получится»** — проверяйте `\dp` и `information_schema.role_table_grants` после каждой миграции.

---

## 5. Схемы: организация и изоляция объектов

### 5.1. Что такое схема

**Схема** — пространство имён внутри базы данных. Все объекты (таблицы, функции, последовательности) принадлежат конкретной схеме.

```sql
-- Создать схему
CREATE SCHEMA reporting;

-- Создать схему с явным владельцем
CREATE SCHEMA reporting AUTHORIZATION analyst_ivanova;

-- Создать таблицу в схеме
CREATE TABLE reporting.monthly_sales (
  period     date,
  region     text,
  revenue    numeric(15,2)
);

-- Удалить схему вместе со всеми объектами (осторожно!)
DROP SCHEMA reporting CASCADE;
```

### 5.2. `search_path`

PostgreSQL ищет объекты по именам в порядке, заданном `search_path`. По умолчанию: `"$user", public`.

```sql
-- Текущий search_path
SHOW search_path;

-- Изменить для текущего сеанса
SET search_path TO reporting, public;

-- Закрепить за ролью постоянно
ALTER ROLE analyst_ivanova SET search_path TO reporting, public;
```

Если `search_path = reporting, public`, то запрос `SELECT * FROM monthly_sales` сначала ищет таблицу в схеме `reporting`, потом в `public`. Это позволяет разным ролям «видеть» разные версии одноимённых объектов.

> **Уязвимость `search_path`.** Если злоумышленник может создать объект в схеме, стоящей в `search_path` раньше доверенной, он может подменить функцию или таблицу. Поэтому в production `search_path` фиксируют на уровне роли и не включают туда схемы, куда может писать непривилегированный пользователь.

### 5.3. Схема `public` в PostgreSQL 14+

До PostgreSQL 14 все роли по умолчанию имели `CREATE` на схему `public`. Начиная с PostgreSQL 14, это право **отозвано** у роли `PUBLIC`:

```sql
-- PostgreSQL 14+: явно выдать право создавать объекты в public
GRANT CREATE ON SCHEMA public TO app_admin;

-- Лучшая практика: использовать изолированные схемы
CREATE SCHEMA app;
GRANT USAGE, CREATE ON SCHEMA app TO app_readwrite;

CREATE SCHEMA reporting;
GRANT USAGE ON SCHEMA reporting TO app_readonly;
```

### 5.4. Паттерн изоляции по схемам

| Схема | Назначение | Доступ |
|---|---|---|
| `app` | Рабочие таблицы приложения | `USAGE` — `app_readonly`, `app_readwrite` |
| `reporting` | Материализованные представления, агрегаты | `USAGE` — только `app_readonly` |
| `internal` | Вспомогательные таблицы, не видны пользователям | Только DBA / `migration_runner` |
| `audit` | Аудит-лог, append-only | `SELECT` — DBA; `INSERT` — триггеры |

> **Почему это удобно аналитику.** Схемы — это границы контекста. Вместо «дать доступ к 40 таблицам» можно сказать: «дать `USAGE` на `reporting`». Матрица доступа становится короче и понятнее.

---

## 6. Привилегии на уровне колонок

PostgreSQL поддерживает управление доступом на уровне отдельных колонок:

```sql
-- Аналитик видит имя и email, но не passport_data
GRANT SELECT (id, name, email) ON TABLE employees TO analyst_ivanova;

-- Просмотр column-level привилегий
SELECT column_name, privilege_type, grantee
FROM   information_schema.column_privileges
WHERE  table_name = 'employees'
ORDER  BY grantee, column_name;
```

> **Альтернатива:** создать представление (`VIEW`) с нужными колонками и выдать права на него. Это проще в сопровождении: `GRANT SELECT ON VIEW employees_public TO app_readonly;`

### 6.1. Когда column-level, а когда VIEW

| Ситуация | Лучше |
|---|---|
| Нужно скрыть 1–2 чувствительные колонки | `VIEW` |
| Нужно дать `UPDATE` только на часть колонок | column-level `GRANT` |
| Нужна фильтрация строк по пользователю | RLS |
| Нужны вычисляемые поля | `VIEW` |

> **Ловушка.** `SELECT *` при column-level привилегиях завершится ошибкой: PostgreSQL попытается прочитать и запрещённые колонки. Поэтому BI-инструменты, которые всегда делают `SELECT *`, ломаются. Решение — `VIEW` с явным списком колонок.

---

## 7. Row-Level Security (RLS)

RLS позволяет ограничить, **какие строки** видит пользователь, а не только к какой таблице у него есть доступ.

### 7.1. Включение RLS

```sql
-- Включить RLS на таблице
-- По умолчанию запрещает все строки для не-суперпользователей (без политик = пустой результат)
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- Распространить политики и на владельца таблицы (суперпользователь всё равно обходит)
ALTER TABLE orders FORCE ROW LEVEL SECURITY;
```

> **Важно.** После `ENABLE ROW LEVEL SECURITY` без политик таблица выглядит пустой для обычных ролей. Это не ошибка, а безопасное поведение по умолчанию. Сначала включают RLS, затем создают политики.

### 7.2. Создание политик

```sql
-- Каждый пользователь видит только свои заказы
-- USING — применяется к SELECT, UPDATE, DELETE (что можно читать / изменять)
CREATE POLICY user_sees_own_orders ON orders
  FOR SELECT
  TO app_readonly
  USING (user_id = (SELECT id FROM users WHERE username = current_user));

-- Приложение видит только активные заказы
CREATE POLICY app_active_orders ON orders
  FOR ALL
  TO app_readwrite
  USING (status != 'archived');

-- Менеджер видит заказы своего региона
-- WITH CHECK — применяется к INSERT, UPDATE (что можно записывать)
CREATE POLICY manager_regional ON orders
  FOR ALL
  TO app_readwrite
  USING       (region = current_setting('app.current_region', true))
  WITH CHECK  (region = current_setting('app.current_region', true));
```

### 7.3. `USING` и `WITH CHECK`

| Клауза | К каким операциям применяется | Смысл |
|---|---|---|
| `USING` | `SELECT`, `UPDATE`, `DELETE` | Какие существующие строки роль может видеть/изменить/удалить |
| `WITH CHECK` | `INSERT`, `UPDATE` | Какие новые строки роль может записать |

Если `WITH CHECK` не указан, PostgreSQL использует `USING` и для проверки новых строк. Это важно: политика «вижу только свой регион» автоматически запретит вставить заказ чужого региона.

### 7.4. Управление политиками

```sql
-- Список политик на таблице
SELECT polname, polcmd, polroles, polqual
FROM   pg_policies
WHERE  tablename = 'orders';

-- Изменить политику
ALTER POLICY user_sees_own_orders ON orders
  USING (owner_id = current_setting('app.user_id')::int);

-- Удалить политику
DROP POLICY user_sees_own_orders ON orders;

-- Временно отключить RLS (только суперпользователь)
ALTER TABLE orders DISABLE ROW LEVEL SECURITY;
```

### 7.5. Когда применять RLS

| Сценарий | RLS? |
|---|---|
| Мультитенантность (данные изолированы по `tenant_id`) | Да |
| Персональные данные — каждый видит только свои | Да |
| Региональное разграничение данных | Да |
| Простое разграничение read/write по таблицам | Нет — достаточно `GRANT` |
| Более 5 политик на одну таблицу | Осторожно — влияет на производительность планировщика |

> RLS применяется после аутентификации и стандартных проверок привилегий. Если у роли нет `SELECT` на таблицу — до политик дело не дойдёт.

### 7.6. RLS и производительность

Политика добавляется к каждому запросу как дополнительное условие. Чтобы она не превратила быстрый запрос в `Seq Scan`:

- создайте индекс по колонке, которая используется в `USING` (`tenant_id`, `region`, `user_id`);
- не используйте в политике подзапросы к большим таблицам без индексов;
- проверяйте план через `EXPLAIN (ANALYZE, BUFFERS)` под нужной ролью (`SET ROLE`).

> **Практика →** [Лаб. 02, часть 4 — RLS и проверка через `SET ROLE`](../../labs/lab_02/lab_02.md).

---

## 8. Матрица доступа — инструмент аналитика

Прежде чем передавать задачу DBA, аналитик готовит **матрицу доступа**. Это документ, по которому DBA выполняет `GRANT`/`REVOKE` и настраивает `pg_hba.conf`.

> Шаблон и пример заполнения — в статье [Матрица доступа](../../wiki/artifacts/access-matrix.md).

### 8.1. Шаблон матрицы

| Роль / профиль | БД | Схема | Объект | SELECT | INSERT | UPDATE | DELETE | TRUNCATE | EXECUTE | Примечания |
|---|---|-------|--------|:------:|:------:|:------:|:------:|:--------:|:-------:|-------------|
| `app_readonly` | myapp_prod | public | все таблицы | ✓ | | | | | | + `USAGE` на схему |
| `app_readwrite` | myapp_prod | public | все таблицы | ✓ | ✓ | ✓ | ✓ | | | + `USAGE` на схему |
| `app_readwrite` | myapp_prod | public | все последовательности | ✓ | | ✓ | | | | Нужно для `INSERT` с `SERIAL` |
| `analyst_ivanova` | myapp_prod | reporting | все таблицы | ✓ | | | | | | + `USAGE` на `reporting` |
| `migration_runner` | myapp_prod | public | все объекты | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | Для `flyway migrate` |

### 8.2. Чек-лист передачи DBA

```
[ ] Роли и пользователи описаны (шаблон из лекции 3)
[ ] Матрица доступа заполнена для всех ролей
[ ] Указан USAGE на схемы (не только привилегии на объекты)
[ ] Указан USAGE + SELECT на последовательности (для INSERT с SERIAL/BIGSERIAL)
[ ] Указано: нужны ли права на будущие объекты (ALTER DEFAULT PRIVILEGES)
[ ] Указано: нужен ли RLS, на каких таблицах и какая логика политик
[ ] Column-level привилегии (если есть): перечислены колонки и роли
[ ] Согласовано с ответственным за информационную безопасность
```

---

## 9. Уровни изоляции транзакций

ACID-гарантия Isolation определяет, насколько параллельные транзакции «видят» изменения друг друга. В PostgreSQL 4 уровня.

> Подробный разбор аномалий, MVCC и практических сценариев — в статье [Уровни изоляции](../../wiki/concepts/transaction-isolation.md).

### 9.1. Таблица уровней и аномалий

| Уровень изоляции | Грязное чтение | Неповторяемое чтение | Фантомное чтение | Аномалия сериализации |
|---|:---:|:---:|:---:|:---:|
| Read Uncommitted | Невозможно¹ | Возможно | Возможно | Возможно |
| **Read Committed** | Невозможно | Возможно | Возможно | Возможно |
| Repeatable Read | Невозможно | Невозможно | Невозможно² | Возможно |
| Serializable | Невозможно | Невозможно | Невозможно | Невозможно |

¹ PostgreSQL не реализует грязное чтение даже на `Read Uncommitted` — используется `Read Committed`.  
² PostgreSQL устранил фантомы на `Repeatable Read` через MVCC (в стандарте SQL они были разрешены).

### 9.2. Уровни по умолчанию и как их применять

```sql
-- Посмотреть текущий уровень
SHOW transaction_isolation;    -- read committed (по умолчанию)

-- Установить для одной транзакции
BEGIN ISOLATION LEVEL REPEATABLE READ;
-- ... запросы ...
COMMIT;

-- Установить глобально (postgresql.conf)
default_transaction_isolation = 'read committed'
```

### 9.3. Примеры аномалий

#### Неповторяемое чтение (Read Committed)

```sql
-- Транзакция 1 (Read Committed):
BEGIN;
SELECT price FROM products WHERE id = 1;   -- = 1000

-- Транзакция 2 (в это время):
UPDATE products SET price = 2000 WHERE id = 1; COMMIT;

-- Транзакция 1 (тот же запрос):
SELECT price FROM products WHERE id = 1;   -- = 2000 (цена изменилась!)
COMMIT;
```

**Решение:** поднять до `REPEATABLE READ` — тогда транзакция 1 увидит 1000 в обоих `SELECT`.

#### Аномалия сериализации (write skew)

```sql
-- Два врача одновременно хотят уйти на перерыв.
-- Правило: хотя бы один врач должен быть на смене.
-- При REPEATABLE READ оба видят «1 врач доступен» → оба уходят → правило нарушено.
-- При SERIALIZABLE одна из транзакций откатится с ошибкой serialization failure.
```

### 9.4. Когда какой уровень применять

| Сценарий | Уровень изоляции |
|---|---|
| Обычные OLTP-операции (`INSERT`/`UPDATE`/`SELECT`) | `Read Committed` |
| Аналитический `SELECT` по «срезу» данных на момент T | `Repeatable Read` |
| Финансовые операции с бизнес-инвариантами | `Serializable` |

> **Практика:** не устанавливайте `Serializable` глобально — это снижает параллелизм и требует обработки `serialization_failure` в коде. Применяйте точечно к критичным транзакциям.

### 9.5. Как аналитику описывать требования к изоляции

В требованиях полезно фиксировать не название уровня, а **бизнес-инвариант**:

- «Отчёт должен строиться по состоянию данных на момент запуска» → `Repeatable Read`.
- «Нельзя допустить, чтобы два менеджера одновременно подтвердили один заказ» → `Serializable` или блокировка строки.
- «Допустимо, что пользователь увидит цену, изменившуюся между двумя запросами» → `Read Committed` (по умолчанию).

DBA переведёт инвариант в технический уровень. Аналитик проверяет, что компромисс понятен бизнесу.

> Подробнее о блокировках, которые возникают при разных уровнях изоляции, — в статье [Блокировки и конкурентный доступ](../../wiki/concepts/locks-concurrency.md).

---

## 10. Разбор вводного кейса

1. **Почему приложение не видит `promo_codes`?**  
   `GRANT ... ON ALL TABLES` затронул только существовавшие на момент выдачи таблицы. Новая таблица из миграции не получила прав. Решение — `ALTER DEFAULT PRIVILEGES` для роли-владельца схемы.
2. **Почему BI-роль получила доступ?**  
   Либо у роли был широкий грант на схему/все таблицы, либо владелец настроил default privileges слишком широко. Нужно проверить `\dp promo_codes`, `pg_default_acl` и `information_schema.role_table_grants`.
3. **Какие два механизма нужны для регионального доступа?**  
   `GRANT SELECT` на таблицу + RLS-политика `USING (region = current_setting('app.current_region', true))`. Без RLS `GRANT` даёт доступ ко всем строкам; без `GRANT` RLS не применяется.

---

## 11. Итоги лекции

После этой лекции студент умеет:

- **Объяснить иерархию привилегий** (`CONNECT` → `USAGE` → `SELECT`) и воспроизвести ошибку `permission denied for schema`.
- **Написать `GRANT`-скрипт** для ролевой модели из нескольких профилей с `ALTER DEFAULT PRIVILEGES` для будущих объектов.
- **Настроить поиск схем** через `search_path` и объяснить, почему смена `search_path` — потенциальная уязвимость.
- **Создать RLS-политику** с `USING`- и `WITH CHECK`-условием; проверить через `SET ROLE`.
- **Выбрать уровень изоляции транзакции** (`Read Committed` / `Repeatable Read` / `Serializable`) в зависимости от бизнес-требований.
- **Подготовить матрицу доступа** — документ, передаваемый DBA для реализации `GRANT`/`REVOKE`.

---

## Контрольные вопросы

1. Почему `GRANT SELECT ON TABLE` без `GRANT USAGE ON SCHEMA` не работает? Какое сообщение об ошибке увидит пользователь?
2. Чем `GRANT ... ON ALL TABLES IN SCHEMA` отличается от `ALTER DEFAULT PRIVILEGES`?
3. Почему `ALTER DEFAULT PRIVILEGES` нужно указывать `FOR ROLE`? Что будет, если объекты создаёт другая роль?
4. Чем `USING` отличается от `WITH CHECK` в RLS-политике?
5. Что произойдёт с таблицей, если включить RLS и не создать ни одной политики?
6. Почему `SELECT *` может сломаться при column-level привилегиях? Как это обойти?
7. В каком уровне изоляции возможна аномалия write skew и как её предотвратить?
8. Почему `Serializable` не ставят глобально по умолчанию?

---

## Ссылки

- Привилегии: https://www.postgresql.org/docs/current/ddl-priv.html
- `GRANT`: https://www.postgresql.org/docs/current/sql-grant.html
- `REVOKE`: https://www.postgresql.org/docs/current/sql-revoke.html
- `ALTER DEFAULT PRIVILEGES`: https://www.postgresql.org/docs/current/sql-alterdefaultprivileges.html
- Схемы: https://www.postgresql.org/docs/current/ddl-schemas.html
- Row Security Policies: https://www.postgresql.org/docs/current/ddl-rowsecurity.html
- Уровни изоляции: https://www.postgresql.org/docs/current/transaction-iso.html

**Wiki:**
- [Привилегии](../../wiki/concepts/privileges.md)
- [Уровни изоляции](../../wiki/concepts/transaction-isolation.md)
- [Безопасность](../../wiki/concepts/security.md)
- [Модели управления доступом](../../wiki/concepts/access-control-models.md)
- [Блокировки и конкурентный доступ](../../wiki/concepts/locks-concurrency.md)
- [Матрица доступа (шаблон)](../../wiki/artifacts/access-matrix.md)
