# Backup & Recovery

PostgreSQL offers logical backups (pg_dump) for portability and selective restore, and physical backups (pg_basebackup + WAL archiving) for fast full-cluster recovery and PITR.

## RPO and RTO

| Term | Definition | Typical target |
| ---- | ---------- | -------------- |
| **RPO** (Recovery Point Objective) | Maximum acceptable data loss (time to last good backup) | Minutes to hours |
| **RTO** (Recovery Time Objective) | Maximum acceptable downtime | Minutes to hours |

Higher backup frequency → lower RPO. Physical backups restore faster than logical → lower RTO.

## Backup Methods Comparison

| Method | Tool | Granularity | Restore speed | PITR support |
| ------ | ---- | ----------- | ------------- | ------------ |
| Logical dump | `pg_dump` | table / schema | Slow (replay SQL) | No |
| Logical globals | `pg_dumpall --globals-only` | roles, tablespaces | Fast | No |
| Physical base | `pg_basebackup` | entire cluster | Fast | Yes (with WAL) |
| WAL archiving | `archive_command` | continuous | N/A (complement) | Yes |

## pg_dump — Logical Backup

```bash
# Plain SQL (human-readable, large)
pg_dump -h localhost -U postgres -d eshop -f eshop.sql

# Custom format (compressed, supports selective restore)
pg_dump -h localhost -U postgres -d eshop -Fc -f eshop.dump

# Directory format (parallel restore possible)
pg_dump -h localhost -U postgres -d eshop -Fd -j 4 -f eshop_dir/
```

### Selective Restore

```bash
# Restore only one table
pg_restore -h localhost -U postgres -d eshop -t orders eshop.dump

# List archive contents
pg_restore --list eshop.dump
```

### pg_dumpall — Globals

Roles and tablespaces are cluster-wide; `pg_dump` does not include them.

```bash
pg_dumpall -h localhost -U postgres --globals-only -f globals.sql
```

Always restore globals first, then individual databases.

## pg_basebackup — Physical Backup

```bash
# Compressed tar format (fastest restore)
pg_basebackup -h localhost -U postgres -D /backups/base \
    --format=tar --gzip --wal-method=stream --checkpoint=fast
```

Options:
- `--wal-method=stream` — include all WAL needed during backup; safe without archiving
- `--checkpoint=fast` — force checkpoint immediately instead of waiting
- `--format=tar --gzip` — compressed archive; use `--format=plain` for a ready-to-use PGDATA copy

## WAL Archiving

Enable continuous WAL archiving so PITR is possible between base backups.

```ini
# postgresql.conf
archive_mode    = on
archive_command = 'cp %p /wal_archive/%f'   # copy each 16 MB segment when complete
```

`%p` = source path; `%f` = filename. The command must return exit code 0 only when the file is safely stored.

## PITR — Point-In-Time Recovery

Use case: accidental `DELETE` or corruption. Replay WAL up to just before the error.

### Steps

1. Stop PostgreSQL.
2. Replace `$PGDATA` with the base backup.
3. Create `$PGDATA/recovery.signal` (empty file).
4. Set `restore_command` and target in `postgresql.conf`:

```ini
restore_command         = 'cp /wal_archive/%f %p'
recovery_target_time    = '2024-10-15 14:30:00'
# or:
# recovery_target_lsn   = '0/15000000'
# recovery_target_name  = 'before_delete'
recovery_target_action  = 'promote'   # automatically promote after reaching target
```

5. Start PostgreSQL — it enters recovery mode, replays WAL, then promotes.
6. Remove `recovery.signal` (auto-deleted on promotion in PG 12+).
7. Verify data, then re-enable archiving and re-take a base backup.

### Named Restore Points

```sql
-- Before a risky operation:
SELECT pg_create_restore_point('before_big_delete');
```

Then use `recovery_target_name = 'before_big_delete'`.

## Backup Policy (3-2-1 Rule)

| Level | Frequency | Retention | Tool |
| ----- | --------- | --------- | ---- |
| Full logical | Weekly | 4 weeks | `pg_dump -Fc` |
| Globals | Daily | 2 weeks | `pg_dumpall --globals-only` |
| Full physical | Daily | 7 days | `pg_basebackup` |
| WAL archive | Continuous | Until base backup expires | `archive_command` |

3-2-1: **3** copies, on **2** different media, **1** offsite.

## Failover Runbook Reference

See [Failover Runbook](../procedures/failover-runbook.md) for the complete step-by-step PITR and replica failover procedures.

## See also

- [WAL & MVCC](wal-mvcc.md) — WAL internals and LSN
- [Replication](replication.md) — streaming replication uses same WAL stream
- [Failover Runbook](../procedures/failover-runbook.md)
