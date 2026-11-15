-- Миграция V006: Фикс миграции V005 (некорректный manager_id)

BEGIN;

-- 1. Исправить некорректные значения
UPDATE orders
SET manager_id = 1
WHERE manager_id IS NULL OR manager_id < 0;

-- 2. Убедиться, что FK ссылается на существующих менеджеров
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM employees WHERE employee_id = 1) THEN
        RAISE EXCEPTION 'Manager employee_id=1 not found';
    END IF;
END $$;

COMMIT;
