# Connection Pooling

Each PostgreSQL backend is an OS process (5–10 MB); at 50+ concurrent clients, a connection pooler like PgBouncer multiplexes many clients through a small fixed pool, protecting the database from connection exhaustion.

## Why Pool Connections

| Without pooler | With PgBouncer (transaction mode) |
| -------------- | --------------------------------- |
| 1 client = 1 backend process | 1 client = shared backend from pool |
| 50 clients → 50 × 8 MB = 400 MB | 50 clients → 10 backends × 8 MB = 80 MB |
| `max_connections` hit → connection refused | Queue and wait in PgBouncer |
| Backend overhead per query | Near-zero overhead for short transactions |

## PgBouncer Architecture

```
                 ┌────────────────────────────────┐
 App :3000 ──┐   │         PgBouncer :6432         │
 App :3001 ──┼──►│  max_client_conn = 200          │
 App :3002 ──┘   │  pool_mode = transaction        │
                 └────────────┬───────────────────┘
                              │ default_pool_size = 10
                              ▼
                 ┌────────────────────────────────┐
                 │       PostgreSQL :5432          │
                 │  backends: up to 10 + 5 reserve│
                 └────────────────────────────────┘
```

## Pool Modes

| Mode | When connection returns to pool | What works | What doesn't work |
| ---- | ------------------------------- | ---------- | ----------------- |
| **session** | Client disconnects | Everything | Poor multiplexing |
| **transaction** | `COMMIT` / `ROLLBACK` | Most things | `PREPARE/EXECUTE`, `SET` (leaks), `LISTEN/NOTIFY`, session advisory locks, temp tables outside transaction |
| **statement** | Each statement | Simple queries only | Transactions, almost everything |

**Recommended for OLTP:** `transaction` mode.

## Key pgbouncer.ini Parameters

```ini
[databases]
eshop = host=127.0.0.1 port=5432 dbname=eshop

[pgbouncer]
listen_addr              = 127.0.0.1
listen_port              = 6432
auth_type                = scram-sha-256
auth_file                = /etc/pgbouncer/userlist.txt

pool_mode                = transaction
max_client_conn          = 200     # max clients connecting to PgBouncer
default_pool_size        = 10      # backends per db+user pair
min_pool_size            = 2       # keep alive even when idle
reserve_pool_size        = 5       # extra backends if cl_waiting > 0
reserve_pool_timeout     = 5       # seconds before reserve kicks in

ignore_startup_parameters = extra_float_digits   # needed for JDBC/DBeaver
max_prepared_statements  = 200     # protocol-level prepared statements (PgBouncer 1.21+)

log_connections          = 1
log_disconnections       = 1
admin_users              = pgbouncer_admin
```

## userlist.txt

PgBouncer authenticates clients itself; it needs SCRAM hashes:

```sql
-- Get SCRAM hash for a role
SELECT format('"%s" "%s"', rolname, rolpassword)
FROM   pg_authid
WHERE  rolname = 'app_backend';
```

```
# userlist.txt (ASCII encoding — NOT UTF-8 BOM)
"app_backend" "SCRAM-SHA-256$4096:..."
"pgbouncer_admin" "admin_pass"
```

## Administrative Console

```bash
psql -h 127.0.0.1 -p 6432 -U pgbouncer_admin -d pgbouncer
```

```sql
SHOW POOLS;     -- cl_active, cl_waiting, sv_active, sv_idle
SHOW CLIENTS;   -- connected clients
SHOW SERVERS;   -- backend connections to PostgreSQL
SHOW STATS;     -- total_xact_count, total_query_count
RELOAD;         -- reload pgbouncer.ini without restart
```

Column meanings in `SHOW POOLS`:
| Column | Meaning |
| ------ | ------- |
| `cl_active` | Clients currently executing a query |
| `cl_waiting` | Clients waiting for a free server connection |
| `sv_active` | Backends busy with a client request |
| `sv_idle` | Backends idle and ready |

## transaction mode Limitations (Lab 7 experiments)

### SET leaks between clients

```sql
-- Client 1
SET work_mem = '64MB';      -- sets on the server connection

-- Client 2 (may get the same server connection next transaction)
SHOW work_mem;              -- '64MB' ← leaked from Client 1
```

Fix: always use `SET LOCAL` inside a transaction; it reverts on commit.

### SQL PREPARE / EXECUTE fails

```sql
-- Client 1
PREPARE q(int) AS SELECT * FROM orders WHERE id = $1;
-- Connection returns to pool

-- Client 2 gets same backend
EXECUTE q(1);
-- ERROR: prepared statement "q" does not exist
```

Fix: use protocol-level prepared statements from your driver (JDBC, psycopg, Npgsql) — PgBouncer 1.21+ handles these automatically via `max_prepared_statements`.

### Other unsupported in transaction mode

- `LISTEN` / `NOTIFY`
- `pg_advisory_lock` (session-level)
- Temporary tables that outlive a transaction

## Capacity Planning Formula

```
required_pool_size = (queries_per_second × avg_query_duration_seconds) + headroom
```

Example: 500 qps, 20 ms avg → 500 × 0.02 = 10 backends + 20 % headroom = 12 backends.

## See also

- [PostgreSQL Architecture](postgresql-architecture.md) — why each connection = one backend process
- [Monitoring](monitoring.md) — `SHOW POOLS` and `pg_stat_activity`
- [Security](security.md) — PgBouncer uses scram-sha-256 matching PostgreSQL
- [PgBouncer tool page](../tools/pgbouncer.md) — installation and Windows-specific setup
