# Monitoring

PostgreSQL exposes runtime state through `pg_stat_*` system views; knowing which view answers which question is the core DBA monitoring skill.

## Key Views at a Glance

| View | What it shows | Primary use |
| ---- | ------------- | ----------- |
| `pg_stat_activity` | All current sessions | Find blocking/idle-in-transaction queries |
| `pg_stat_user_tables` | Per-table row counts, dead tuples, I/O | Detect bloat, schedule VACUUM |
| `pg_stat_user_indexes` | Per-index scan counts, I/O | Find unused indexes |
| `pg_stat_statements` | Aggregated query stats (requires extension) | Find slow/expensive queries |
| `pg_stat_bgwriter` / `pg_stat_checkpointer` | Background writer & checkpoint stats | Tune `shared_buffers`, `checkpoint_completion_target` |
| `pg_stat_ssl` | SSL state per connection | Audit encrypted connections |
| `pg_stat_replication` | Standby lag | Monitor replica health |
| `pg_locks` | Active locks | Find lock contention |
| `pg_stat_progress_vacuum` | Running VACUUM progress | Monitor long vacuums |

## pg_stat_activity — Session Monitoring

```sql
-- Active queries running longer than 30 s
SELECT pid, now() - query_start AS duration, state, wait_event_type, wait_event, query
FROM   pg_stat_activity
WHERE  state != 'idle'
  AND  query_start < now() - INTERVAL '30 seconds'
ORDER  BY duration DESC;
```

### States

| State | Meaning |
| ----- | ------- |
| `active` | Executing a query right now |
| `idle` | Waiting for the next command from client |
| `idle in transaction` | Inside `BEGIN`; no query running — **dangerous**: holds locks |
| `idle in transaction (aborted)` | In a failed transaction block |

### Detecting Blocking

```sql
-- Find blocking and blocked sessions
SELECT blocked.pid          AS blocked_pid,
       blocked.query        AS blocked_query,
       blocker.pid          AS blocker_pid,
       blocker.query        AS blocker_query
FROM   pg_stat_activity AS blocked
JOIN   pg_stat_activity AS blocker
       ON blocker.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE  cardinality(pg_blocking_pids(blocked.pid)) > 0;
```

To terminate a blocking session:
```sql
SELECT pg_terminate_backend(pid);   -- graceful; closes connection
SELECT pg_cancel_backend(pid);      -- cancels current query; leaves connection open
```

## pg_stat_user_tables — Bloat Detection

```sql
SELECT relname,
       n_live_tup,
       n_dead_tup,
       round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 1) AS dead_pct,
       last_autovacuum,
       last_autoanalyze
FROM   pg_stat_user_tables
ORDER  BY n_dead_tup DESC;
```

Alert threshold: `dead_pct > 10 %` warrants investigation. `dead_pct > 20 %` → run `VACUUM ANALYZE`.

## pg_stat_statements — Query Profiling

Requires loading the extension:

```sql
-- Enable (requires restart)
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
-- After restart:
CREATE EXTENSION pg_stat_statements;
```

### Top-10 Queries by Total Time

```sql
SELECT round(total_exec_time::numeric, 2) AS total_ms,
       calls,
       round(mean_exec_time::numeric, 2)  AS avg_ms,
       round(stddev_exec_time::numeric, 2) AS stddev_ms,
       rows,
       left(query, 80) AS query_snippet
FROM   pg_stat_statements
ORDER  BY total_exec_time DESC
LIMIT  10;
```

Reset statistics: `SELECT pg_stat_statements_reset();`

## Cache Hit Ratio

Measures what fraction of page reads are served from `shared_buffers` (vs disk).

```sql
SELECT round(100.0 * sum(blks_hit) / nullif(sum(blks_hit) + sum(blks_read), 0), 2)
           AS cache_hit_pct
FROM   pg_stat_database
WHERE  datname = 'eshop';
```

Target: **≥ 99 %** for an OLTP workload. Low ratio → increase `shared_buffers` or investigate full table scans.

## Checkpoint Statistics

```sql
-- PostgreSQL 17+
SELECT checkpoints_timed, checkpoints_req,
       round(checkpoint_write_time / 1000.0, 1) AS write_s,
       round(checkpoint_sync_time  / 1000.0, 1) AS sync_s
FROM   pg_stat_checkpointer;

-- PostgreSQL ≤ 16
SELECT checkpoints_timed, checkpoints_req,
       round(checkpoint_write_time / 1000.0, 1) AS write_s,
       round(checkpoint_sync_time  / 1000.0, 1) AS sync_s
FROM   pg_stat_bgwriter;
```

`checkpoints_req` should be much smaller than `checkpoints_timed`. Many required checkpoints → `max_wal_size` too small.

## Logging Configuration

```ini
# postgresql.conf
log_destination           = 'stderr'
logging_collector         = on
log_directory             = 'log'
log_filename              = 'postgresql-%Y-%m-%d.log'
log_rotation_age          = 1d
log_rotation_size         = 100MB

# Log slow queries
log_min_duration_statement = 1000    # ms; 0 = log all; -1 = disable

# Include metadata for pgBadger
log_line_prefix           = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_checkpoints           = on
log_connections           = on
log_disconnections        = on
log_lock_waits            = on
log_temp_files            = 0
```

## pgBadger — Log Analysis

See [pgBadger](../tools/pgbadger.md) for setup and report generation.

## auto_explain

Logs query plans automatically for slow queries — no manual `EXPLAIN` needed:

```ini
shared_preload_libraries  = 'auto_explain'
auto_explain.log_min_duration = 1000   # ms
auto_explain.log_analyze  = on
auto_explain.log_buffers  = on
auto_explain.log_nested_statements = on
```

## See also

- [Indexes](indexes.md) — `pg_stat_user_indexes` for usage tracking
- [WAL & MVCC](wal-mvcc.md) — dead tuples and autovacuum
- [pgBadger](../tools/pgbadger.md) — automated log analysis
- [Connection Pooling](connection-pooling.md) — `SHOW POOLS` in PgBouncer admin console
