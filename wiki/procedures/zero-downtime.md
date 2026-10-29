# Zero-Downtime Patterns

In production, schema changes must not block reads or writes; three DDL operations are dangerous without special care: adding a NOT NULL column, renaming a column, and creating an index.

## Why These Operations Are Dangerous

| Operation | Risk | Duration of lock |
| --------- | ---- | ---------------- |
| `ALTER TABLE ADD COLUMN NOT NULL` (without DEFAULT) | `AccessExclusiveLock` while scanning all rows to verify constraint | Table size × I/O speed |
| `ALTER TABLE RENAME COLUMN` | `AccessExclusiveLock`; application code breaks if it hardcodes the old name | Brief, but deploy must be atomic |
| `CREATE INDEX` | `ShareLock` — readers allowed, but all writes block | Index build time |

## Pattern 1 — ADD NOT NULL Column (3 steps)

**Goal:** add `orders.confirmed_at TIMESTAMPTZ NOT NULL`

```sql
-- Step 1: add with DEFAULT — metadata-only in PG 11+ (instant, no lock on rows)
ALTER TABLE orders ADD COLUMN confirmed_at TIMESTAMPTZ DEFAULT now();

-- Step 2: backfill existing rows (in batches on very large tables)
UPDATE orders SET confirmed_at = created_at WHERE confirmed_at IS NULL;

-- Step 3: enforce NOT NULL (fast — all rows already have a value)
ALTER TABLE orders ALTER COLUMN confirmed_at SET NOT NULL;
ALTER TABLE orders ALTER COLUMN confirmed_at DROP DEFAULT;
```

**Why 3 steps?**
- In PG 10 and earlier, `ADD COLUMN NOT NULL DEFAULT` had to scan the entire table to write the default to every row under `AccessExclusiveLock`.
- In PG 11+, PostgreSQL stores the default in the system catalog and reads it virtually — so a single `ADD COLUMN NOT NULL DEFAULT` is instant. The 3-step pattern is still safer when you need explicit control over the fill process (e.g. batch updates to avoid long transactions).

## Pattern 2 — RENAME COLUMN (4 steps, 2 releases)

**Goal:** rename `customers.name` → `customers.full_name`

**Release 1** — add new column, fill it, keep both:

```sql
-- Step 1: add new column
ALTER TABLE customers ADD COLUMN full_name TEXT;

-- Step 2: fill from old column
UPDATE customers SET full_name = name;

-- Step 3: set NOT NULL on new column
ALTER TABLE customers ALTER COLUMN full_name SET NOT NULL;
```

Deploy application code that writes to **both** `name` and `full_name`, and reads from `full_name`.

**Release 2** — drop old column (after all instances are updated):

```sql
-- Step 4: drop old column
ALTER TABLE customers DROP COLUMN name;
```

Why two releases? Between Release 1 and Release 2, both columns exist simultaneously. Old application versions (before rollout is complete) still write to `name`; new versions write `full_name`. Dropping `name` in the same release as adding `full_name` would break old instances still running.

## Pattern 3 — CREATE INDEX CONCURRENTLY

```sql
-- Safe: does not block writes
CREATE INDEX CONCURRENTLY idx_orders_total_amount ON orders(total_amount DESC);
```

vs.

```sql
-- Dangerous: ShareLock blocks all writes until index is built
CREATE INDEX idx_orders_total_amount ON orders(total_amount DESC);
```

### Verifying the Index

```sql
SELECT c.relname, i.indisvalid, i.indisready
FROM   pg_index i
JOIN   pg_class c ON c.oid = i.indexrelid
WHERE  i.indrelid = 'orders'::regclass
  AND  c.relname = 'idx_orders_total_amount';
-- indisvalid must be true
```

If `indisvalid = false` (build was interrupted):

```sql
DROP INDEX CONCURRENTLY idx_orders_total_amount;
-- then recreate
CREATE INDEX CONCURRENTLY idx_orders_total_amount ON orders(total_amount DESC);
```

## Pattern 4 — DROP TABLE (3 releases)

Never drop a table in the same release as removing its last reference from application code.

| Release | Action |
| ------- | ------ |
| 1 | Rename table to `_old_table_name`; update app to not read it |
| 2 | Remove all foreign keys referencing the table |
| 3 | `DROP TABLE _old_table_name` |

## Full Comparison

| Operation | Dangerous way | Zero-downtime way | Lock held |
| --------- | ------------- | ----------------- | --------- |
| ADD NOT NULL column | `ALTER TABLE ADD COLUMN … NOT NULL` | ADD + UPDATE + SET NOT NULL (3 steps) | None (each step is brief) |
| Rename column | `ALTER TABLE RENAME COLUMN` | ADD + FILL + NOT NULL + DROP (2 releases) | Brief per-step |
| Create index | `CREATE INDEX` | `CREATE INDEX CONCURRENTLY` | None for writes |
| Drop table | `DROP TABLE` | RENAME → remove FK → DROP (3 releases) | None during traffic |
| Change column type | `ALTER COLUMN TYPE` | ADD new + migrate + DROP old | Controlled per step |

## Flyway Integration

Each step should be a separate migration file, or at minimum clearly commented:

```sql
-- V007__add_confirmed_at_safe.sql
-- Step 1: add with default (instant in PG 11+)
ALTER TABLE orders ADD COLUMN confirmed_at TIMESTAMPTZ DEFAULT now();

-- Step 2: backfill
UPDATE orders SET confirmed_at = created_at WHERE confirmed_at IS NULL;

-- Step 3: enforce NOT NULL
ALTER TABLE orders ALTER COLUMN confirmed_at SET NOT NULL;
ALTER TABLE orders ALTER COLUMN confirmed_at DROP DEFAULT;
```

## See also

- [Locks & Concurrency](../concepts/locks-concurrency.md) — table and row lock modes, Lock Queue, lock_timeout
- [Rollback Strategies](rollback-strategies.md) — what to do when a migration goes wrong
- [Migration Workflow](migration-workflow.md) — full deployment cycle
- [Indexes](../concepts/indexes.md) — `CREATE INDEX CONCURRENTLY` details
- [РПД дисциплины](../course/rpd.md) — соответствие индикаторам ПК-1-И-17 и ПК-3-И-3
