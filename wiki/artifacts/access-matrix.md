# Матрица доступа и требования к ролям

**Источник:** лаб. 02 — «Управление доступом»  
**Кто создаёт:** системный аналитик  
**Кому передаётся:** DBA (для выполнения GRANT/REVOKE и настройки pg_hba.conf)

---

## Зачем этот документ

DBA не знает, какой доступ нужен приложению — он знает только SQL. Аналитик знает бизнес-требования, но не знает PostgreSQL. Матрица доступа — точка передачи требований между ролями.

> **Запомнить:** матрица создаётся **до** того, как DBA начинает выдавать привилегии. Без матрицы легко выдать лишнее (нарушение принципа наименьших привилегий).

---

## Шаблон: требования к ролям

Заполняется аналитиком, передаётся DBA.

```markdown
## Требования к ролям — eshop

| Роль            | Логин | Кому соответствует | Привилегии                                    | RLS |
|-----------------|-------|--------------------|-----------------------------------------------|-----|
| eshop_readonly  | нет   | читающие клиенты   | SELECT на customers, orders, products         | да  |
| eshop_app       | нет   | backend-сервис     | SELECT, INSERT, UPDATE, DELETE на всех таблицах | да |
| analyst_ivanova | да    | конкретный юзер    | SELECT на orders, products (без customers)    | нет |
| app_backend     | да    | сервисный аккаунт  | MEMBER OF eshop_app                           | -   |

### Требования к RLS
- customers: доступ ограничен по region = current_setting('app.current_region')
- orders: app-пользователь видит только свои заказы
```

---

## Шаблон: матрица привилегий (заполняется после настройки)

Таблица проверяется командой `\dp <table>` в psql или через Information Schema.

| Роль \ Объект   | customers | orders | order_items | products |
|-----------------|-----------|--------|-------------|----------|
| eshop_readonly  | S         | S      | S           | S        |
| eshop_app       | SIUD      | SIUD   | SIUD        | SIUD     |
| analyst_ivanova | —         | S      | S           | S        |

> S = SELECT, I = INSERT, U = UPDATE, D = DELETE

---

## Критические паттерны для запоминания

### 1. GRANT + ALTER DEFAULT PRIVILEGES — нужны оба

```sql
-- Даёт доступ к существующим таблицам:
GRANT SELECT ON ALL TABLES IN SCHEMA public TO eshop_readonly;

-- Даёт доступ к будущим таблицам (без этого новые таблицы будут недоступны!):
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO eshop_readonly;
```

> **Ловушка:** если выполнить только `GRANT ON ALL TABLES`, то после следующей миграции (новая таблица) роль потеряет доступ к ней. Нужны **оба** оператора.

### 2. RLS: ENABLE + CREATE POLICY — нужны оба

```sql
-- Включает RLS (без этого политики не работают):
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

-- Создаёт политику:
CREATE POLICY customers_by_region
    ON customers
    FOR SELECT
    TO eshop_readonly
    USING (region = current_setting('app.current_region', true));
```

> **Ловушка:** `CREATE POLICY` без `ENABLE ROW LEVEL SECURITY` — политика создана, но не применяется. Owner таблицы обходит RLS по умолчанию.

### 3. Проверка привилегий

```sql
-- Просмотр привилегий на таблицу:
\dp customers

-- Через SQL:
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_name = 'customers';

-- Проверить RLS-политики:
SELECT * FROM pg_policies WHERE tablename = 'customers';
```

---

## Связь с концепциями

- Реализуемая модель: **RBAC** (role-based) + **RLS** как элемент ABAC — см. [[concepts/access-control-models]]
- DBA выполняет GRANT, аналитик задаёт требования — разграничение ответственности: [[roles/dba-vs-sa]]
- Роли eshop: [[course/eshop-schema]]
