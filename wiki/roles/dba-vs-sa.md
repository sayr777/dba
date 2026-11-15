# DBA vs System Analyst

In the course, every lab has two participant tracks: the DBA executes all PostgreSQL administration tasks, while the System Analyst understands why each task matters and participates in decision-making, communication, and validation.

## Competency Map

| Competency | Code | Primary owner |
| ---------- | ---- | ------------- |
| Administers database systems | ОПК-2 | DBA |
| Applies professional standards | ОПК-3 | DBA + SA |
| Documents technical decisions | ОПК-5 | SA |
| Designs database architecture | ПК-1 | DBA |
| Maintains system performance | ПК-2 | DBA + SA |

## Responsibility Matrix by Topic

### Architecture & Installation (Week 1–2)

| Task | DBA | SA |
| ---- | --- | -- |
| Install PostgreSQL | Executes | Documents config decisions |
| Set postgresql.conf parameters | Decides + sets | Understands impact (memory, connections) |
| Design ERD | Collaborates | Validates against business requirements |
| Define normalization levels | Decides | Approves from business perspective |

### Roles & Privileges (Week 3–4)

| Task | DBA | SA |
| ---- | --- | -- |
| Create roles and grant privileges | Executes | Defines access requirements |
| Configure pg_hba.conf | Executes | Reviews security policy |
| Enable and configure RLS | Executes | Specifies data isolation rules |
| Respond to access request | Executes | Initiates request using template |

### Backup & Recovery (Week 5–6)

| Task | DBA | SA |
| ---- | --- | -- |
| Define RPO / RTO | Recommends | Approves based on business impact |
| Configure WAL archiving | Executes | Understands retention implications |
| Execute pg_dump schedule | Configures + monitors | Verifies backup policy compliance |
| Perform PITR | Executes | Identifies target time, approves data loss scope |
| Failover decision | Recommends | Approves (with on-call lead) |

### Monitoring (Week 7–8)

| Task | DBA | SA |
| ---- | --- | -- |
| Set alert thresholds | Configures | Reviews against SLA requirements |
| Investigate blocking queries | Diagnoses + resolves | Reports user-facing symptoms |
| Optimise slow queries | Executes (EXPLAIN, indexes) | Identifies which queries matter to business |
| Read pgBadger report | Interprets | Acts on top slow queries list |

### Indexes & Autovacuum (Week 9)

| Task | DBA | SA |
| ---- | --- | -- |
| Design index strategy | Decides | Reviews query patterns with DBA |
| Monitor autovacuum | Observes + tunes | Understands why dead tuples hurt performance |
| Install PgBouncer | Executes | Reviews connection limits vs user count |
| Write PgBouncer justification | Writes | Reviews business case |

### Security & Compliance (Week 11)

| Task | DBA | SA |
| ---- | --- | -- |
| Configure pgAudit | Executes | Defines what must be audited |
| Enable TLS | Executes | Verifies encryption policy compliance |
| Classify personal data (152-ФЗ) | Advises | **Primary owner** — legal responsibility |
| Complete IB checklist | Executes technical items | Signs off on organisational items |

### Migrations (Week 12–13)

| Task | DBA | SA |
| ---- | --- | -- |
| Write migration SQL | Primary author | Reviews intent, provides rollback window |
| Write Migration Plan | Collaborates | Approves risk assessment |
| Write Runbook | Primary author | Reviews and approves |
| Communicate during deploy | Executes | Sends team notifications |
| Zero-downtime decision | Decides | Confirms acceptable downtime budget |

## The Role Request Template (from lab 02)

When a developer or analyst needs database access, they request it from the DBA using a structured form:

```
Role request:
  Requestor: analyst_ivanova
  Database: eshop
  Required access: SELECT on customers, orders
  Purpose: monthly sales report
  Duration: permanent
  Approver: project manager
```

The DBA evaluates the request, applies the principle of least privilege, and responds with the granted role.

## Key Principles

**DBA:** applies technical solutions, owns configuration, ensures SLA.

**SA:** owns requirements and business context, escalates, communicates to stakeholders, validates business outcomes after recovery.

Neither role acts alone on high-risk operations (failover, DROP TABLE, PITR) — approval from both is required.

## See also

- [Security](../concepts/security.md) — role model, RLS, pg_hba.conf configuration
- [Failover Runbook](../procedures/failover-runbook.md) — DBA and SA tasks during incidents
- [Migration Workflow](../procedures/migration-workflow.md) — collaborative approval process
