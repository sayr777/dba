# План миграции V003 — Создание таблиц promo_codes

**Группа:** [Группа]  
**Студент:** [ФИО]  
**Дата:** [Дата]

## 1. Цель

Создать таблицу `promo_codes` для поддержки промокодов и связать её с таблицей `orders`.

## 2. Предусловия

- [ ] Бэкап БД перед миграцией
- [ ] Миграция V002 применена и проверена
- [ ] MR с миграцией одобрен DBA

## 3. Изменения и риски

| Изменение | Риск | Уровень риска | Mitigation |
|-----------|------|---------------|------------|
| CREATE TABLE promo_codes | Нет блокировок | Низкий | — |
| ALTER TABLE orders ADD promo_code_id INT | Шорт-lock на ALTER | Средний | Применять в не-пиковое время |
| ALTER TABLE orders ADD CONSTRAINT fk_promo | Проверка FK | Средний | Индекс на promo_codes(id) |
| INSERT INTO promo_codes (данные) | Нет блокировок | Низкий | — |

## 4. SQL-верификация после деплоя

```sql
-- Проверка существования таблицы
SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'promo_codes');

-- Проверка FK
SELECT conname FROM pg_constraint WHERE conname LIKE '%promo%';

-- Проверка данных
SELECT count(*) FROM promo_codes;

-- Проверка связи orders → promo_codes
SELECT count(*) FROM orders WHERE promo_code_id IS NOT NULL;
```

## 5. Стратегия отката при неудаче

1. Если миграция упала на шаге ALTER TABLE:
   - `ALTER TABLE orders DROP COLUMN promo_code_id;`
2. Если миграция упала на шаге FK:
   - `ALTER TABLE orders DROP CONSTRAINT fk_orders_promo_codes;`
3. После отката — исправить ошибку и запустить миграцию заново.

## 6. Checklist MR

- [ ] SQL-файл валиден (`flyway validate`)
- [ ] Есть обратный скрипт (rollback)
- [ ] Индексы добавлены
- [ ] Риск-анализ заполнен
- [ ] План верификации готов
- [ ] DBA одобрил MR
