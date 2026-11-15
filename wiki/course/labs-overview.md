# Labs Overview

10 lab sessions, 20 academic hours total; all labs build on a single eshop project database and implement competencies from [[course/rpd|РПД]].

## Lab Map

| Lab | Week | Title | Core skills |
| --- | ---- | ----- | ----------- |
| lab_01 | 1–2 | PostgreSQL install, Chinook, backup/restore cycle | Install, psql basics, pg_dump, ERD |
| lab_02 | 3–4 | eshop schema + role model + RLS | CREATE TABLE, ROLE, GRANT, RLS policies |
| lab_03 | 5–6 | Backup policy implementation | pg_dump formats, pg_dumpall, pg_basebackup, WAL archiving |
| lab_04 | 6 | Recovery: selective, full, PITR | pg_restore -t, recovery.signal, PITR, failover runbook |
| lab_05 | 7 | Monitoring: sessions, bloat, cache | pg_stat_activity, VACUUM, cache hit ratio, logging config |
| lab_06 | 8 | Query analysis: pg_stat_statements, EXPLAIN, pgBadger | 200k orders dataset, EXPLAIN ANALYZE, pgBadger setup |
| lab_07 | 9 | Indexes, autovacuum, PgBouncer | Partial/composite/expression indexes, autovacuum tuning, PgBouncer install |
| lab_08 | 11 | Security: pgAudit, TLS, pgcrypto, 152-ФЗ | pgAudit session/object, ssl=on, pgp_sym_encrypt |
| lab_09 | 12 | Flyway migrations + Migration Plan + Runbook | flyway baseline/migrate/validate/repair, V002–V003 migrations |
| lab_10 | 13 | Rollback, zero-downtime, final project defence | Forward rollback, ADD NOT NULL 3-step, RENAME COLUMN 4-step, project report |

## Per-Lab Detail

### Lab 01 — Install & First Backup
- Install PostgreSQL 18 (EDB installer) + DBeaver
- Restore Chinook database (music store, for learning)
- `pg_dump` → drop → `pg_restore` cycle
- ERD: generate from DBeaver

### Lab 02 — eshop Schema & Access Control
- Create 4 tables: `customers`, `products`, `orders`, `order_items`
- Create roles: `eshop_readonly`, `eshop_app`, `analyst_ivanova`, `app_backend`
- RLS on `customers`: analyst sees only customers in their region
- `ALTER DEFAULT PRIVILEGES` for future tables

### Lab 03 — Backup Policy
- `pg_dump -Fc` (custom), `-Fd` (directory), plain SQL
- `pg_dumpall --globals-only` (roles are cluster-wide)
- `pg_basebackup --wal-method=stream`
- Enable WAL archiving (`archive_mode = on`, `archive_command`)
- Document backup policy table (4 levels)

### Lab 04 — Recovery & PITR
- Selective restore: `pg_restore -t customers`
- Full logical restore to new database
- PITR simulation: create restore point → corrupt data → recover to named point
- Fill in failover runbook with DBA and SA responsibilities

### Lab 05 — Monitoring Deep Dive
- Simulate blocking: two sessions, one holds lock
- pg_stat_activity: find blocking query, terminate it
- Dead tuples experiment: mass UPDATE → count n_dead_tup → VACUUM
- VACUUM vs VACUUM FULL
- Cache hit ratio baseline
- Configure logging (log_min_duration_statement, log_line_prefix)

### Lab 06 — Query Analysis
- Enable pg_stat_statements (ALTER SYSTEM + restart)
- Generate large dataset: 20k customers, 1k products, 200k orders, 600k order_items
- EXPLAIN ANALYZE: before and after index creation
- pgBadger: install Strawberry Perl, generate HTML report from log
- Self-study: identify missing FK indexes, investigate bloat

### Lab 07 — Indexes, Autovacuum, PgBouncer
- Reset orders status distribution (realistic: 85% delivered, 5% shipped, 5% cancelled, 3% processing, 2% pending)
- Partial index `idx_orders_active` — compare size vs full index
- Composite index `idx_orders_status_created` — column order rule
- `CREATE INDEX CONCURRENTLY idx_order_items_product` — verify `indisvalid`
- Expression index `idx_customers_email_lower`
- Autovacuum threshold tuning per table
- PgBouncer install, pgbouncer.ini, userlist.txt, SHOW POOLS, pgbench 50 clients
- Document pgbouncer_justification.md with measured numbers

### Lab 08 — Security
- pgAudit: install, configure `pgaudit.log = 'write,ddl,role'`, verify in log
- Object-level audit via `pgaudit.role`
- TLS: `ssl=on`, self-signed cert, `hostssl` in pg_hba.conf
- pgcrypto: encrypt `customers.phone`, decrypt, verify analyst can't read it
- IB checklist: 152-ФЗ classification, ib_checklist.md

### Lab 09 — Flyway
- flyway.toml with `cleanDisabled = true`
- `flyway baseline` (existing schema = version 1)
- V002: add `categories` table, link to `products`
- V003: add `promo_codes` table, FK from `orders`
- R__: repeatable view migration
- Intentional checksum mismatch → `flyway validate` error
- Migration Plan V003 + Runbook

### Lab 10 — Rollback & Final Defence
- V005 bad migration (NOT NULL without default) → Failed state
- V006 forward rollback
- Manual undo script + `flyway repair`
- ADD NOT NULL 3-step (V007)
- RENAME COLUMN 4-step (V008)
- `CREATE INDEX CONCURRENTLY` with `indisvalid` check
- `vacuumdb --full` + `reindexdb --concurrently`
- Final project report: all sections of eshop_project_report.md
- Oral defence: 3 questions from the question bank

## Exam Requirements

All 10 lab checklists must be complete before the exam. The exam consists of:
- **Project report** (60 points): `eshop_project_report.md` with 8 graded sections
- **Oral defence** (40 points): 3 questions from the 23-question bank

Passing score: 55 / 100. Grade scale: 55–69 satisfactory, 70–84 good, 85–100 excellent.

## See also

- [eshop Schema](eshop-schema.md) — cumulative schema after all labs
- [Lectures Overview](lectures-overview.md) — source theory for each lab
- [DBA vs SA](../roles/dba-vs-sa.md) — responsibilities in each lab
