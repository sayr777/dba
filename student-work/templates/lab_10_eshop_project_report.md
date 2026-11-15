# Итоговый отчёт проекта eshop

**Группа:** [Группа]  
**Студент:** [ФИО]  
**Дата:** [Дата]

## 1. Описание БД

**База данных:** eshop  
**СУБД:** PostgreSQL [версия]

### ERD

[Вставить ERD-диаграмму из DBeaver или Mermaid]

### Таблицы

| Таблица | Строк | Описание |
|---------|-------|----------|
| customers | [число] | Клиенты |
| products | [число] | Товары |
| orders | [число] | Заказы |
| order_items | [число] | Позиции заказов |
| categories | [число] | Категории товаров |
| promo_codes | [число] | Промокоды |

## 2. Ролевая модель

| Роль | Тип | Привилегии |
|------|-----|------------|
| eshop_readonly | NOLOGIN | SELECT на все таблицы |
| eshop_app | NOLOGIN | SELECT/INSERT/UPDATE на orders+order_items |
| analyst_ivanova | LOGIN | SELECT (через eshop_readonly) |
| app_backend | LOGIN | INSERT/UPDATE (через eshop_app) |

## 3. Резервное копирование

| Тип бэкапа | Частота | Ретенция |
|------------|---------|----------|
| pg_dump -Fc | Ежедневно | 30 дней |
| Basebackup | Еженедельно | 4 недели |
| WAL-архив | Непрерывно | До восстановления |

| Параметр | Значение |
|----------|----------|
| RPO | 24 часа |
| RTO | 2 часа |

## 4. Мониторинг и пороги

| Метрика | Порог предупреждения | Порог критический |
|---------|---------------------|-------------------|
| Подключения | > 80% | > 95% |
| Cache hit ratio | < 95% | < 90% |
| Dead tuples (на таблицу) | > 10000 | > 50000 |
| Replication lag | > 1 сек | > 10 сек |

## 5. Производительность

### Индексы

| Таблица | Индекс | Тип |
|---------|--------|-----|
| orders | idx_orders_customer_id | B-tree |
| orders | idx_orders_promo_code_id | B-tree |
| products | idx_products_category_id | B-tree |

### Autovacuum

| Таблица | autovacuum_vacuum_scale_factor | autovacuum_analyze_scale_factor |
|---------|-------------------------------|--------------------------------|
| orders | 0.05 | 0.02 |
| products | 0.1 | 0.05 |

### PgBouncer

- Pool mode: transaction
- Max client connections: 200
- Default pool size: 20

## 6. Информационная безопасность

| Компонент | Статус |
|-----------|--------|
| pgAudit | [включён/нет] |
| SSL/TLS | [включён/нет] |
| Шифрование pgcrypto | [включено/нет] |
| RLS | [включён/нет] |
| 152-ФЗ | [соответствует/нет] |

## 7. Flyway миграции

| Версия | Описание | Статус |
|--------|----------|--------|
| V001 | Initial schema | Applied |
| V002 | Add categories | Applied |
| V003 | Create promo_codes | Applied |
| V004 | [была отменена] | — |
| V005 | [ошибка] | — |
| V006 | Fix manager_id | Applied |
| V007 | Add confirmed_at safe | Applied |
| V008 | Rename customer_name | Applied |

**Инцидент:** V005 — [описание инцидента и как откатили]

## 8. Zero-downtime паттерны

| Паттерн | Применение |
|---------|------------|
| Forward rollback | V005 → V006 |
| ADD NOT NULL (3 шага) | V007 |
| RENAME COLUMN (5 шагов) | V008 |
| CREATE INDEX CONCURRENTLY | idx_orders_total_amount |

## 9. Выводы

[Общий вывод по проекту: что сделано, чему научились, что можно улучшить]
