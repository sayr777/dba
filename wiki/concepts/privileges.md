# Привилегии (Privileges)

Привилегии PostgreSQL — это права роли на конкретные объекты (базу, схему, таблицу, колонку, последовательность, функцию); они организованы в иерархию и дополняются привилегиями по умолчанию и Row-Level Security.

---

## 1. Иерархия привилегий

```text
База данных      CONNECT, CREATE, TEMP
  └── Схема      USAGE, CREATE
        ├── Таблица        SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
        ├── Колонка        SELECT, INSERT, UPDATE, REFERENCES
        ├── Последовательность  USAGE, SELECT, UPDATE
        └── Функция        EXECUTE
```

Чтобы прочитать таблицу, роли нужны **все** уровни: `CONNECT` на базу, `USAGE` на схему, `SELECT` на таблицу. Отсутствие любого уровня даёт `permission denied`, даже если остальные выданы.

---

## 2. GRANT и REVOKE

```sql
-- База и схема
GRANT CONNECT ON DATABASE eshop TO app_readonly;
GRANT USAGE   ON SCHEMA public TO app_readonly;

-- Существующие таблицы
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_readonly;

-- Последовательности (нужны для INSERT с SERIAL/IDENTITY)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_readwrite;

-- Отзыв
REVOKE INSERT ON orders FROM app_readonly;
REVOKE ALL PRIVILEGES ON orders FROM app_readonly;
```

### WITH GRANT OPTION

Позволяет получателю передавать привилегию дальше. Усложняет аудит: цепочку прав становится трудно отследить. В большинстве команд права выдаёт только DBA.

---

## 3. Привилегии по умолчанию

`GRANT ... ON ALL TABLES` действует только на **существующие** объекты. Для будущих таблиц нужно:

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE schema_owner IN SCHEMA public
  GRANT SELECT ON TABLES TO app_readonly;

ALTER DEFAULT PRIVILEGES FOR ROLE schema_owner IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO app_readwrite;
```

> **Ключевая ловушка.** `FOR ROLE` привязывает правило к роли-создателю. Если миграции создаёт `migration_runner`, а правило задано для `schema_owner`, новая таблица не получит прав.

---

## 4. Владение и привилегии

Владелец объекта может всё: `ALTER`, `DROP`, `GRANT`. Поэтому «кому принадлежит таблица» важнее, чем кажется.

```sql
SELECT schemaname, tablename, tableowner
FROM   pg_tables
WHERE  schemaname = 'public';
```

При удалении роли-владельца:

```sql
REASSIGN OWNED BY old_role TO new_owner;
DROP OWNED BY old_role;
DROP ROLE old_role;
```

---

## 5. Колоночные привилегии

```sql
GRANT SELECT (id, name, email) ON employees TO analyst_ivanova;
```

Ограничение: `SELECT *` попытается прочитать запрещённые колонки и упадёт. Для BI-инструментов лучше создавать `VIEW` с явным списком колонок.

---

## 6. RLS и привилегии

RLS не заменяет `GRANT`: сначала роль должна иметь `SELECT` на таблицу, затем применяются политики. Без `GRANT` до RLS дело не доходит.

```sql
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY own_orders ON orders
  FOR SELECT TO app_readonly
  USING (customer_id = current_setting('app.customer_id', true)::int);
```

---

## 7. Проверка

```sql
-- Табличные привилегии
SELECT grantee, table_schema, table_name, privilege_type
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public';

-- Схемы
\dn+

-- Таблица
\dp orders

-- Default privileges
SELECT * FROM pg_default_acl;
```

---

## 8. См. также

- [Безопасность](security.md) — аутентификация, аудит, TLS
- [Модели управления доступом](access-control-models.md) — RBAC, ABAC, RLS
- [Матрица доступа](../artifacts/access-matrix.md) — шаблон для DBA
- [Схема eshop](../course/eshop-schema.md) — роли и таблицы проекта

---

> **Источники:** [[lec_03]], [[lec_04]], [[lab_02]]
