# pg_dump

`pg_dump` — утилита логического резервного копирования одной базы PostgreSQL; создаёт SQL-скрипт или бинарный архив, из которого можно воссоздать схему и данные.

---

## 1. Что делает

- Подключается к работающему серверу и делает согласованный снимок одной базы.
- Не останавливает сервер.
- Не включает роли, табличные пространства и другие объекты уровня кластера.
- Может выгружать только схему, только данные или отдельные таблицы.

---

## 2. Форматы

| Формат | Флаг | Особенности |
|---|---|---|
| Plain SQL | `-Fp` | Текст; восстанавливается через `psql` |
| Custom | `-Fc` | Сжатый бинарный; выборочное восстановление, параллельный `pg_restore -j` |
| Directory | `-Fd` | Папка; параллельный дамп `-j N`, удобно для больших баз |
| Tar | `-Ft` | Tar-архив; менее гибкий |

Рекомендация: `-Fc` для большинства случаев, `-Fd -j` — для больших баз.

---

## 3. Основные команды

```bash
# Полная база в custom-формате
pg_dump -h localhost -U postgres -Fc eshop -f eshop_20240901.dump

# Только схема
pg_dump -h localhost -U postgres --schema-only eshop -f schema.sql

# Только данные
pg_dump -h localhost -U postgres --data-only eshop -f data.sql

# Одна таблица
pg_dump -h localhost -U postgres -t orders eshop -f orders.sql

# Исключить таблицу
pg_dump -h localhost -U postgres --exclude-table=audit_log eshop -f noaudit.dump

# Параллельно в directory-формат
pg_dump -h localhost -U postgres -Fd -j 4 eshop -f eshop_dir/
```

### Полезные флаги

| Флаг | Смысл |
|---|---|
| `-n schema` | Только указанная схема |
| `-t table` | Только указанная таблица |
| `--inserts` | Генерировать `INSERT` вместо `COPY` (медленнее) |
| `--column-inserts` | `INSERT` с именами колонок |
| `--no-owner` | Не восстанавливать владельцев |
| `--no-privileges` | Не выгружать `GRANT`/`REVOKE` |
| `--with-statistics` | Выгрузить статистику планировщика (PG 18) |

---

## 4. Ограничения

- Не содержит роли и пароли → нужен `pg_dumpall --globals-only`.
- Не содержит табличные пространства.
- Не является основой для PITR.
- Восстановление большой базы медленное: индексы строятся заново.
- Дамп фиксирует состояние на момент старта, а не «непрерывную копию».

---

## 5. Проверка дампа

```bash
# Список объектов в дампе
pg_restore --list eshop_20240901.dump

# Восстановление в тестовую базу
createdb eshop_restore_test
pg_restore -d eshop_restore_test -Fc eshop_20240901.dump

# Сверка
psql -d eshop_restore_test -c "SELECT count(*) FROM orders;"
```

> `pg_restore --list` показывает оглавление, но не гарантирует, что данные читаются. Полная проверка — только восстановление.

---

## 6. Типичные ошибки

| Ошибка | Причина | Решение |
|---|---|---|
| `role "app_user" does not exist` | Не восстановлены глобальные объекты | `pg_dumpall --globals-only` + `psql -f` |
| `database already exists` | `pg_restore -C` в существующую базу | `--clean --if-exists` или `dropdb` |
| `duplicate key` | Данные уже есть | Восстанавливать в пустую базу |
| `invalid byte sequence` | Файл в UTF-16 (PowerShell `>`) | Использовать `-f`, а не `>` |

---

## 7. См. также

- [Резервное копирование и восстановление](../concepts/backup-recovery.md)
- [PITR](../concepts/pitr.md)
- [pg_basebackup](pg-basebackup.md)
- [Регламент бэкапов](../artifacts/backup-policy.md)

---

> **Источники:** [[lec_05]], [[lec_06]], [[lab_03]], [[lab_04]]
