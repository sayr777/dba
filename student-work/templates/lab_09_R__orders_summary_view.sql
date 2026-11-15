-- Повторяемая миграция (R): View orders_summary

CREATE OR REPLACE VIEW orders_summary AS
SELECT
    o.id,
    o.order_date,
    c.first_name || ' ' || c.last_name AS customer,
    COUNT(oi.id) AS item_count,
    SUM(oi.quantity * oi.unit_price) AS total_amount,
    p.code AS promo_code
FROM orders o
JOIN customers c ON c.id = o.customer_id
LEFT JOIN order_items oi ON oi.order_id = o.id
LEFT JOIN promo_codes p ON p.id = o.promo_code_id
GROUP BY o.id, o.order_date, c.first_name, c.last_name, p.code;
