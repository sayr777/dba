# Лекция 4. Привилегии, схемы, разграничение доступа

**Неделя:** 4

---

## Цель лекции

По итогам лекции студент:

- знает иерархию привилегий PostgreSQL — от базы данных до колонки;
- умеет применять `GRANT`/`REVOKE` и настраивать привилегии по умолчанию;
- понимает роль схем в изоляции объектов и управлении `search_path`;
- знает принцип Row-Level Security и когда его применять;
- умеет подготовить матрицу доступа для передачи DBA.

---

## 1. Иерархия привилегий PostgreSQL

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

---

## 2. GRANT и REVOKE

### 2.1. Синтаксис GRANT

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

### 2.2. WITH GRANT OPTION

Гранти может передавать привилегию другим ролям:

```sql
GRANT SELECT ON TABLE reports TO analyst_ivanova WITH GRANT OPTION;
-- analyst_ivanova теперь может сама выдавать SELECT на reports
```

> Использовать осторожно: усложняет аудит цепочки прав.

### 2.3. REVOKE

```sql
-- Отозвать конкретную привилегию
REVOKE INSERT ON TABLE orders FROM app_readonly;

-- Отозвать все привилегии
REVOKE ALL PRIVILEGES ON TABLE orders FROM app_readonly;

-- Каскадный отзыв (если привилегия была передана дальше через GRANT OPTION)
REVOKE SELECT ON TABLE reports FROM analyst_ivanova CASCADE;
```

### 2.4. Просмотр привилегий

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

---

## 3. Привилегии по умолчанию (ALTER DEFAULT PRIVILEGES)

`GRANT ON ALL TABLES` выдаёт права только на **уже существующие** объекты. Новые таблицы, созданные позже, привилегий не получают.

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

> **Важно:** `ALTER DEFAULT PRIVILEGES` привязана к роли-создателю (`FOR ROLE`). Если объекты создаёт другой пользователь — нужна отдельная настройка для него. При описании требований к доступу укажите DBA: нужны ли права на будущие объекты и кто их создаёт.

---

## 4. Схемы: организация и изоляция объектов

### 4.1. Что такое схема

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

### 4.2. search_path

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

### 4.3. Схема public в PostgreSQL 14+

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

### 4.4. Паттерн изоляции по схемам

| Схема        | Назначение                                      | Доступ                                    |
|--------------|-------------------------------------------------|-------------------------------------------|
| `app`        | Рабочие таблицы приложения                      | `USAGE` — app_readonly, app_readwrite     |
| `reporting`  | Материализованные представления, агрегаты        | `USAGE` — только app_readonly             |
| `internal`   | Вспомогательные таблицы, не видны пользователям | Только DBA / migration_runner             |
| `audit`      | Аудит-лог, append-only                          | `SELECT` — DBA; `INSERT` — триггеры       |

---

## 5. Привилегии на уровне колонок

PostgreSQL поддерживает управление доступом на уровне отдельных колонок:

```sql
-- Аналитик видит имя и email, но не salary
GRANT SELECT (id, name, email) ON TABLE employees TO analyst_ivanova;

-- Просмотр column-level привилегий
SELECT column_name, privilege_type, grantee
FROM   information_schema.column_privileges
WHERE  table_name = 'employees'
ORDER  BY grantee, column_name;
```

> **Альтернатива:** создать представление (`VIEW`) с нужными колонками и выдать права на него. Это проще в сопровождении: `GRANT SELECT ON VIEW employees_public TO app_readonly;`

---

## 6. Row-Level Security (RLS)

RLS позволяет ограничить, **какие строки** видит пользователь, а не только к какой таблице у него есть доступ.

### 6.1. Включение RLS

```sql
-- Включить RLS на таблице
-- По умолчанию запрещает все строки для не-суперпользователей (без политик = пустой результат)
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- Распространить политики и на владельца таблицы (суперпользователь всё равно обходит)
ALTER TABLE orders FORCE ROW LEVEL SECURITY;
```

### 6.2. Создание политик

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

### 6.3. Управление политиками

```sql
-- Список политик на таблице
SELECT polname, polcmd, polroles, polqual
FROM   pg_policies
WHERE  tablename = 'orders';

-- Изменить политику
ALTER POLICY user_sees_own_orders ON orders USING (owner_id = current_setting('app.user_id')::int);

-- Удалить политику
DROP POLICY user_sees_own_orders ON orders;

-- Временно отключить RLS (только суперпользователь)
ALTER TABLE orders DISABLE ROW LEVEL SECURITY;
```

### 6.4. Когда применять RLS

| Сценарий                                             | RLS?      |
|------------------------------------------------------|-----------|
| Мультитенантность (данные изолированы по tenant_id)  | Да        |
| Персональные данные — каждый видит только свои       | Да        |
| Региональное разграничение данных                    | Да        |
| Простое разграничение read/write по таблицам         | Нет — достаточно `GRANT` |
| Более 5 политик на одну таблицу                      | Осторожно — влияет на производительность планировщика |

> RLS применяется после аутентификации и стандартных проверок привилегий. Если у роли нет `SELECT` на таблицу — до политик дело не дойдёт.

---

## 7. Матрица доступа — инструмент аналитика

Прежде чем передавать задачу DBA, аналитик готовит **матрицу доступа**. Это документ, по которому DBA выполняет `GRANT`/`REVOKE` и настраивает `pg_hba.conf`.

### 7.1. Шаблон матрицы

| Роль / профиль    | БД          | Схема      | Объект             | SELECT | INSERT | UPDATE | DELETE | TRUNCATE | EXECUTE | Примечания                  |
|-------------------|-------------|------------|--------------------|:------:|:------:|:------:|:------:|:--------:|:-------:|-----------------------------|
| `app_readonly`    | myapp_prod  | public     | все таблицы        | ✓      |        |        |        |          |         | + USAGE на схему            |
| `app_readwrite`   | myapp_prod  | public     | все таблицы        | ✓      | ✓      | ✓      | ✓      |          |         | + USAGE на схему            |
| `app_readwrite`   | myapp_prod  | public     | все последовательности | ✓  |        | ✓      |        |          |         | Нужно для INSERT с SERIAL   |
| `analyst_ivanova` | myapp_prod  | reporting  | все таблицы        | ✓      |        |        |        |          |         | + USAGE на схему reporting  |
| `migration_runner`| myapp_prod  | public     | все объекты        | ✓      | ✓      | ✓      | ✓      | ✓        | ✓       | Для Flyway migrate          |

### 7.2. Чек-лист передачи DBA

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

## 8. Уровни изоляции транзакций

ACID-гарантия Isolation (изоляция) определяет, насколько параллельные транзакции «видят» изменения друг друга. В PostgreSQL 4 уровня:

### 8.1. Таблица уровней и аномалий

| Уровень изоляции   | Грязное чтение | Неповторяемое чтение | Фантомное чтение | Аномалия сериализации |
|--------------------|:--------------:|:--------------------:|:----------------:|:---------------------:|
| Read Uncommitted   | Невозможно¹    | Возможно             | Возможно         | Возможно              |
| **Read Committed** | Невозможно     | Возможно             | Возможно         | Возможно              |
| Repeatable Read    | Невозможно     | Невозможно           | Невозможно²      | Возможно              |
| Serializable       | Невозможно     | Невозможно           | Невозможно       | Невозможно            |

¹ PostgreSQL не реализует грязное чтение даже на Read Uncommitted — используется Read Committed.  
² PostgreSQL устранил фантомы на Repeatable Read через MVCC (в стандарте SQL они были разрешены).

### 8.2. Уровни по умолчанию и как их применять

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

### 8.3. Примеры аномалий

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

**Решение:** поднять до `REPEATABLE READ` — тогда транзакция 1 увидит 1000 в обоих SELECT.

#### Аномалия сериализации (write skew)

```sql
-- Два врача одновременно хотят уйти на перерыв.
-- Правило: хотя бы один врач должен быть на смене.
-- При REPEATABLE READ оба видят «1 врач доступен» → оба уходят → правило нарушено.
-- При SERIALIZABLE одна из транзакций откатится с ошибкой serialization failure.
```

### 8.4. Когда какой уровень применять

| Сценарий                                          | Уровень изоляции      |
|---------------------------------------------------|-----------------------|
| Обычные OLTP-операции (INSERT/UPDATE/SELECT)      | Read Committed        |
| Аналитический SELECT по «срезу» данных на момент T | Repeatable Read      |
| Финансовые операции с бизнес-инвариантами         | Serializable          |

> **Практика:** не устанавливайте Serializable глобально — это снижает параллелизм и требует обработки `serialization_failure` в коде. Применяйте точечно к критичным транзакциям.

---

## 9. Итоги лекции

После этой лекции студент умеет:

- **Объяснить иерархию привилегий** (`CONNECT` → `USAGE` → `SELECT`) и воспроизвести ошибку «permission denied for schema».
- **Написать GRANT-скрипт** для ролевой модели из нескольких профилей с `ALTER DEFAULT PRIVILEGES` для будущих объектов.
- **Настроить поиск схем** через `search_path` и объяснить, почему смена `search_path` — потенциальная уязвимость.
- **Создать RLS-политику** с `USING`- и `WITH CHECK`-условием; проверить через `SET ROLE`.
- **Выбрать уровень изоляции транзакции** (`Read Committed` / `Repeatable Read` / `Serializable`) в зависимости от бизнес-требований.
- **Подготовить матрицу доступа** — документ, передаваемый DBA для реализации `GRANT`/`REVOKE`.

---

## Ссылки

- Привилегии: https://www.postgresql.org/docs/current/ddl-priv.html
- GRANT: https://www.postgresql.org/docs/current/sql-grant.html
- REVOKE: https://www.postgresql.org/docs/current/sql-revoke.html
- ALTER DEFAULT PRIVILEGES: https://www.postgresql.org/docs/current/sql-alterdefaultprivileges.html
- Схемы: https://www.postgresql.org/docs/current/ddl-schemas.html
- Row Security Policies: https://www.postgresql.org/docs/current/ddl-rowsecurity.html
