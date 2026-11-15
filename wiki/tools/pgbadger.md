# pgBadger

pgBadger is a Perl-based PostgreSQL log analyser that parses structured log files and generates an HTML report with slow query rankings, error summaries, connection graphs, and lock wait analysis.

## Prerequisites

1. **Strawberry Perl** (Windows) or system Perl (Linux/Mac)
2. **pgbadger** script: download `pgbadger` from https://github.com/darold/pgbadger (single Perl script, no install needed)
3. PostgreSQL logging configured to emit the right fields

## Log Configuration (postgresql.conf)

pgBadger requires a consistent `log_line_prefix` with specific tokens:

```ini
log_destination           = 'stderr'
logging_collector         = on
log_directory             = 'log'
log_filename              = 'postgresql-%Y-%m-%d.log'
log_rotation_age          = 1d

# Required prefix (pgBadger default format)
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '

# What to log
log_min_duration_statement = 1000    # log queries > 1 s
log_checkpoints            = on
log_connections            = on
log_disconnections         = on
log_lock_waits             = on
log_temp_files             = 0       # log all temp file usage
```

After changing: `SELECT pg_reload_conf();` (no restart needed for logging params).

## Running pgBadger

```bash
# Linux / Mac — single log file
perl pgbadger /var/log/postgresql/postgresql-2024-10-15.log \
    -o report.html

# Windows PowerShell
$perl = "C:\Strawberry\perl\bin\perl.exe"
$pg   = "C:\Program Files\PostgreSQL\18"
& $perl pgbadger "$pg\data\log\postgresql-2024-10-15.log" -o report.html
```

### Useful Options

| Option | Effect |
| ------ | ------ |
| `-o report.html` | Output file (default: pgbadger.html) |
| `-f stderr` | Log format (auto-detected, but explicit is safer) |
| `--jobs 4` | Parallel parsing for large files |
| `--last-parsed .pgbadger_last_state` | Incremental mode: skip already-parsed lines |
| `--begin '2024-10-15 10:00:00'` | Filter by time range |
| `--end   '2024-10-15 12:00:00'` | End of time range |
| `--dbname eshop` | Filter by database name |

## Report Sections

| Section | What you see |
| ------- | ------------ |
| **Slowest queries** | Individual queries ranked by duration |
| **Most frequent queries** | Normalised (parameterised) queries by call count |
| **Queries by total time** | Best candidate for index optimisation |
| **Connections** | Connections/disconnections over time |
| **Locks** | Lock waits and deadlocks |
| **Checkpoints** | Checkpoint frequency and duration |
| **Temp files** | Queries that spilled to disk (work_mem too low) |
| **Errors / Warnings** | Fatal errors, panics, warnings |

## Incremental (Scheduled) Reports

For daily reports on a busy server:

```bash
# Run after midnight each day
perl pgbadger /var/log/postgresql/postgresql-*.log \
    --last-parsed /var/lib/pgbadger/.last_state \
    -o /var/www/html/pgbadger/report-$(date +%Y-%m-%d).html
```

## Interpreting Results

**Slowest queries** → candidates for `EXPLAIN ANALYZE` and index tuning.

**Queries by total time** = avg_time × calls → high total time with moderate avg often means N+1 queries (fix in application).

**Temp file usage** → `work_mem` may be too low for those queries; or the query plan needs an index.

**Many connections** → consider PgBouncer.

## See also

- [Monitoring](../concepts/monitoring.md) — `pg_stat_statements` for real-time profiling
- [Indexes](../concepts/indexes.md) — what to do after identifying slow queries
- [PgBouncer](pgbouncer.md) — address high connection counts flagged by pgBadger
