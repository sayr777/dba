-- Миграция V007: ADD NOT NULL безопасно (zero-downtime, 3 шага)

-- ШАГ 1: Добавить колонку nullable
ALTER TABLE orders
    ADD COLUMN confirmed_at TIMESTAMP;

-- ШАГ 2: Заполнить существующие данные
UPDATE orders
SET confirmed_at = order_date
WHERE confirmed_at IS NULL;

-- ШАГ 3: Установить NOT NULL
ALTER TABLE orders
    ALTER COLUMN confirmed_at SET NOT NULL;
