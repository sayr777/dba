# PgBouncer

PgBouncer is a lightweight connection pooler for PostgreSQL; it accepts application connections on its own port and multiplexes them through a small fixed pool of real PostgreSQL backend processes.

For architecture and mode comparison, see [Connection Pooling](../concepts/connection-pooling.md).

---

## Installation on Windows

> **Warning:** Installing via EnterpriseDB (EDB) Stack Builder often fails or hangs on Windows in certain regions due to CloudFront geo-blocking (`HTTP 403 Forbidden`).  
> **Recommended:** Use the official standalone binary package from GitHub Releases.

### Method 1. Official GitHub Release (Recommended)

Download and extract the official Windows 64-bit release into `C:\pgbouncer` using PowerShell:

```powershell
$zip = "$env:TEMP\pgbouncer.zip"
curl.exe -L -o $zip "https://github.com/pgbouncer/pgbouncer/releases/download/pgbouncer_1_26_1/pgbouncer-1.26.1-windows-x86_64.zip"
Expand-Archive -Path $zip -DestinationPath "$env:TEMP\pgbouncer" -Force
New-Item -ItemType Directory -Path "C:\pgbouncer" -Force
Copy-Item -Path "$env:TEMP\pgbouncer\pgbouncer-*\*" -Destination "C:\pgbouncer" -Recurse -Force
```

Verify binary and version:

```powershell
Get-ChildItem C:\pgbouncer
& "C:\pgbouncer\pgbouncer.exe" --version
```

### Method 2. Via EDB Stack Builder (Alternative)

1. Start → PostgreSQL 18 → **Application Stack Builder** (Run as Administrator).
2. Select server `PostgreSQL 18 on port 5432`.
3. **Add-ons, tools and utilities** → **pgBouncer**.
4. Enter: host `localhost`, role `postgres`, password, PG port `5432`, PgBouncer port `6432`.

Find configuration files and service if installed via EDB:

```powershell
Get-ChildItem "C:\Program Files","C:\Program Files (x86)" `
    -Recurse -Filter pgbouncer.ini -ErrorAction SilentlyContinue |
    Select-Object FullName

Get-Service *bouncer*
```

---

## Configuration: pgbouncer.ini

Create or update `C:\pgbouncer\pgbouncer.ini` via PowerShell:

```powershell
@'
[databases]
eshop = host=127.0.0.1 port=5432 dbname=eshop

[pgbouncer]
logfile              = C:\pgbouncer\pgbouncer.log
pidfile              = C:\pgbouncer\pgbouncer.pid
listen_addr          = 127.0.0.1
listen_port          = 6432
auth_type            = scram-sha-256
auth_file            = C:\pgbouncer\userlist.txt

pool_mode            = transaction
max_client_conn      = 200
default_pool_size    = 10
min_pool_size        = 2
reserve_pool_size    = 5
reserve_pool_timeout = 5

; required for JDBC drivers (DBeaver)
ignore_startup_parameters = extra_float_digits
; protocol-level prepared statements (PgBouncer 1.21+)
max_prepared_statements  = 200

log_connections      = 1
log_disconnections   = 1
admin_users          = pgbouncer_admin
'@ | Set-Content -Path "C:\pgbouncer\pgbouncer.ini" -Encoding ascii
```

### Key Parameters

| Parameter | Value | Description |
| --------- | ----- | ----------- |
| `pool_mode` | `transaction` | Server connection returned to pool after each transaction |
| `max_client_conn` | `200` | Maximum concurrent client connections accepted |
| `default_pool_size` | `10` | Real PostgreSQL backend processes per database/user pair |
| `reserve_pool_size` | `5` | Emergency backend connections when queue waits > `reserve_pool_timeout` |
| `ignore_startup_parameters` | `extra_float_digits` | Prevents JDBC startup handshake failures with DBeaver |
| `max_prepared_statements` | `200` | Enables client driver protocol-level prepared statements |

---

## Authentication: userlist.txt

PgBouncer verifies credentials before forwarding queries. It requires user records with SCRAM-SHA-256 or plain hashes.

### 1. Extract SCRAM hash from PostgreSQL

Run as `postgres` in psql or DBeaver:

```sql
SELECT format('"%s" "%s"', rolname, rolpassword) AS userlist_line
FROM   pg_authid
WHERE  rolname = 'app_backend';
```

Expected output begins with: `"app_backend" "SCRAM-SHA-256$4096:..."`.

### 2. Generate userlist.txt

Run in PowerShell:

```powershell
$dir = "C:\pgbouncer"
@(
    '"app_backend" "SCRAM-SHA-256$4096:...full-hash-from-sql-query..."'
    '"pgbouncer_admin" "admin_pass"'
) | Set-Content -Path "$dir\userlist.txt" -Encoding ascii
```

> **Critical Gotchas:**
> 1. **PowerShell BOM:** In Windows PowerShell 5.1, `-Encoding utf8` prepends a UTF-8 BOM (`EF BB BF`). PgBouncer fails to parse the first line and rejects the user (`"no such user"`). **Always use `-Encoding ascii`** or UTF-8 without BOM.
> 2. **PowerShell string interpolation:** Always enclose the hash in **single quotes** `'...'` so PowerShell does not interpret `$4096` as an empty variable.

---

## Running PgBouncer on Windows

### Option A. As a Windows Service (Administrator required)

Register and start the service:

```powershell
& "C:\pgbouncer\pgbouncer.exe" --regservice "C:\pgbouncer\pgbouncer.ini"
Start-Service pgbouncer
Get-Service pgbouncer        # Status = Running
```

To manage the service:

```powershell
Restart-Service pgbouncer    # restart
Stop-Service pgbouncer       # stop
& "C:\pgbouncer\pgbouncer.exe" --unregservice "C:\pgbouncer\pgbouncer.ini" # unregister
```

### Option B. Standalone Background Process (No Admin required)

If administrator privileges are unavailable:

```powershell
Start-Process "C:\pgbouncer\pgbouncer.exe" "C:\pgbouncer\pgbouncer.ini" -WindowStyle Hidden
Get-Process pgbouncer        # verify running process
```

To stop / restart:

```powershell
Stop-Process -Name pgbouncer -Force
Start-Process "C:\pgbouncer\pgbouncer.exe" "C:\pgbouncer\pgbouncer.ini" -WindowStyle Hidden
```

Check logs in case of startup errors:

```powershell
Get-Content "C:\pgbouncer\pgbouncer.log" -Tail 30
```

---

## Testing the Connection

```powershell
$pg = "C:\Program Files\PostgreSQL\18\bin"
$env:PGPASSWORD = "backend_pass_2024"
& "$pg\psql.exe" -h 127.0.0.1 -p 6432 -U app_backend -d eshop -c "SELECT count(*) FROM orders;"
# Expected: 200000
Remove-Item Env:PGPASSWORD
```

---

## Admin Console

Connect to the virtual `pgbouncer` management database on port 6432:

```powershell
$env:PGPASSWORD = "admin_pass"
& "$pg\psql.exe" -h 127.0.0.1 -p 6432 -U pgbouncer_admin -d pgbouncer
```

Key admin queries:

```sql
SHOW POOLS;       -- pool status per database+user (cl_active, cl_waiting, sv_active, sv_idle)
SHOW CLIENTS;     -- connected client sockets
SHOW SERVERS;     -- active PostgreSQL backend connections
SHOW STATS;       -- throughput, transaction counts, bytes sent/received
RELOAD;           -- apply pgbouncer.ini configuration changes without restarting
PAUSE;            -- wait for active transactions to complete and pause incoming queries
RESUME;           -- resume after PAUSE
```

---

## Load Testing with pgbench

Compare connection count under load:

```powershell
Set-Content -Path "$env:TEMP\select.sql" -Encoding ascii `
    -Value "SELECT count(*) FROM orders WHERE status = 'pending';"

$env:PGPASSWORD = "backend_pass_2024"

# 1. Through PgBouncer (port 6432)
& "$pg\pgbench.exe" -h 127.0.0.1 -p 6432 -U app_backend -d eshop `
    -n -c 50 -j 4 -T 30 -f "$env:TEMP\select.sql"

# 2. Direct to PostgreSQL (port 5432)
& "$pg\pgbench.exe" -h 127.0.0.1 -p 5432 -U app_backend -d eshop `
    -n -c 50 -j 4 -T 30 -f "$env:TEMP\select.sql"

Remove-Item Env:PGPASSWORD
```

Check active backends in PostgreSQL during the test (`postgres` database, port 5432):

```sql
SELECT count(*) AS backends FROM pg_stat_activity WHERE usename = 'app_backend';
```

* **Through PgBouncer:** `backends` ≤ 15 (`default_pool_size` 10 + `reserve_pool_size` 5).
* **Direct:** `backends` ≈ 50 (1 backend process per client).

---

## DBeaver Connection via PgBouncer

1. Right-click existing `eshop` connection in Database Navigator → **Duplicate Connection**.
2. Edit connection settings:
   * **Host:** `127.0.0.1`
   * **Port:** `6432` (instead of 5432)
   * **Username:** `app_backend`
   * **Password:** `backend_pass_2024`
3. Click **Test Connection ...** → should connect successfully.

---

## Transaction Mode Limitations

In `pool_mode = transaction`:
1. **`SET` statement leakage:** `SET work_mem = '64MB'` affects the server backend connection, not the client. Subsequent transactions from another client on that connection inherit the parameter. Fix: use `SET LOCAL` within a transaction block.
2. **Prepared statements:** SQL commands `PREPARE` / `EXECUTE` are session-bound and fail. Protocol-level prepared statements (JDBC, Npgsql) work if `max_prepared_statements > 0`.
3. **Session-level features disabled:** `LISTEN` / `NOTIFY`, temporary tables surviving transactions, session advisory locks (`pg_advisory_lock`).

---

## See Also

- [Connection Pooling](../concepts/connection-pooling.md) — modes, sizing formulas, transaction vs session pooling
- [Monitoring](../concepts/monitoring.md) — `pg_stat_activity` backend monitoring
- [Artifacts: PgBouncer Justification](../artifacts/pgbouncer-justification.md) — report template for Lab 07
- Official Releases: https://github.com/pgbouncer/pgbouncer/releases
