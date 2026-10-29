# DBeaver

DBeaver is the cross-platform GUI client used throughout the course for SQL editing, EXPLAIN visualisation, ERD generation, and data exploration; knowing its quirks prevents confusing errors in labs.

## Connecting to PostgreSQL

1. **Database** → **New Database Connection** → PostgreSQL
2. Enter: Host `localhost`, Port `5432`, Database `eshop`, User `postgres`, Password
3. Test Connection → OK → Finish

### Connecting via PgBouncer

Create a second connection, identical but with Port `6432` and User `app_backend`.

## Auto-Commit Mode

**Always verify Auto-Commit before running DDL or VACUUM.**

Toggle: right-click the connection button at the top → **Auto-commit**

Or: check the Transaction Mode button in the SQL Editor toolbar (should show **Auto** not **Manual**).

**Why it matters:**
- `VACUUM` and `CREATE INDEX CONCURRENTLY` **cannot run inside a transaction block**
- DBeaver's **Smart commit mode** auto-switches to Manual Commit after the first `UPDATE`
- Symptom: `ERROR: VACUUM cannot run inside a transaction block`
- Fix: **Rollback** → switch to **Auto-Commit** → retry

> Disable Smart commit mode: Connection settings → Transaction → uncheck "Smart commit mode".

## Running EXPLAIN

Use `Ctrl+Enter` to execute `EXPLAIN (ANALYZE, BUFFERS)`, not the "Explain execution plan" toolbar button.

The toolbar button uses an internal API that strips `Execution Time` and `Buffers` from the output — you lose the most important numbers.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE status = 'pending';
```

## Reading EXPLAIN Output

Plan reads **bottom-up** — the deepest indented node executes first.

```
Bitmap Heap Scan on orders  (cost=42..1234 rows=3900 width=64)
                             ← step 2: fetch heap pages by page list
  Heap Blocks: exact=1639
  ->  Bitmap Index Scan on idx_orders_active  (cost=0..41 rows=3900 width=0)
                                              ← step 1: build page list from index
        Buffers: shared hit=6
Planning Time: 0.3 ms
Execution Time: 8.7 ms
```

Key numbers: `Execution Time`, `Buffers: shared hit/read`, `Rows Removed by Filter`, `loops`.

## ERD Generation

Right-click the schema in Database Navigator → **View diagram** (or **ER Diagram** tab).

DBeaver generates a Crow's Foot ERD from the live database schema. Use it to verify foreign keys and cardinalities after each lab.

## Useful Shortcuts

| Shortcut | Action |
| -------- | ------ |
| `Ctrl+Enter` | Execute current statement |
| `Alt+X` | Execute entire script |
| `Ctrl+Shift+F` | Format SQL |
| `Ctrl+/` | Comment/uncomment lines |
| `F5` | Refresh object tree |

## psql Alternative (PowerShell)

DBeaver doesn't connect to the PgBouncer admin console (`pgbouncer` database). Use psql:

```powershell
$pg = "C:\Program Files\PostgreSQL\18\bin"
& "$pg\psql.exe" -h 127.0.0.1 -p 6432 -U pgbouncer_admin -d pgbouncer
```

Also needed for `vacuumdb`, `pgbench`, `pg_dump`, `pg_basebackup`.

## See also

- [PgBouncer](pgbouncer.md) — creating a second DBeaver connection on port 6432
- [Monitoring](../concepts/monitoring.md) — running `pg_stat_activity` queries in DBeaver
- [Indexes](../concepts/indexes.md) — reading EXPLAIN ANALYZE plans
