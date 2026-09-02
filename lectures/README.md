# Лекции курса «Администрирование БД»

Краткое описание тем по неделям.

| Нед. | Файл                       | Тема                                                                    | Ключевые понятия                                                                                     |
| ---- | -------------------------- | ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| 1    | [lec_01](lec_01/lec_01.md) | Роль DBA. Архитектура PostgreSQL. ERD. Нормализация. Коммуникация       | postmaster, backend, shared_buffers, WAL, ERD, Crow's Foot, 1НФ/2НФ/3НФ, BIGSERIAL/NUMERIC/TIMESTAMPTZ, шаблон тикета |
| 2    | [lec_02](lec_02/lec_02.md) | Установка и конфигурирование PostgreSQL                                 | postgresql.conf, pg_hba.conf, initdb, pg_ctl, psql, DBeaver                                          |
| 3    | [lec_03](lec_03/lec_03.md) | Роли и пользователи. Модель аутентификации                              | CREATE ROLE, INHERIT, NOLOGIN, pg_hba.conf, scram-sha-256, SET ROLE                                  |
| 4    | [lec_04](lec_04/lec_04.md) | Привилегии, схемы, разграничение доступа. RLS. Уровни изоляции          | GRANT, REVOKE, ALTER DEFAULT PRIVILEGES, search_path, RLS, CREATE POLICY, Read Committed, Serializable, dirty read, phantom |
| 5    | [lec_05](lec_05/lec_05.md) | Резервное копирование: pg_dump, pg_basebackup, WAL-архивирование        | RPO, RTO, -Fc, -Fd, pg_dumpall --globals-only, archive_mode, archive_command                         |
| 6    | [lec_06](lec_06/lec_06.md) | Восстановление, PITR, отработка сбоев                                   | pg_restore, recovery.signal, restore_command, recovery_target_time, runbook                          |
| 7    | [lec_07](lec_07/lec_07.md) | Мониторинг, сбор статистики, журналирование                             | pg_stat_activity, pg_stat_user_tables, pg_stat_bgwriter, cache hit ratio, log_min_duration_statement |
| 8    | [lec_08](lec_08/lec_08.md) | Анализ медленных запросов: pg_stat_statements, EXPLAIN, pgBadger        | total_exec_time, Seq Scan, Index Scan, Batches, shared_blks_read, auto_explain                       |
| 9    | [lec_09](lec_09/lec_09.md) | Оптимизация. Индексы. Connection Pooling. Обоснование модернизации ПАО  | B-tree, GIN, BRIN, partial index, autovacuum bloat, PgBouncer transaction mode                       |
| 10   | [lec_10](lec_10/lec_10.md) | Отказоустойчивость и репликация PostgreSQL                              | SLA, MTBF, MTTR, streaming replication, replay_lag, hot standby, Patroni                             |
| 11   | [lec_11](lec_11/lec_11.md) | Информационная безопасность на уровне БД. Аудит                         | SQL-инъекция, pgAudit, session audit, TLS, hostssl, pg_crypto, 152-ФЗ                                |
| 12   | [lec_12](lec_12/lec_12.md) | Версионирование схемы БД. Flyway. Migration Plan. Runbook               | V/U/R-файлы, двойное подчёркивание, flyway info/validate, cleanDisabled=true                         |
| 13   | [lec_13](lec_13/lec_13.md) | Rollback-стратегии. Обслуживание БД. Управление изменениями. Итог курса | forward rollback, undo, PITR, zero-downtime, vacuumdb, pg_upgrade, NewSQL, pgvector                  |
