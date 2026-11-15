# Failover Runbook

A failover runbook documents who does what step-by-step when the primary PostgreSQL server fails; DBA executes technical steps while the System Analyst handles communication and verification.

## Roles During an Incident

| Role | Responsibility |
| ---- | -------------- |
| **DBA** | All PostgreSQL commands: promote standby, verify replication, re-configure application |
| **System Analyst (SA)** | Monitor dashboards, notify stakeholders, verify business-level functionality after recovery |
| **On-call lead** | Declare incident, assign roles, approve destructive actions |

## Scenario A — Planned Switchover (Maintenance)

Use when: scheduled maintenance, hardware replacement, version upgrade.

```
DBA:
1. Confirm standby is in sync
   pg_primary> SELECT client_addr, write_lag, flush_lag, replay_lag FROM pg_stat_replication;
   -- All lag values should be 0 or near-zero

2. Notify stakeholders (SA sends message)
   SA: "Planned switchover begins at HH:MM. Expect 30–60 s downtime."

3. Stop writes to primary (application maintenance mode or stop app)
   SA: coordinate with app team

4. Wait for standby to catch up
   pg_primary> SELECT pg_current_wal_lsn();
   pg_standby> SELECT pg_last_wal_replay_lsn();
   -- Must match

5. Promote standby
   pg_standby> pg_ctl promote -D $PGDATA
   -- OR with Patroni:
   -- patronictl -c /etc/patroni.yml switchover <cluster>

6. Verify new primary accepts writes
   new_primary> SELECT pg_is_in_recovery();  -- must return false

7. Reconfigure old primary as new standby
   old_primary: touch $PGDATA/standby.signal
   old_primary: set primary_conninfo to new primary in postgresql.conf
   old_primary: start PostgreSQL

8. Update application connection strings to new primary

9. Re-enable application
   SA: verify application health, notify stakeholders
```

## Scenario B — Unplanned Failover (Primary Crash)

Use when: primary server is unreachable or crashed.

```
DBA:
1. Confirm primary is truly dead (not a network partition)
   - Attempt direct connection to primary: timeout
   - Check server status via OOB console or hypervisor
   - Check pg_stat_replication was active recently

2. DECISION POINT: authorise failover
   On-call lead: "Confirmed primary unreachable for > 2 min. Authorise failover."

3. Check standby replication state
   pg_standby> SELECT pg_last_wal_replay_lsn(), pg_is_in_recovery();
   -- Note LSN — any unconfirmed WAL on crashed primary may be lost (RPO window)

4. Promote standby
   pg_standby> pg_ctl promote -D $PGDATA
   -- OR with Patroni: Patroni detects this automatically

5. Verify promotion
   new_primary> SELECT pg_is_in_recovery();  -- false

6. Update DNS or load balancer to point to new primary
   -- Or update connection strings in application config

7. Re-enable application
   SA: smoke test — can users log in, create orders?

8. Document data loss (if any)
   DBA: compare LSN from step 3 with last known write
   SA: identify affected transactions, notify business

9. Repair old primary
   - Fix hardware/OS issue on old primary server
   - Re-initialise as standby via pg_basebackup
   - Configure primary_conninfo to new primary
   - Start PostgreSQL in standby mode
```

## Scenario C — PITR Recovery (Accidental Data Deletion)

Use when: `DELETE FROM orders WHERE ...` ran without a `WHERE`, or data was corrupted.

```
DBA:
1. Immediately stop the application to prevent further writes

2. Identify the exact time of the bad transaction
   pg_primary> SELECT * FROM pg_stat_activity ORDER BY query_start DESC LIMIT 10;
   -- Or check pgAudit logs / application logs for timestamp

3. Take immediate backup of current state (evidence + fallback)
   pg_dump -Fc eshop -f eshop_pre_restore_$(date +%Y%m%d_%H%M%S).dump

4. Stop PostgreSQL

5. Replace PGDATA with last good base backup
   cp -a /backups/base/* $PGDATA/

6. Configure recovery.signal and recovery target
   touch $PGDATA/recovery.signal

   In postgresql.conf:
   restore_command       = 'cp /wal_archive/%f %p'
   recovery_target_time  = '2024-10-15 14:29:00'  ← 1 min before incident
   recovery_target_action = 'promote'

7. Start PostgreSQL and monitor recovery
   tail -f $PGDATA/log/postgresql-*.log
   -- Watch for "recovery stopping before commit"

8. Verify data restored
   SELECT count(*) FROM orders;  -- compare with expected count

9. Re-enable application
   SA: verify business data, notify stakeholders of recovery outcome

10. Re-take base backup and re-enable WAL archiving
    ALTER SYSTEM RESET restore_command;
    ALTER SYSTEM SET archive_mode = 'on';
    -- Restart PostgreSQL
```

## Communication Templates

### Initial alert (SA)
```
[INCIDENT] PostgreSQL primary unresponsive since HH:MM.
DBA is investigating. Application may experience errors.
Next update in 10 min.
```

### During failover (SA)
```
[INCIDENT UPDATE] Failover to standby in progress.
Estimated downtime: 1–2 min. Do not retry failed transactions.
```

### Recovery complete (SA)
```
[INCIDENT RESOLVED] Database restored at HH:MM.
Data loss: [none / transactions from HH:MM to HH:MM].
Root cause analysis to follow.
```

## See also

- [Patroni](../tools/patroni.md) — HA-оркестратор и автоматический failover
- [High Availability](../concepts/high-availability.md) — SLA, MTBF, MTTR, кворум и split-brain
- [Backup & Recovery](../concepts/backup-recovery.md) — PITR setup and WAL archiving
- [Replication](../concepts/replication.md) — streaming replication, Patroni architecture
- [DBA vs SA](../roles/dba-vs-sa.md) — role responsibilities during incidents
- [РПД дисциплины](../course/rpd.md) — связь с индикатором ПК-1-И-40
