# Лекция 6. Восстановление, PITR, отработка сбоев

**Неделя:** 6

---

## Цель лекции

По итогам лекции студент:

- знает типовые сценарии потери данных и соответствующие методы восстановления;
- умеет описать процедуру восстановления из логического и физического дампа;
- понимает механизм PITR и умеет описать условия его применения;
- знает, как оформить регламент восстановления (failover runbook) для DBA.

---

## 1. Сценарии потери данных

Прежде чем выбирать метод восстановления, нужно понять причину:

| Сценарий                                        | Что пострадало             | Метод восстановления                    |
|-------------------------------------------------|----------------------------|-----------------------------------------|
| Случайный `DELETE` без `WHERE`                  | Данные в таблице           | PITR или восстановление из логического дампа |
| `DROP TABLE` / `DROP DATABASE`                  | Схема + данные             | PITR или полный pg_restore              |
| Плохая миграция (`UPDATE` с неверным условием)  | Данные в нескольких строках | PITR (если нет forward rollback)        |
| Отказ диска / повреждение файловой системы      | Весь PGDATA                | pg_basebackup + WAL-архив (PITR)        |
| Аппаратный сбой (полная потеря сервера)         | Всё                        | pg_basebackup + WAL-архив; failover на реплику |

> **Первый вопрос при инциденте:** «Когда была последняя заведомо корректная точка?» — это определяет RPO и метод восстановления.

---

## 2. Восстановление из логического дампа

### 2.1. Восстановление всей базы (custom-формат)

```bash
# Создать базу-приёмник
createdb -h localhost -U postgres myapp_restored

# Восстановить из custom-дампа
pg_restore -h localhost -U postgres \
  -d myapp_restored \
  -Fc myapp_prod_20240901.dump \
  --verbose

# Параллельное восстановление
pg_restore -h localhost -U postgres \
  -d myapp_restored \
  -Fc myapp_prod_20240901.dump \
  -j 4 --verbose
```

### 2.2. Выборочное восстановление

```bash
# Только одна таблица
pg_restore -h localhost -U postgres \
  -d myapp_prod -t orders \
  myapp_prod_20240901.dump

# Только схема (без данных)
pg_restore -h localhost -U postgres \
  -d myapp_restored --schema-only \
  myapp_prod_20240901.dump

# Просмотр объектов в дампе
pg_restore --list myapp_prod_20240901.dump | grep -i "TABLE DATA"
```

### 2.3. Типичные ошибки при восстановлении

| Ошибка                                          | Причина                                   | Решение                                   |
|-------------------------------------------------|-------------------------------------------|-------------------------------------------|
| `role "app_user" does not exist`                | Роли не восстановлены                     | Сначала `psql -f globals.sql`             |
| `database already exists`                       | База есть, а в дампе `CREATE DATABASE`    | `dropdb` или флаг `--clean`               |
| `duplicate key value violates unique constraint`| Данные уже есть в таблице                 | Использовать `--clean` или пустую базу    |
| Медленное восстановление                        | Индексы строятся построчно                | `-j 4` для параллельного восстановления   |

---

## 3. Восстановление из физической копии (pg_basebackup)

Физическое восстановление заменяет весь PGDATA:

```bash
# 1. Остановить сервер
pg_ctl stop -D /var/lib/postgresql/17/main -m fast

# 2. Переименовать (не удалять!) текущий PGDATA
mv /var/lib/postgresql/17/main /var/lib/postgresql/17/main_damaged

# 3. Восстановить (directory-формат)
cp -a /backup/basebackup/ /var/lib/postgresql/17/main/

# 4. Установить права
chown -R postgres:postgres /var/lib/postgresql/17/main
chmod 700 /var/lib/postgresql/17/main

# 5. Запустить сервер
pg_ctl start -D /var/lib/postgresql/17/main
```

---

## 4. Point-in-Time Recovery (PITR)

PITR позволяет восстановить базу **на конкретный момент времени** — например, за 1 минуту до случайного `DROP TABLE`.

### 4.1. Требования

- Включён `archive_mode = on` и работает `archive_command`.
- Доступен `pg_basebackup`, снятый до момента восстановления.
- Доступны WAL-файлы в архиве с момента `pg_basebackup` до целевого времени.

### 4.2. Процедура PITR (PostgreSQL 12+)

```bash
# 1. Восстановить pg_basebackup (как в разделе 3)

# 2. Создать файл-сигнал начала recovery
touch /var/lib/postgresql/17/main/recovery.signal

# 3. Добавить параметры восстановления в postgresql.conf
cat >> /var/lib/postgresql/17/main/postgresql.conf << 'EOF'
restore_command         = 'cp /mnt/wal_archive/%f %p'
recovery_target_time    = '2024-09-01 14:30:00'
recovery_target_action  = 'promote'
EOF

# 4. Запустить — PostgreSQL войдёт в режим recovery
pg_ctl start -D /var/lib/postgresql/17/main

# 5. Наблюдать в логах
tail -f /var/lib/postgresql/17/main/log/postgresql-*.log
```

### 4.3. Ключевые параметры PITR

| Параметр                    | Описание                                                     |
|-----------------------------|--------------------------------------------------------------|
| `restore_command`           | Команда для копирования WAL-файла из архива в PGDATA         |
| `recovery_target_time`      | Целевой момент времени (включительно)                        |
| `recovery_target_lsn`       | Целевой LSN (позиция в журнале)                              |
| `recovery_target_action`    | `promote` / `pause` / `shutdown` по достижении цели          |

### 4.4. Проверка результата PITR

```sql
-- Время последней применённой транзакции
SELECT pg_last_xact_replay_timestamp();

-- Проверить наличие данных
SELECT COUNT(*) FROM orders;
SELECT MAX(created_at) FROM orders;
```

---

## 5. Failover Runbook

Failover Runbook — регламент действий при сбое, который команда согласует **заранее**.

### 5.1. Шаблон failover runbook

```markdown
## Failover Runbook: production

### Контакты
- Дежурный DBA: [телефон, Telegram]
- Ответственный за приложение: [контакт]
- Служба ИБ: [контакт]

### Признаки необходимости failover
- PostgreSQL не отвечает более 5 минут
- Ошибки подключения: connection refused / FATAL
- Мониторинг показывает: сервер недоступен

### Шаги
1. Зафиксировать время начала инцидента
2. Оценить: можно ли перезапустить (pg_ctl start)?
3. Если нет — данные целы? (PGDATA доступен?)
   - Данные целы → восстановить pg_basebackup + WAL (PITR)
   - Данные недоступны → переключить на реплику
4. Выполнить восстановление
5. Проверить: flyway info — корректный статус миграций
6. Smoke-тест приложения
7. Зафиксировать: время восстановления, что потеряно (RPO факт)

### После восстановления
- Постмортем: причина, timeline, что пошло не так
- Обновить runbook
- Убедиться, что архивирование возобновилось
```

---

## 6. Регулярное тестирование восстановления

| Что тестировать              | Частота    | Как                                                         |
|------------------------------|------------|-------------------------------------------------------------|
| pg_restore логического дампа | Ежемесячно | Восстановить в тестовую БД; проверить счётчики строк        |
| PITR                         | Квартально | Восстановить на произвольную точку; проверить данные        |
| Failover на реплику          | Квартально | Симулировать остановку primary; переключить трафик          |

---

## 7. Итоги лекции

После этой лекции студент умеет:

- **Выбрать метод восстановления** по сценарию: `pg_restore -t` для одной таблицы, полный restore, PITR для точечного восстановления.
- **Выполнить PITR**: создать `recovery.signal`, прописать `restore_command` и `recovery_target_time`, запустить в режиме recovery.
- **Составить Failover Runbook** с контактами, признаками отказа и шагами по двум сценариям.
- **Объяснить**, почему PITR без заранее настроенного `archive_mode=on` невозможен.
- **Встроить тест восстановления** в регламент: периодичность, сценарий, критерии успеха.

---

## Ссылки

- Непрерывное архивирование и PITR: https://www.postgresql.org/docs/current/continuous-archiving.html
- pg_restore: https://www.postgresql.org/docs/current/app-pgrestore.html
- pg_waldump: https://www.postgresql.org/docs/current/pgwaldump.html
- Параметры восстановления: https://www.postgresql.org/docs/current/recovery-config.html
