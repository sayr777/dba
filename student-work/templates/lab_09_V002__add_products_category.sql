-- Миграция V002: Добавить таблицу categories и связь с products

BEGIN;

-- 1. Создать таблицу categories
CREATE TABLE categories (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    created_at  TIMESTAMP DEFAULT NOW()
);

-- 2. Вставить начальные данные
INSERT INTO categories (name, description) VALUES
    ('Электроника', 'Электронные устройства и аксессуары'),
    ('Одежда', 'Одежда и обувь'),
    ('Книги', 'Книги и аудиокниги');

-- 3. Добавить column category_id в products
ALTER TABLE products
    ADD COLUMN category_id INT REFERENCES categories(id);

-- 4. Присвоить категории по умолчанию
UPDATE products SET category_id = 1 WHERE category_id IS NULL;

-- 5. Сделать NOT NULL
ALTER TABLE products ALTER COLUMN category_id SET NOT NULL;

COMMIT;
