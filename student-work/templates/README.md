# Шаблоны файлов-артефактов лабораторных работ

Каждый файл — шаблон с placeholder-значениями. Замените на свои данные.

## Лабораторная 01 — Установка PostgreSQL и DBeaver

- `lab_01_erd.mermaid` — ERD диаграмма chinook (Mermaid)

## Лабораторная 03 — Резервное копирование

- `lab_03_backup_policy.md` — регламент резервного копирования
- `lab_03_eshop_plain.sql` — plain-дамп (команда pg_dump)
- `lab_03_globals.sql` — дамп ролей (команда pg_dumpall)

## Лабораторная 04 — Восстановление и PITR

- `lab_04_failover_runbook.md` — runbook аварийного восстановления

## Лабораторная 05 — Мониторинг

- `lab_05_db_health_report.md` — отчёт о здоровье БД

## Лабораторная 06 — Анализ запросов

- `lab_06_report.md` — отчёт по анализу запросов

## Лабораторная 07 — Индексы, autovacuum, PgBouncer

- `lab_07_pgbouncer_justification.md` — обоснование введения PgBouncer

## Лабораторная 08 — Информационная безопасность

- `lab_08_ib_checklist.md` — чек-лист ИБ

## Лабораторная 09 — Flyway

- `lab_09_flyway.toml` — конфигурация Flyway
- `lab_09_migration_plan_V003.md` — план миграции V003
- `lab_09_V002__add_products_category.sql` — миграция V002
- `lab_09_V003__create_promo_codes.sql` — миграция V003
- `lab_09_R__orders_summary_view.sql` — повторяемая миграция (view)

## Лабораторная 10 — Rollback, zero-downtime

- `lab_10_V006__fix_manager_id.sql` — фикс миграции V005
- `lab_10_V007__add_confirmed_at_safe.sql` — ADD NOT NULL без блокировки
- `lab_10_V008__rename_customer_name.sql` — RENAME COLUMN без блокировки
- `lab_10_final_flyway_status.txt` — статус миграций
- `lab_10_eshop_final_schema.sql` — дамп финальной схемы
- `lab_10_eshop_project_report.md` — итоговый отчёт проекта
