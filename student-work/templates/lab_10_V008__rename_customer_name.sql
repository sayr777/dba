-- Миграция V008: RENAME COLUMN безопасно (zero-downtime, 5 шагов)

-- ШАГ 1: Добавить новую колонку
ALTER TABLE customers
    ADD COLUMN full_name VARCHAR(200);

-- ШАГ 2: Скопировать данные
UPDATE customers
SET full_name = first_name || ' ' || last_name;

-- ШАГ 3: Установить NOT NULL
ALTER TABLE customers
    ALTER COLUMN full_name SET NOT NULL;

-- ШАГ 4: Удалить старую колонку
ALTER TABLE customers
    DROP COLUMN first_name;

ALTER TABLE customers
    DROP COLUMN last_name;

-- ШАГ 5: Переименовать новую в целевую
ALTER TABLE customers
    RENAME COLUMN full_name TO name;
