# DBA Course Wiki — Index

> Knowledge base for «Администрирование баз данных», 13 weeks, PostgreSQL 18 + Flyway + PgBouncer + pgBadger.

## Concepts

| Page | Summary |
| ---- | ------- |
| [PostgreSQL Architecture](concepts/postgresql-architecture.md) | Processes, memory, PGDATA layout, shared buffers |
| [WAL & MVCC](concepts/wal-mvcc.md) | Write-Ahead Log, MVCC, dead tuples, VACUUM |
| [Indexes](concepts/indexes.md) | B-tree, Hash, GIN, GiST, BRIN; partial/expression/composite |
| [Backup & Recovery](concepts/backup-recovery.md) | pg_dump, pg_basebackup, WAL archiving, PITR, RPO/RTO |
| [Replication](concepts/replication.md) | Streaming replication, logical replication, Patroni, failover |
| [Security](concepts/security.md) | Roles, RLS, pg_hba.conf, pgAudit, TLS, pgcrypto, 152-ФЗ |
| [Access Control Models](concepts/access-control-models.md) | DAC, RBAC, ABAC/RLS, MAC, ReBAC — теория и PostgreSQL-реализация |
| [Normalization](concepts/normalization.md)                 | 1НФ–5НФ, BCNF, аномалии, денормализация, упражнение с ERD       |
| [Monitoring](concepts/monitoring.md) | pg_stat_activity, pg_stat_user_tables, pg_stat_statements, pgBadger |
| [Connection Pooling](concepts/connection-pooling.md) | PgBouncer modes, pool sizing, transaction mode limitations |
| [Locks & Concurrency](concepts/locks-concurrency.md) | Табличные/строчные блокировки, Lock Queue, deadlock, lock_timeout |
| [High Availability](concepts/high-availability.md) | SLA, MTBF, MTTR, кворум, split-brain, switchover vs failover |
| [DBMS Landscape](concepts/dbms-landscape.md) | OLTP, OLAP (ClickHouse), NewSQL, Key-Value (Redis), Vector (pgvector) |

## Tools

| Page | Summary |
| ---- | ------- |
| [psql](tools/psql.md) | CLI terminal: флаги подключения, метакоманды (\d, \l, \x), скрипты |
| [DBeaver](tools/dbeaver.md) | GUI client: connections, auto-commit gotchas, EXPLAIN |
| [Flyway](tools/flyway.md) | CLI migration tool: naming, commands, flyway.toml |
| [PgBouncer](tools/pgbouncer.md) | Connection pooler: install, pgbouncer.ini, userlist.txt |
| [pgbench](tools/pgbench.md) | Нагрузочное тестирование: TPS, latency, валидация пула соединений |
| [pgBadger](tools/pgbadger.md) | Log analyser: setup, log_line_prefix, HTML reports |
| [pgAudit](tools/pgaudit.md) | Аудит безопасности: сессионный/объектный аудит, 152-ФЗ |
| [Patroni](tools/patroni.md) | HA-оркестратор: DCS etcd/consul, patronictl, авто-failover |
| [Obsidian](tools/obsidian.md) | IDE для wiki: граф связей, [[wiki-links]], плагины Ollama, workflows Lint/Ingest/Query |

## Procedures

| Page | Summary |
| ---- | ------- |
| [Migration Workflow](procedures/migration-workflow.md) | Plan → validate → migrate → info → repair cycle |
| [Rollback Strategies](procedures/rollback-strategies.md) | Forward rollback, undo scripts, PITR — when to use each |
| [Zero-Downtime Patterns](procedures/zero-downtime.md) | ADD NOT NULL, RENAME COLUMN, CREATE INDEX CONCURRENTLY |
| [Failover Runbook](procedures/failover-runbook.md) | Step-by-step failover for streaming replication |

## Roles

| Page | Summary |
| ---- | ------- |
| [DBA vs SA](roles/dba-vs-sa.md)         | Who does what: DBA leads, SA participates in each lab task |
| [Team Roles](roles/team-roles.md)        | DBA, SA, PM, BE, RND, DevOps — роли и взаимодействие SA с каждой; 11 use stories |

## Course

| Page | Summary |
| ---- | ------- |
| [РПД дисциплины](course/rpd.md) | Утвержденная рабочая программа (ГУУ, 2026), матрица компетенций ПК-1, ПК-3, ПК-5 |
| [Lectures Overview](course/lectures-overview.md) | One-line summary of all 13 lectures |
| [Labs Overview](course/labs-overview.md) | Goal + checklist items for all 10 labs |
| [eshop Schema](course/eshop-schema.md) | ERD, tables, roles, RLS, data volumes, Flyway history |
| [Тренажёр](course/trainer.md) | Агент-собеседник: вопросы, оценка ответов, объяснение тем с примерами из eshop |

## Cheatsheets

| Page                                    | Summary                                                              |
| --------------------------------------- | -------------------------------------------------------------------- |
| [Mermaid](cheatsheets/mermaid.md)       | flowchart, erDiagram, stateDiagram-v2 — синтаксис и примеры из курса |
| [Git](cheatsheets/git.md)               | Базовый workflow, ветвление, rebase, stash, MR-процесс для миграций  |
| [Markdown](cheatsheets/markdown.md)     | GFM + Obsidian: таблицы, блоки кода, ссылки, callouts, frontmatter  |

## Artifacts

Документы, создаваемые студентом в ходе лабораторных работ.

| Page | Summary |
| ---- | ------- |
| [Index](artifacts/index.md) | Каталог всех артефактов: когда создавать и кому передавать |
| [Access Matrix](artifacts/access-matrix.md) | Матрица доступа (лаб. 02): роли × таблицы, GRANT + RLS шаблоны |
| [Backup Policy](artifacts/backup-policy.md) | Регламент бэкапов (лаб. 03): типы, частота, RPO/RTO |
| [Failover Runbook](artifacts/failover-runbook.md) | Действия при инциденте (лаб. 04): роль аналитика vs DBA |
| [DB Health Report](artifacts/db-health-report.md) | Отчёт о состоянии БД (лаб. 05): pg_stat_* запросы + шаблон |
| [EXPLAIN Analysis](artifacts/explain-analysis.md) | Анализ медленного запроса (лаб. 06): EXPLAIN ANALYZE + словарь |
| [PgBouncer Justification](artifacts/pgbouncer-justification.md) | Обоснование пулера (лаб. 07): проблема / решение / ограничения |
| [Security Checklist](artifacts/security-checklist.md) | ИБ-чек-лист (лаб. 08): auth, audit, TLS, 152-ФЗ |
| [Migration Plan](artifacts/migration-plan.md) | План миграции (лаб. 09): шаблон для MR-ревью DBA |
| [Deployment Runbook](artifacts/deployment-runbook.md) | Runbook деплоя (лаб. 09): пошагово с откатом |
| [Project Report](artifacts/project-report.md) | Итоговый отчёт (лаб. 10): 9 разделов + вопросы к защите |

## Reference

| Page | Summary |
| ---- | ------- |
| [Glossary](glossary.md) | 60+ terms: MVCC, WAL, RPO, PITR, bloat, shard… |
