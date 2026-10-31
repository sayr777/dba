# Glossary

Key terms for «Администрирование баз данных», alphabetically.

---

**152-ФЗ** — Russian Federal Law on Personal Data; requires personal data of Russian citizens to be stored on servers in Russia; eshop data (name + email + phone) falls under УЗ-3 (general category).

**AccessExclusiveLock** — the heaviest table-level lock in PostgreSQL (acquired by ALTER TABLE, DROP TABLE, VACUUM FULL); conflicts with all other locks, blocking both reads and writes.

**ALTER DEFAULT PRIVILEGES** — pre-grants privileges on objects not yet created; used so future tables automatically get correct permissions for existing roles.

**archive_command** — shell command that copies a completed WAL segment to the archive. Must return exit code 0 only when the segment is safely stored.

**archive_mode** — parameter that enables WAL archiving (`on`); required for PITR and for a standby to catch up from an archive.

**archive_timeout** — forces WAL segment rotation after the given interval even with low write activity; bounds archive delay and therefore practical RPO.

**autovacuum** — background process that automatically runs VACUUM and ANALYZE on tables when dead tuple count exceeds a threshold.

**B-tree** — default index type in PostgreSQL; a balanced sorted tree supporting equality, range, `LIKE 'prefix%'`, and `ORDER BY` operations.

**Backend** — per-connection PostgreSQL process; allocated 5–10 MB of memory; dies when the client disconnects.

**Baseline (Flyway)** — marker that tells Flyway "everything up to version N is already applied"; used when adopting Flyway on an existing database.

**Bitmap Heap Scan** — scan node that first collects all heap page numbers from an index (Bitmap Index Scan), sorts them, then reads each page once in order; efficient for hundreds–thousands of rows.

**bloat** — wasted space in a table or index caused by dead tuple versions not yet reclaimed by VACUUM.

**BRIN** (Block Range INdex) — very small index that stores min/max values per range of physical pages; effective for naturally-ordered large tables.

**cache hit ratio** — percentage of page requests served from `shared_buffers` rather than disk; target ≥ 99 % for OLTP.

**checkpoint** — point at which the checkpointer flushes all dirty `shared_buffers` pages to disk and writes a checkpoint record to WAL; limits crash recovery time.

**checksum (Flyway)** — hash of a migration file stored in `flyway_schema_history`; if the file changes after being applied, `flyway validate` fails.

**cleanDisabled** — Flyway configuration flag; `true` disables `flyway clean` to prevent accidental full database wipe in production.

**Column-level privilege** — `GRANT SELECT (col1, col2) ON table`; restricts access to individual columns. `SELECT *` fails if it touches a forbidden column.

**ClickHouse** — open-source column-oriented analytical DBMS (OLAP) designed for real-time reporting and aggregated queries over billions of rows.

**CONCURRENTLY** — modifier for `CREATE INDEX` and `DROP INDEX`; avoids write locks by performing two table scans with MVCC snapshots.

**dead tuples** — old row versions that no active transaction snapshot can see; wasting space and slowing sequential scans; reclaimed by VACUUM.

**deadlock** — situation where two or more transactions each wait for a lock held by the other; resolved automatically by PostgreSQL deadlock detector after deadlock_timeout.

**DEFAULT PRIVILEGES** — rules set by `ALTER DEFAULT PRIVILEGES` that automatically apply `GRANT` to objects created in the future by a specific role.

**default_pool_size** — PgBouncer parameter: number of real PostgreSQL backend connections per (database, user) pair.

**ERD** (Entity-Relationship Diagram) — visual representation of tables and their relationships; the course uses Crow's Foot notation.

**Expression index** — index that stores the result of a function or expression; the query must use the exact same expression for the index to be used.

**failover** — promotion of a standby to primary when the primary fails; can be manual or automatic (with Patroni).

**Flyway** — database migration tool that versions SQL scripts and tracks their execution state in `flyway_schema_history`.

**forward rollback** — strategy for undoing a bad migration by writing a new corrective migration rather than reverting; preferred because it always moves history forward.

**GIN** (Generalised Inverted iNdex) — index type for array containment, full-text search, and JSONB keys.

**GiST** (Generalised Search Tree) — extensible index type for geometric types, range types, and full-text (alternative to GIN).

**GRANT** — SQL command that gives a role a privilege on a database object.

**Hash index** — index type that stores a hash of the column value; supports only equality (`=`); slightly faster than B-tree for pure equality lookups.

**hot standby** — standby server that accepts read-only queries while replaying WAL; enabled by `hot_standby = on`.

**hostssl** — `pg_hba.conf` rule type that accepts TCP connections only if they use TLS; safer than `host`, which allows both encrypted and plain connections.

**idle in transaction** — session state where a client is inside a `BEGIN` block but not executing a query; dangerous because it holds locks and prevents VACUUM.

**Index Only Scan** — scan node that returns results entirely from the index, without reading heap pages; requires all needed columns to be in the index and visibility map to be up to date.

**Index Scan** — scan node that looks up each row pointer in the index and fetches it from the heap; efficient for few rows.

**indisvalid** — `pg_index` column; `false` means the index is broken and not used by the planner; must be dropped and recreated.

**Lock Queue** — FIFO queue of transactions waiting for incompatible table locks; an ACCESS EXCLUSIVE lock waiting in queue blocks all subsequent read requests.

**lock_timeout** — session/transaction parameter that aborts any statement waiting for a lock longer than the specified duration; essential safeguard for zero-downtime DDL.

**log_line_prefix** — format string for log lines; must include time, PID, user, database and client for pgBadger to parse logs correctly.

**log_statement** — parameter controlling which SQL statements are logged (`none`, `ddl`, `mod`, `all`); `all` on production risks leaks and disk overflow.

**LSN** (Log Sequence Number) — monotonically increasing byte offset into the WAL stream; used as PITR recovery target.

**max_client_conn** — PgBouncer parameter: total number of clients that can connect to PgBouncer simultaneously.

**MTBF** — (Mean Time Between Failures) average operational time of a system between occurrences of hardware or software failures.

**MTTR** — (Mean Time To Recovery) average time required to repair or restore a failed system back to normal operation.

**MVCC** (Multi-Version Concurrency Control) — technique where each row has multiple timestamped versions; readers see a consistent snapshot without blocking writers.

**pg_basebackup** — utility that takes a physical copy of an entire PostgreSQL cluster; required as the starting point for PITR and standby setup.

**pg_ctl** — command-line utility to start, stop, restart, reload and check a PostgreSQL cluster (`pg_ctl -D PGDATA`).

**Partial index** — an index with a `WHERE` clause; indexes only rows matching the condition, making it smaller and faster to maintain.

**Patroni** — HA orchestrator for PostgreSQL using Distributed Configuration Stores (etcd/Consul) for automated failover, leader elections, and split-brain prevention.

**pg_dump** — utility that takes a logical backup of a single database; supports plain SQL, custom (-Fc), and directory (-Fd) formats.

**pg_dumpall** — utility that dumps all databases plus cluster-wide objects (roles, tablespaces).

**pg_hba.conf** — Host-Based Authentication configuration file; rules are evaluated top-to-bottom, first match wins.

**pg_reload_conf()** — SQL function that reloads `postgresql.conf` and `pg_hba.conf` without restart; does not apply `postmaster`-context parameters such as `shared_buffers`.

**pg_repack** — extension that rewrites a bloated table or index online, with brief locks instead of the long `ACCESS EXCLUSIVE` of `VACUUM FULL`.

**pg_restore** — utility that restores a custom-format or directory-format dump created by pg_dump.

**pg_stat_activity** — system view showing all current sessions: state, query, wait event, duration.

**pg_stat_ssl** — system view showing which sessions use TLS, with protocol version and cipher.

**pg_stat_statements** — extension that aggregates query execution statistics (total time, calls, rows, stddev).

**pg_stat_user_tables** — system view showing per-table statistics: live/dead tuple counts, last autovacuum time, I/O stats.

**pg_upgrade** — utility that upgrades a PostgreSQL cluster between major versions (e.g. 17 → 18) without a full logical dump; requires stopping both clusters and running `--check` first.

**pg_waldump** — utility that prints WAL records; used to find the exact LSN of a transaction (e.g. a mistaken DELETE or DROP) for PITR.

**pgAudit** — PostgreSQL extension for SQL-level audit logging; supports session-level and object-level auditing.

**pgBadger** — Perl tool that parses PostgreSQL log files and generates HTML reports with slow query analysis.

**pgbench** — PostgreSQL built-in benchmarking tool based on TPC-B transactions; measures TPS and latency under concurrent client load.

**PgBouncer** — connection pooler that multiplexes many client connections through a small pool of backend connections.

**pgbouncer.ini** — PgBouncer configuration file; defines databases, pool settings, authentication, and logging.

**pgcrypto** — PostgreSQL extension providing cryptographic functions including `pgp_sym_encrypt`/`pgp_sym_decrypt`.

**PGDATA** — directory containing all PostgreSQL cluster data files, WAL segments, and configuration files.

**pgvector** — PostgreSQL extension adding vector similarity search (HNSW, IVFFlat) for AI, LLM embeddings, and RAG systems.

**PITR** (Point-In-Time Recovery) — recovery technique that replays WAL segments from a base backup to a specific time, LSN, or named restore point.

**pool_mode** — PgBouncer parameter: `session` (connection per session), `transaction` (connection per transaction), or `statement`.

**postmaster** — the main PostgreSQL process that listens on the port, forks backend processes, and monitors child processes.

**postmaster.pid** — file in PGDATA containing the postmaster PID; its absence means the server is stopped, its presence with a dead PID means an unclean shutdown.

**psql** — command-line interactive terminal client for PostgreSQL supporting meta-commands, script execution, and administrative automation.

**PUBLICATION** — logical replication object on the primary that defines which tables to replicate.

**Read Committed** — default PostgreSQL isolation level; each statement sees a fresh snapshot, so non-repeatable reads and phantoms are possible.

**recovery.signal** — empty file placed in PGDATA to tell PostgreSQL to enter recovery mode; removed automatically after promotion (PG 12+).

**reindexdb** — command-line wrapper for `REINDEX`; supports a single index, table or whole database, and `--concurrently` for online rebuilds.

**Redis** — in-memory key-value data structure store used for high-speed caching, session management, and pub/sub message brokers.

**Repeatable migration (R__)** — Flyway migration that re-runs whenever its file checksum changes; used for views, functions, procedures.

**Repeatable Read** — isolation level where the transaction sees one snapshot; prevents non-repeatable reads and phantoms, but write skew is still possible.

**restore_command** — shell command that copies a WAL segment from the archive to the recovery process; used during PITR.

**RLS** (Row-Level Security) — feature that adds a transparent WHERE clause to every query on a table based on policy conditions.

**RPO** (Recovery Point Objective) — maximum acceptable data loss measured in time; e.g. RPO = 1 hour means losing up to 1 hour of data is acceptable.

**RTO** (Recovery Time Objective) — maximum acceptable downtime after a failure.

**SCRAM-SHA-256** — password authentication method using Salted Challenge Response Authentication; recommended over MD5.

**search_path** — ordered list of schemas PostgreSQL searches for unqualified object names; a writable schema early in the path is a security risk.

**Serializable** — strictest isolation level; prevents write skew by aborting conflicting transactions with `serialization_failure` (SQLSTATE 40001).

**Seq Scan** — sequential scan that reads every page of a table; efficient when fetching > ~10–15 % of rows.

**shared_buffers** — PostgreSQL's page cache in shared memory; typical setting is 25 % of RAM.

**SLA** — (Service Level Agreement) contractual commitment defining the percentage of time a service must remain available (e.g. 99.9% availability allows max ~8.7 hours downtime/year).

**Split-Brain** — critical cluster failure state where network partitioning causes multiple nodes to believe they are the active primary, resulting in conflicting writes.

**standby.signal** — empty file placed in PGDATA to tell PostgreSQL it is a standby server (PG 12+).

**statement_timeout** — server/session parameter that aborts any query whose execution duration exceeds the specified threshold.

**SUBSCRIPTION** — logical replication object on the standby that connects to a PUBLICATION and applies changes.

**Switchover** — planned and graceful promotion of a standby to primary with zero data loss (RPO = 0), typically for maintenance.

**Timeline (WAL)** — branch number in the WAL history; a new timeline starts after PITR promotion or standby promotion, preventing replay from diverging branches.

**synchronous_commit** — controls when a `COMMIT` returns to the client: `on` = after local WAL flush; `remote_write` = after standby WAL write; `remote_apply` = after standby replay.

**transaction mode** — PgBouncer pool mode where a server connection is held only for the duration of one transaction.

**Transaction isolation** — level that defines which concurrent changes a transaction can see: `Read Committed` (default), `Repeatable Read`, `Serializable`.

**USAGE** — schema-level privilege required to reference objects in the schema; without it `GRANT SELECT` on a table still yields `permission denied for schema`.

**VACUUM** — command that marks dead tuples as reusable (does not shrink the file); runs automatically via autovacuum.

**VACUUM FULL** — rewrites the table entirely, freeing space to OS; requires `AccessExclusiveLock`; avoid during business hours.

**vacuumdb** — command-line utility wrapper around VACUUM; supports `--full`, `--analyze`, `--freeze` options.

**WAL** (Write-Ahead Log) — durability mechanism where changes are written to `pg_wal/` before data pages; enables crash recovery and PITR.

**wal_level** — parameter controlling how much information is written to WAL: `minimal`, `replica` (needed for streaming), `logical` (needed for logical replication).

**walsender** — background process on the primary that streams WAL to a standby's walreceiver.

**work_mem** — per-sort/per-hash-table memory allocation; multiplied by concurrent operations per connection; set conservatively to avoid OOM.

**Write skew** — anomaly where two transactions read overlapping data, make disjoint writes, and together violate an invariant; prevented only by `Serializable`.

**xmax** — hidden column storing the transaction ID that deleted or updated a row version (0 = still live).

**xmin** — hidden column storing the transaction ID that inserted a row version.

**zero-downtime migration** — schema change pattern that avoids write locks on large tables; key patterns: ADD NOT NULL (3 steps), RENAME COLUMN (4 steps, 2 releases), CREATE INDEX CONCURRENTLY.

