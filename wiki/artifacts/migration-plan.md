# Migration Plan (план миграции схемы)

**Источник:** лаб. 09 — «Управление миграциями»  
**Кто создаёт:** системный аналитик / разработчик  
**Кому передаётся:** DBA + тимлид для ревью до открытия Merge Request

---

## Зачем этот документ

Миграция без плана — изменение вслепую. Migration Plan позволяет DBA понять риски **до** деплоя, а не во время него. Если что-то пойдёт не так, план содержит точные команды отката.

> **Запомнить:** Migration Plan открывается вместе с MR (Merge Request). Без утверждённого плана миграция не деплоится в production.

---

## Шаблон Migration Plan

```markdown
# Migration Plan: V003 — Добавление таблицы promo_codes

| Поле          | Значение                           |
|---------------|------------------------------------|
| Версия        | V003                               |
| Автор         | Иванова А.В.                       |
| Дата деплоя   | 2024-11-15 (плановая)              |
| Тип           | DDL                                |
| Файл          | V003__create_promo_codes.sql       |

---

## Изменения

| Объект                  | Операция     | Риск    | Комментарий                                       |
|-------------------------|--------------|---------|---------------------------------------------------|
| promo_codes             | CREATE TABLE | Низкий  | Новая таблица, нет зависимостей                   |
| idx_promo_codes_code    | CREATE INDEX | Низкий  | CONCURRENTLY — без блокировки                     |
| orders.promo_code_id    | ADD COLUMN   | Низкий  | NULL-able FK — без блокировки                     |

---

## SQL-изменения (суть, без полного кода)

```sql
-- 1. Создать таблицу promo_codes
CREATE TABLE promo_codes (
    id               SERIAL PRIMARY KEY,
    code             TEXT NOT NULL UNIQUE,
    discount_percent NUMERIC(5,2) NOT NULL CHECK (discount_percent > 0),
    valid_from       DATE,
    valid_to         DATE,
    created_at       TIMESTAMPTZ DEFAULT now()
);

-- 2. Индекс на code без блокировки (уже UNIQUE, но явный для читаемости)
CREATE INDEX CONCURRENTLY idx_promo_codes_code ON promo_codes(code);

-- 3. Добавить FK в orders (NULL-able — без блокировки таблицы)
ALTER TABLE orders ADD COLUMN promo_code_id INT REFERENCES promo_codes(id);
```

---

## Откат (Rollback)

```sql
-- Если что-то пошло не так:
ALTER TABLE orders DROP COLUMN IF EXISTS promo_code_id;
DROP INDEX IF EXISTS idx_promo_codes_code;
DROP TABLE IF EXISTS promo_codes;
```

> Откат выполняет DBA. Аналитик уведомляет команду и фиксирует время.

---

## Проверка после деплоя

```sql
-- 1. Таблица создана:
SELECT count(*) FROM information_schema.tables
WHERE table_name = 'promo_codes';  -- ожидается: 1

-- 2. Индекс создан:
SELECT indexname FROM pg_indexes WHERE tablename = 'promo_codes';
-- ожидается: idx_promo_codes_code

-- 3. Колонка promo_code_id добавлена в orders:
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'orders' AND column_name = 'promo_code_id';
-- ожидается: data_type=integer, is_nullable=YES

-- 4. Flyway зафиксировал успех:
SELECT version, description, success FROM flyway_schema_history ORDER BY installed_rank DESC LIMIT 3;
-- ожидается: success=true для V003
```

---

## MR-чек-лист (перед открытием)

- [ ] Имя файла: `V003__create_promo_codes.sql` (двойное подчёркивание!)
- [ ] Идемпотентность: `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`
- [ ] `flyway validate` прошёл без ошибок
- [ ] `cleanDisabled = true` в flyway.toml (нет случайного DROP в prod)
- [ ] Rollback-скрипт написан и проверен на dev
- [ ] DBA сделал ревью плана
```

---

## Правило именования файлов Flyway

```
V{version}__{description}.sql
  ↑          ↑↑
  Версия     Два подчёркивания (обязательно!)
```

| Правильно | Неправильно |
|-----------|-------------|
| `V003__create_promo_codes.sql` | `V003_create_promo_codes.sql` (одно подчёркивание) |
| `V003__create_promo_codes.sql` | `v003__create_promo_codes.sql` (строчная V) |
| `V003__create_promo_codes.sql` | `V3__create_promo_codes.sql` (без ведущих нулей — нестабильный порядок) |

> **Ловушка:** одно подчёркивание — Flyway воспримет как разделитель внутри версии: `V0` + `03__create_promo_codes`. Это ошибка.

---

## Команды Flyway

```bash
flyway info      # показать состояние всех миграций
flyway validate  # проверить, что файлы не изменились после применения
flyway migrate   # применить pending-миграции
flyway repair    # сбросить FAILED-статус после исправления
```

---

> **Связанные страницы:** [[tools/flyway]], [[procedures/migration-workflow]], [[artifacts/deployment-runbook]], [[procedures/zero-downtime]]
