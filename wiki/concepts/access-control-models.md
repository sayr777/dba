# Модели управления доступом

Управление доступом — механизм, определяющий, **кто** может выполнять **какие** действия над **какими** объектами. В практике работы с БД системный аналитик встречает несколько принципиально разных моделей.

---

## 1. Обзор и сравнение

| Модель  | Полное название                  | Ключевой принцип                          | PostgreSQL-реализация            |
|---------|----------------------------------|-------------------------------------------|----------------------------------|
| DAC     | Discretionary Access Control     | Владелец объекта сам раздаёт права        | `GRANT` / `REVOKE`               |
| RBAC    | Role-Based Access Control        | Права привязаны к ролям, не к людям       | Система ролей + `GRANT role TO`  |
| ABAC    | Attribute-Based Access Control   | Права зависят от атрибутов субъекта/объекта | Row Level Security (RLS)       |
| MAC     | Mandatory Access Control         | Централизованные метки безопасности       | SE-PostgreSQL (расширение ОС)    |
| ReBAC   | Relationship-Based Access Control| Права через граф отношений                | Нет встроенной поддержки         |

---

## 2. DAC — Discretionary Access Control

Самая распространённая модель в реляционных СУБД. Владелец объекта сам решает, кому давать доступ.

В PostgreSQL каждая таблица, схема и функция имеют **владельца** (роль-создатель). Владелец выдаёт права через `GRANT` и отзывает через `REVOKE`:

```sql
-- Владелец таблицы выдаёт право
GRANT SELECT ON orders TO analyst_ivanova;

-- Передача права другим (WITH GRANT OPTION)
GRANT SELECT ON reports TO analyst_ivanova WITH GRANT OPTION;
-- Теперь analyst_ivanova сама может выдавать SELECT на reports

-- Отзыв с каскадом (если право было передано дальше)
REVOKE SELECT ON reports FROM analyst_ivanova CASCADE;
```

**Иерархия DAC в PostgreSQL** — доступ к объекту нижнего уровня требует прав на всех уровнях выше:

```
База данных  →  CONNECT
  Схема      →  USAGE
    Таблица  →  SELECT / INSERT / UPDATE / DELETE / TRUNCATE
      Колонка →  SELECT / INSERT / UPDATE (column-level)
```

**Слабость DAC:** владелец может выдать кому угодно право на `WITH GRANT OPTION`, создавая непрозрачную цепочку прав. Для аудита нужно отслеживать всю цепочку через `information_schema.role_table_grants`.

> **Источники:** [[lectures/lec_03]], [[lectures/lec_04]]

---

## 3. RBAC — Role-Based Access Control

Стандарт NIST RBAC (ANSI/INCITS 359-2004): права назначаются **ролям**, пользователи получают права через членство в ролях. Это устраняет проблему DAC, где права прописаны напрямую на каждого пользователя.

**Ключевая идея в PostgreSQL:** роли могут содержать другие роли — так строится иерархия профилей (lec_03, раздел 3):

```sql
-- 1. Профили прав (NOLOGIN — не могут подключаться сами по себе)
CREATE ROLE app_readonly  NOLOGIN;
CREATE ROLE app_readwrite NOLOGIN;

-- 2. Привязываем привилегии к профилям
GRANT USAGE  ON SCHEMA public                        TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public          TO app_readonly;
-- Для таблиц, созданных в будущем:
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_readonly;

GRANT USAGE  ON SCHEMA public                        TO app_readwrite;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_readwrite;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_readwrite;

-- 3. Пользователи получают права через членство в профиле
GRANT app_readonly TO analyst_ivanova;
GRANT app_readonly TO analyst_petrov;
GRANT app_readwrite TO app_user;
```

```
app_readonly (NOLOGIN)        app_readwrite (NOLOGIN)
     ├── analyst_ivanova            └── app_user (LOGIN)
     └── analyst_petrov
```

**Атрибут INHERIT** (по умолчанию включён) — пользователь автоматически наследует все привилегии ролей, в которых состоит. Если `NOINHERIT` — для активации прав нужен явный `SET ROLE`.

**Четыре уровня RBAC по NIST:**

| Уровень       | Что добавляет                               | PostgreSQL |
|---------------|---------------------------------------------|------------|
| RBAC0 (base)  | Роли, назначение пользователей              | ✓ GRANT role TO user |
| RBAC1         | Иерархия ролей (наследование)               | ✓ INHERIT  |
| RBAC2         | Ограничения (взаимоисключающие роли, SoD)   | Частично — через CHECK в приложении |
| RBAC3         | RBAC1 + RBAC2                               | Частично   |

**Принцип минимальных привилегий (PoLP)** — каждая роль получает только права, необходимые для задачи. Нарушение: выдача `SUPERUSER` аналитику «для удобства» — суперпользователь обходит все политики, включая RLS.

**Шаблон типовых профилей курса:**

| Профиль           | Аудитория                       | Привилегии                               |
|-------------------|---------------------------------|------------------------------------------|
| `app_readonly`    | Аналитики, BI-инструменты       | `SELECT` на все таблицы схемы            |
| `app_readwrite`   | Backend-приложение              | `SELECT, INSERT, UPDATE, DELETE`         |
| `app_admin`       | Административные скрипты        | `app_readwrite` + `TRUNCATE`, DDL        |
| `migration_runner`| CI/CD (Flyway)                  | Расширенные права только при деплое      |

> **Источники:** [[lectures/lec_03]], [[lectures/lec_04]]

---

## 4. ABAC — Attribute-Based Access Control

В ABAC решение о доступе принимается на основе **атрибутов**: кто запрашивает (`current_user`, роль), что запрашивается (значения строки/колонки), при каких условиях (контекст сеанса).

В PostgreSQL это реализовано через **Row Level Security (RLS)** — политики, фильтрующие строки автоматически при каждом запросе (lec_04, раздел 6):

```sql
-- Включить RLS на таблице
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;  -- действует и на владельца

-- Политика: пользователь видит только свои заказы
-- Атрибут субъекта: current_user → id в таблице users
CREATE POLICY user_sees_own_orders ON orders
  FOR SELECT
  TO app_readonly
  USING (user_id = (SELECT id FROM users WHERE username = current_user));

-- Политика: менеджер видит заказы своего региона
-- Атрибут контекста: app.current_region (передаётся через SET)
CREATE POLICY manager_regional ON orders
  FOR ALL
  TO app_readwrite
  USING       (region = current_setting('app.current_region', true))
  WITH CHECK  (region = current_setting('app.current_region', true));
```

**USING** применяется к `SELECT`, `UPDATE`, `DELETE` (что читать/изменять).  
**WITH CHECK** применяется к `INSERT`, `UPDATE` (что записывать).

**RLS и RBAC — разные уровни защиты:**

```
RBAC (роли) → "app_readonly может читать таблицу orders"
                         ↓
ABAC/RLS    → "но только строки, где user_id = текущий пользователь"
```

**Когда применять RLS:**

| Сценарий                                     | RLS?      |
|----------------------------------------------|-----------|
| Мультитенантность (изоляция по tenant_id)    | Да        |
| Персональные данные — каждый видит только своё | Да      |
| Региональное разграничение                   | Да        |
| Простое read/write по таблицам               | Нет — достаточно GRANT |
| Более 5 политик на таблицу                   | Осторожно — влияет на планировщик |

**Column-level security** — частный случай ABAC на уровне столбцов:

```sql
-- Аналитик видит имя и email, но не salary
GRANT SELECT (id, name, email) ON TABLE employees TO analyst_ivanova;
-- Альтернатива: VIEW с нужными колонками (проще в сопровождении)
```

> **Источники:** [[lectures/lec_04]], [[labs/lab_02]]

---

## 5. MAC — Mandatory Access Control

В MAC права не определяются владельцем объекта — они задаются **централизованной политикой безопасности** (администратором) через метки секретности (confidentiality labels): TOP SECRET > SECRET > CONFIDENTIAL > UNCLASSIFIED.

В PostgreSQL MAC реализуется через **SE-PostgreSQL** (расширение SELinux):
- Каждому объекту присваивается метка безопасности.
- Пользователь может получить доступ только если его метка >= метки объекта.
- Даже суперпользователь не может нарушить политику MAC.

MAC используется в государственных и военных системах (обработка гостайны). В коммерческих приложениях практически не применяется — слишком жёсткая модель.

**Связь с 152-ФЗ:** закон не требует MAC, но требует разграничения доступа (ст. 19) — это реализуется комбинацией DAC + RBAC + ABAC.

> **Источники:** [[lectures/lec_11]] (pgAudit, ИБ, 152-ФЗ)

---

## 6. ReBAC — Relationship-Based Access Control

В ReBAC права определяются **отношениями между объектами** в графе. Классический пример: Google Drive — если пользователь имеет доступ к папке, он автоматически имеет доступ ко всем вложенным файлам.

Архитектура **Google Zanzibar** (2019) — публичное описание ReBAC системы Google. Современные реализации: **SpiceDB**, **Ory Keto**, **OpenFGA**.

```
# Пример Zanzibar-нотации
doc:readme#viewer@user:alice
folder:engineering#member@user:alice
doc:readme#viewer@folder:engineering#member  # все члены папки — зрители документа
```

В PostgreSQL нет встроенной поддержки ReBAC. Реализуется через рекурсивные CTE или внешний сервис авторизации:

```sql
-- Псевдокод: рекурсивный обход графа отношений
-- :current_user_id — параметр приложения (не встроенная функция PostgreSQL)
WITH RECURSIVE accessible_docs AS (
  SELECT resource_id FROM permissions WHERE user_id = :current_user_id
  UNION
  SELECT r.id FROM resources r
  JOIN accessible_docs ad ON r.parent_id = ad.resource_id
)
SELECT * FROM documents WHERE id IN (SELECT resource_id FROM accessible_docs);
```

ReBAC актуален для систем с иерархическими структурами данных (файловые системы, оргструктуры, проектные инструменты).

---

## 7. Выбор модели для проекта

Модели не исключают друг друга — в реальных системах они комбинируются:

```
Слой 1: DAC   — GRANT/REVOKE на уровне объектов
Слой 2: RBAC  — профили ролей; пользователи получают права через членство
Слой 3: ABAC  — RLS для фильтрации строк по атрибутам контекста
```

**Алгоритм выбора:**

```
Нужна изоляция строк по условию?
  → Да: RBAC + ABAC (RLS)
  → Нет: RBAC

Нужна централизованная политика безопасности уровня ОС?
  → Да: MAC (SE-PostgreSQL) — только для госсистем
  → Нет: DAC + RBAC

Нужна навигация по графу прав (вложенные папки, оргструктура)?
  → Да: ReBAC (внешний сервис) + PostgreSQL как хранилище
  → Нет: RBAC
```

**Типичная комбинация для eshop:**

| Уровень   | Механизм              | Пример                                                    |
|-----------|-----------------------|-----------------------------------------------------------|
| DAC       | GRANT/REVOKE          | `GRANT SELECT ON orders TO app_readonly`                  |
| RBAC      | Профили ролей         | `GRANT app_readonly TO analyst_ivanova`                   |
| ABAC      | RLS                   | Менеджер видит заказы только своего региона               |

---

## 8. Матрица доступа — документ аналитика

Матрица доступа — это рабочий документ системного аналитика, передаваемый DBA для реализации `GRANT`/`REVOKE`. Объединяет решения по всем моделям (lec_04, раздел 7):

```
[ ] Роли и профили описаны (шаблон lec_03)
[ ] Матрица GRANT заполнена (DAC + RBAC)
[ ] USAGE на схемы указан отдельно
[ ] ALTER DEFAULT PRIVILEGES — нужен ли для будущих объектов
[ ] RLS — на каких таблицах, логика политик (ABAC)
[ ] Column-level привилегии перечислены
[ ] Согласовано с ИБ
```

---

> **Источники:** [[lectures/lec_03]], [[lectures/lec_04]], [[labs/lab_02]]  
> **Связанные страницы:** [[concepts/security]], [[procedures/migration-workflow]]
