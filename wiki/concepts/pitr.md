# PITR (Point-In-Time Recovery)

PITR — восстановление кластера PostgreSQL на конкретный момент в прошлом путём применения WAL-сегментов к базовой физической копии; позволяет откатиться до секунды, но только при заранее настроенном архивировании WAL.

---

## 1. Что нужно до инцидента

PITR невозможно «включить» после аварии. Требования готовятся заранее:

- `wal_level = replica` (или `logical`);
- `archive_mode = on`;
- работающий `archive_command` (или `archive_library`);
- базовая копия `pg_basebackup`, завершённая до целевого момента;
- непрерывный архив WAL от этой копии до цели, без пропусков.

Проверка архивирования:

```sql
SELECT last_archived_wal, last_archived_time,
       failed_count, last_failed_wal, stats_reset
FROM   pg_stat_archiver;
```

`failed_count > 0` означает, что архив неполный.

---

## 2. Ограничение: весь кластер

PITR откатывает **весь кластер**, включая все базы. Нельзя восстановить одну таблицу.

Поэтому при логической ошибке (`DELETE`, `DROP`, плохая миграция):

1. Поднять отдельный экземпляр на копии (другой порт, например 5433).
2. Применить WAL до момента до ошибки.
3. Проверить данные.
4. Выгрузить нужные строки и загрузить в production.
5. Остановить временный экземпляр.

Production при этом продолжает работать.

---

## 3. Параметры цели

| Параметр | Смысл |
|---|---|
| `recovery_target_time` | Момент времени (указывать с часовым поясом) |
| `recovery_target_lsn` | Позиция в WAL |
| `recovery_target_xid` | Номер транзакции |
| `recovery_target_name` | Именованная точка (`pg_create_restore_point`) |
| `recovery_target_inclusive` | Включать ли целевую транзакцию |
| `recovery_target_timeline` | Линия времени (`latest` по умолчанию) |
| `recovery_target_action` | `pause`, `promote`, `shutdown` |

Без `recovery_target_*` сервер применит весь архив — это режим восстановления после отказа диска, а не откат в прошлое.

---

## 4. Поиск точной точки через pg_waldump

```bash
pg_waldump -p /backup/wal_archive \
  000000010000000000000005 000000010000000000000007 | grep "COMMIT.*rels"
```

Пример:

```text
rmgr: Transaction ... lsn: 0/05A3B2C8 ... desc: COMMIT 2024-09-01 14:31:02 MSK; rels: base/16384/16390
```

Остановка перед этой транзакцией:

```ini
recovery_target_lsn       = '0/05A3B2C8'
recovery_target_inclusive = off
```

---

## 5. Минимальная процедура (Linux-подобная схема)

```bash
# 1. Развернуть базовую копию
cp -r /backup/basebackup /var/lib/postgresql/18/pitr

# 2. Создать сигнал recovery
touch /var/lib/postgresql/18/pitr/recovery.signal

# 3. Параметры
cat >> /var/lib/postgresql/18/pitr/postgresql.auto.conf <<'EOF'
port = 5433
archive_mode = off
restore_command = 'cp /backup/wal_archive/%f %p'
recovery_target_time = '2024-09-01 14:30:00+03'
recovery_target_action = 'pause'
EOF

# 4. Запустить
pg_ctl -D /var/lib/postgresql/18/pitr start

# 5. Проверить
psql -p 5433 -c "SELECT pg_is_in_recovery(), pg_last_xact_replay_timestamp();"
```

> В Windows пути и `restore_command` отличаются; используйте `copy` и двойные `\\` в конфиге. Полная процедура — в лекции 6.

---

## 6. Обязательные правила

- `archive_mode = off` на отдельном экземпляре, иначе он запишет WAL новой timeline в боевой архив.
- Указывать часовой пояс в `recovery_target_time`.
- `recovery_target_action = 'pause'` для проверки данных; `promote` — если экземпляр станет рабочим.
- После promotion удалить `recovery_target_*` и `restore_command`, включить `archive_mode = on`, снять новый `pg_basebackup`.
- Проверять PITR на стенде регулярно.

---

## 7. См. также

- [Резервное копирование и восстановление](backup-recovery.md)
- [WAL и MVCC](wal-mvcc.md)
- [pg_basebackup](../tools/pg-basebackup.md)
- [Стратегии отката](../procedures/rollback-strategies.md)
- [Failover Runbook](../artifacts/failover-runbook.md)

---

> **Источники:** [[lec_06]], [[lec_13]], [[lab_04]]
