# Indexes

An index is a separate data structure that allows PostgreSQL to locate rows without scanning the entire table; the right index type and design can reduce query time by orders of magnitude.

## Index Types

| Type | Structure | Use case | Example |
| ---- | --------- | -------- | ------- |
| **B-tree** (default) | Sorted balanced tree | `=`, `<`, `>`, `BETWEEN`, `LIKE 'prefix%'`, `ORDER BY` | `idx_orders_created_at` |
| **Hash** | Hash table | Equality only (`=`), slightly faster than B-tree for pure equality | `CREATE INDEX … USING hash` |
| **GIN** | Inverted index | Array containment (`@>`), full-text search (`@@`), JSONB keys | `tsvector` columns |
| **GiST** | Generalised Search Tree | Geometric types, range types, full-text (alternative to GIN) | PostGIS geometries |
| **BRIN** | Block Range Index | Naturally ordered large tables (time-series, log tables); tiny size | `created_at` on append-only table |

## Scan Nodes in EXPLAIN

| Node | Analogy | When chosen |
| ---- | ------- | ----------- |
| **Seq Scan** | Read book page by page | Fetching > ~10–15 % of rows; no usable index |
| **Index Scan** | Look up index entry, jump to heap page, repeat | Few rows; index provides order for `ORDER BY … LIMIT` |
| **Bitmap Index Scan → Bitmap Heap Scan** | Collect all page numbers from index, then read pages in order | Hundreds–thousands of rows; avoids random I/O |
| **Index Only Scan** | Answer comes entirely from the index | Query needs only indexed columns; visibility map must be current |

Plan reads **bottom-up**: the innermost `→` node executes first.

## Partial Index

Indexes only rows matching a `WHERE` clause. Smaller, faster, cheaper to maintain.

```sql
-- Only index active orders (2–5 % of table)
CREATE INDEX idx_orders_active ON orders(status)
    WHERE status IN ('pending', 'processing');
```

**Limitation:** planner can only use it when the query predicate is provably within the index predicate. A parameterised query `WHERE status = $1` may not use it if the planner cannot prove `$1 ∈ {'pending','processing'}`.

## Expression (Functional) Index

Stores the result of a function. The query must use the **exact same expression**.

```sql
CREATE INDEX idx_customers_email_lower ON customers(LOWER(email));
ANALYZE customers;   -- collect stats on the expression

-- uses the index:
SELECT * FROM customers WHERE LOWER(email) = LOWER('User@Example.com');

-- does NOT use the index:
SELECT * FROM customers WHERE email = 'user@example.com';
```

For JSONB operators use double parentheses: `CREATE INDEX ON t ((data->>'key'))`.

## Composite Index — Column Order

Rule: **equality columns first, then the range column.**

```sql
-- Good: status (equality) first, created_at (range) second
CREATE INDEX idx_orders_status_created ON orders(status, created_at);

-- For: WHERE status = 'pending' AND created_at >= now() - interval '30 days'
-- → Index Scan, reads only ~150 entries
```

Reversed `(created_at, status)` forces the planner to scan all ~8 000 entries for the 30-day range, then filter by status.

## CREATE INDEX CONCURRENTLY

```sql
-- Safe for production: no write lock during build
CREATE INDEX CONCURRENTLY idx_order_items_product ON order_items(product_id);
```

- Reads the table **twice**; waits for existing transactions to finish
- Cannot run inside a transaction block
- May leave `indisvalid = false` if interrupted — check and drop/recreate if so

```sql
SELECT indexrelid::regclass, indisvalid, indisready
FROM   pg_index
WHERE  indrelid = 'order_items'::regclass;
```

## Finding Unused Indexes

```sql
SELECT s.relname, s.indexrelname,
       pg_size_pretty(pg_relation_size(s.indexrelid)) AS size,
       s.idx_scan
FROM   pg_stat_user_indexes s
JOIN   pg_index i ON i.indexrelid = s.indexrelid
WHERE  s.idx_scan = 0
  AND  NOT i.indisunique
  AND  NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = s.indexrelid)
ORDER  BY pg_relation_size(s.indexrelid) DESC;
```

On production, evaluate over several weeks (including month-end reporting cycles) before dropping.

## When Indexes Don't Help

- Fetching a large fraction of rows (> ~10–15 %) — Seq Scan is cheaper
- Very small tables (< a few hundred rows) — Seq Scan fits in one read
- Low cardinality column with uniform distribution (e.g. `status = 'delivered'` = 85 %) — partial index needed
- After a `VACUUM`/`ANALYZE`, stats may shift the planner's choice

## See also

- [WAL & MVCC](wal-mvcc.md) — `CREATE INDEX CONCURRENTLY` relies on MVCC snapshots
- [Monitoring](monitoring.md) — `pg_stat_user_indexes` for usage stats
- [Zero-Downtime Patterns](../procedures/zero-downtime.md) — `CREATE INDEX CONCURRENTLY` as a safe DDL pattern
