# pg_basebackup

`pg_basebackup` — утилита физического резервного копирования всего кластера PostgreSQL; создаёт двоичную копию `PGDATA`, которая используется для восстановления, PITR и инициализации реплик.

---

## 1. Что делает

- Копирует весь кластер (все базы, глобальные объекты, конфигурацию).
- Работает онлайн, без остановки сервера.
- Может сразу включить нужные WAL-сегменты (`-X stream`).
- Может создать `standby.signal` и прописать параметры репликации (`-R`).

---

## 2. Основные команды

```bash
# Физическая копия в каталог
pg_basebackup -h localhost -U replication_user \
  -D /backup/basebackup -Fp -Xs -P

# Tar + gzip
pg_basebackup -h localhost -U replication_user \
  -D /backup -Ft -z -Xs -P

# Инициализация standby
pg_basebackup -h 10.0.1.10 -U repl_user \
  -D /var/lib/postgresql/18/main \
  -Fp -Xs -P -R --slot=standby_spb_slot
```

| Флаг | Смысл |
|---|---|
| `-D` | Каталог назначения |
| `-Fp` | Plain: файловая иерархия как `PGDATA` |
| `-Ft` | Tar-архив |
| `-Xs` | Передать WAL-сегменты, нужные для консистентности |
| `-P` | Прогресс |
| `-z` | gzip (только с `-Ft`) |
| `-R` | Создать `standby.signal`, прописать `primary_conninfo` и `primary_slot_name` |
| `--slot` | Использовать слот репликации |
| `--incremental` | Инкрементальная копия по манифесту (PG 17+) |

---

## 3. Требования

```sql
CREATE ROLE replication_user REPLICATION LOGIN PASSWORD 'secret';
```

```
# pg_hba.conf
host  replication  replication_user  127.0.0.1/32  scram-sha-256
```

Роль должна иметь атрибут `REPLICATION` или быть суперпользователем.

---

## 4. Восстановление

```bash
# Остановить службу
systemctl stop postgresql

# Переименовать повреждённый каталог (не удалять)
mv /var/lib/postgresql/18/main /var/lib/postgresql/18/main_damaged

# Развернуть копию
cp -r /backup/basebackup /var/lib/postgresql/18/main

# Права
chown -R postgres:postgres /var/lib/postgresql/18/main

# Запуск (при необходимости — с recovery.signal и restore_command)
systemctl start postgresql
```

Без WAL-архива данные вернутся на момент окончания копии.

---

## 5. Инкрементальные копии (PG 17+)

Требование: `summarize_wal = on`.

```bash
pg_basebackup -h localhost -U postgres -D /backup/full -X stream -P
pg_basebackup -h localhost -U postgres -D /backup/incr1 -X stream -P \
  --incremental=/backup/full/backup_manifest

pg_combinebackup /backup/full /backup/incr1 -o /var/lib/postgresql/18/main
```

Цепочка должна быть полной: потеря любой копии делает следующие непригодными.

---

## 6. См. также

- [Резервное копирование и восстановление](../concepts/backup-recovery.md)
- [PITR](../concepts/pitr.md)
- [pg_dump](pg-dump.md)
- [Репликация](../concepts/replication.md)

---

> **Источники:** [[lec_05]], [[lec_06]], [[lec_10]], [[lab_03]], [[lab_04]]
