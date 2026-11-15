-- Миграция V003: Создать таблицу promo_codes

BEGIN;

-- 1. Создать таблицу promo_codes
CREATE TABLE promo_codes (
    id          SERIAL PRIMARY KEY,
    code        VARCHAR(50) NOT NULL UNIQUE,
    discount    DECIMAL(5,2) NOT NULL CHECK (discount >= 0 AND discount <= 100),
    valid_from  TIMESTAMP NOT NULL,
    valid_to    TIMESTAMP NOT NULL,
    max_uses    INT DEFAULT NULL,  -- NULL = без ограничений
    created_at  TIMESTAMP DEFAULT NOW()
);

-- 2. Добавить promo_code_id в orders
ALTER TABLE orders
    ADD COLUMN promo_code_id INT REFERENCES promo_codes(id);

-- 3. Создать индекс для быстрого поиска
CREATE INDEX idx_orders_promo_code_id ON orders(promo_code_id);

-- 4. Вставить тестовые промокоды
INSERT INTO promo_codes (code, discount, valid_from, valid_to, max_uses) VALUES
    ('WELCOME10', 10.00, '2024-01-01', '2025-12-31', 1000),
    ('SUMMER20', 20.00, '2024-06-01', '2024-08-31', 500),
    ('VIP30', 30.00, '2024-01-01', '2024-12-31', 100);

COMMIT;
