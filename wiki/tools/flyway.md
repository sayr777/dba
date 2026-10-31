# Flyway

Flyway is a database migration tool that versions SQL scripts and tracks their execution state in `flyway_schema_history`, ensuring every environment runs the same sequence of changes.

## Установка (Windows)

1. Скачайте ZIP последнего релиза Flyway CLI Community Edition:  
   https://documentation.red-gate.com/fd/command-line-184127404.html  
   (кнопка **Download** → Community → Windows ZIP)
2. Распакуйте архив в каталог без пробелов, например `C:\tools\flyway-10`.
3. Добавьте путь в системную переменную `PATH` (PowerShell от имени администратора):
   ```powershell
   [Environment]::SetEnvironmentVariable(
       "PATH",
       [Environment]::GetEnvironmentVariable("PATH","Machine") + ";C:\tools\flyway-10",
       "Machine"
   )
   ```
4. Откройте **новое** окно PowerShell и проверьте:
   ```powershell
   flyway --version
   ```
   Ожидаемый вывод: `Flyway Community Edition 10.x.x`.
5. Для работы с PostgreSQL Flyway использует JDBC-драйвер; он уже включён в ZIP-пакет.

## Naming Convention

```
V{version}__{description}.sql      ← versioned migration (run once, in order)
U{version}__{description}.sql      ← undo migration (Flyway Teams only)
R__{description}.sql               ← repeatable migration (re-runs when checksum changes)
```

- Version: `001`, `002`, … or `1.2.3`
- **Double underscore** separates version from description (single underscore = parse error)
- Description uses underscores: `V002__add_products_category.sql`

## flyway.toml

```toml
[environments.default]
url       = "jdbc:postgresql://localhost:5432/eshop"
user      = "postgres"
password  = "your_password"
locations = ["filesystem:./migrations"]

[flyway]
cleanDisabled     = true    # MUST be true in production — prevents accidental full wipe
validateOnMigrate = true    # validate checksums before applying
outOfOrder        = false   # disallow applying V003 before V002 is applied
```

## Commands

| Command | What it does |
| ------- | ------------ |
| `flyway info` | Show all migrations and their status |
| `flyway migrate` | Apply all pending migrations |
| `flyway validate` | Check all applied migrations still match their files (checksum) |
| `flyway repair` | Remove failed-migration rows and realign checksums; after that `migrate` re-runs the same version, so the file must be fixed or removed |
| `flyway baseline` | Tell Flyway "everything up to version N is already done" |
| `flyway clean` | **DROP EVERYTHING** — disabled by `cleanDisabled = true` |

## Typical Workflow

```bash
# 1. Write migration file
# migrations/V002__add_products_category.sql

# 2. Preview what will happen
flyway -configFiles=flyway.toml info

# 3. Apply
flyway -configFiles=flyway.toml migrate

# 4. Confirm
flyway -configFiles=flyway.toml info
# V002 → Success
```

## flyway_schema_history

```sql
SELECT installed_rank, version, description, type, script, checksum, success
FROM   flyway_schema_history
ORDER  BY installed_rank;
```

| Column | Meaning |
| ------ | ------- |
| `version` | Migration version string |
| `type` | SQL, JDBC, BASELINE, DELETED |
| `checksum` | CRC32 of the file contents |
| `success` | `true` = applied OK; `false` = Failed; `null` = Baseline |

## Handling Failures

If `flyway migrate` fails mid-way:

```bash
# Fix the issue (or write a new corrective migration)
# Then:
flyway -configFiles=flyway.toml repair
# Marks the Failed row as DELETED in flyway_schema_history

flyway -configFiles=flyway.toml migrate
# Applies the corrected version
```

## Baseline — Pre-existing Schema

When adopting Flyway on an existing database:

```bash
flyway -configFiles=flyway.toml baseline \
    -baselineVersion=1 \
    -baselineDescription="initial_eshop_schema"
```

This inserts a BASELINE row at version 1; all V1 files are skipped; V2+ are treated as pending.

## Repeatable Migrations

Use for views, functions, procedures — objects that can be safely replaced:

```sql
-- R__orders_summary_view.sql
CREATE OR REPLACE VIEW orders_summary AS
SELECT c.name, o.status, COUNT(*) AS cnt
FROM   customers c JOIN orders o ON o.customer_id = c.id
GROUP  BY c.name, o.status;
```

Flyway re-applies it whenever the file changes (detected by checksum).

## MR Checklist for a Migration

- [ ] File name uses **double underscore**
- [ ] `cleanDisabled = true` in flyway.toml
- [ ] `flyway validate` passes locally
- [ ] Migration Plan written: objects changed, risks, rollback SQL
- [ ] Runbook written: backup step, smoke test, rollback procedure
- [ ] DBA review completed

## See also

- [Migration Workflow](../procedures/migration-workflow.md) — full plan→deploy cycle
- [Rollback Strategies](../procedures/rollback-strategies.md) — forward rollback vs undo scripts
- [Zero-Downtime Patterns](../procedures/zero-downtime.md) — DDL patterns safe to use in migrations
- [eshop Schema](../course/eshop-schema.md) — migration history for the course project
