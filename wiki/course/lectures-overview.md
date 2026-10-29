# Lectures Overview

13 lectures, 26 academic hours total; each lecture links to the corresponding wiki concept pages and covers competencies from [[course/rpd|РПД]].

## Thematic Plan

| Week | Lecture | Topic | Key concept pages |
| ---- | ------- | ----- | ----------------- |
| 1 | lec_01 | DBA role, PostgreSQL architecture, ERD, Crow's Foot notation | [PostgreSQL Architecture](../concepts/postgresql-architecture.md) |
| 2 | lec_02 | Installation (EDB/Docker), postgresql.conf, pg_hba.conf, psql, DBeaver | [PostgreSQL Architecture](../concepts/postgresql-architecture.md), [DBeaver](../tools/dbeaver.md) |
| 3 | lec_03 | Roles and users: unified concept, LOGIN/SUPERUSER/REPLICATION attributes, RBAC | [Security](../concepts/security.md) |
| 4 | lec_04 | Privilege hierarchy, GRANT/REVOKE, ALTER DEFAULT PRIVILEGES, schemas, RLS, transaction isolation | [Security](../concepts/security.md) |
| 5 | lec_05 | RPO/RTO, pg_dump formats, pg_dumpall, pg_basebackup, WAL archiving, 3-2-1 rule | [Backup & Recovery](../concepts/backup-recovery.md) |
| 6 | lec_06 | Recovery scenarios, PITR setup, recovery.signal, failover runbook template | [Backup & Recovery](../concepts/backup-recovery.md), [Failover Runbook](../procedures/failover-runbook.md) |
| 7 | lec_07 | pg_stat_activity, idle-in-transaction, blocking queries, dead tuples, pg_stat_statements, cache hit ratio | [Monitoring](../concepts/monitoring.md), [WAL & MVCC](../concepts/wal-mvcc.md) |
| 8 | lec_08 | Query analysis workflow, EXPLAIN ANALYZE reading, when indexes help, N+1 problem, auto_explain, pgBadger | [Indexes](../concepts/indexes.md), [Monitoring](../concepts/monitoring.md), [pgBadger](../tools/pgbadger.md) |
| 9 | lec_09 | Index types (B-tree/Hash/GIN/GiST/BRIN), partial/expression/composite, CREATE INDEX CONCURRENTLY, autovacuum tuning, PgBouncer modes, capacity planning | [Indexes](../concepts/indexes.md), [Connection Pooling](../concepts/connection-pooling.md) |
| 10 | lec_10 | HA concepts (SLA/MTBF/MTTR), streaming replication setup, hot standby, synchronous replication, logical replication, Patroni | [Replication](../concepts/replication.md) |
| 11 | lec_11 | Security threats, 152-ФЗ categories, pgAudit (session/object), TLS (ssl=on, hostssl), pgcrypto | [Security](../concepts/security.md) |
| 12 | lec_12 | Flyway naming (V/U/R), flyway.toml, commands, flyway_schema_history, MR process, Migration Plan template | [Flyway](../tools/flyway.md), [Migration Workflow](../procedures/migration-workflow.md) |
| 13 | lec_13 | Rollback strategies, zero-downtime patterns (ADD NOT NULL, RENAME, DROP TABLE), vacuumdb/reindexdb, modern DBMS landscape | [Rollback Strategies](../procedures/rollback-strategies.md), [Zero-Downtime](../procedures/zero-downtime.md) |

## Lecture Structure (standard format)

Every lecture follows the same outline:
1. **Цель** — learning objectives
2. **Numbered sections** — content
3. **Итоги** — summary table or bullet points
4. **Ссылки** — official documentation links

## Communication Templates by Lecture

Each practical lecture introduces a reusable communication template:

| Lecture | Template purpose |
| ------- | ---------------- |
| lec_01 | Role request initiation |
| lec_03 | Role attribute request to DBA |
| lec_04 | Access matrix documentation |
| lec_06 | Failover runbook |
| lec_08 | Query optimisation request |
| lec_09 | Hardware modernisation justification |
| lec_10 | HA requirements specification |
| lec_12 | Migration Plan + Runbook |

## See also

- [Labs Overview](labs-overview.md) — how lectures map to hands-on labs
- [eshop Schema](eshop-schema.md) — the running project developed across all labs
