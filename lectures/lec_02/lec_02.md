# Лекция 2. Установка и конфигурирование PostgreSQL. Локальная среда разработчика

**Неделя:** 2

---

## Цель лекции

По итогам лекции студент:

- знает варианты установки PostgreSQL и умеет выбрать подходящий для локальной разработки;
- понимает структуру каталога PGDATA и назначение ключевых конфигурационных файлов;
- умеет запустить/остановить сервер, подключиться через DBeaver и psql;
- понимает, зачем аналитику локальная копия БД и как её поддерживать в актуальном состоянии.

---

## 1. Зачем аналитику локальная БД

Системный аналитик работает с БД не только в рамках чтения данных. Типичные задачи, которые требуют локального экземпляра:

- **Проверка migration plan** — запустить скрипт миграции на «чистой» БД перед отправкой MR.
- **Написание тестовых запросов** — не загружать prod, не рисковать данными.
- **Разработка runbook** — воспроизвести сценарий восстановления в безопасной среде.
- **Изучение прав доступа** — безопасно экспериментировать с ролями и привилегиями.

Принцип: **каждый член команды, касающийся БД, должен иметь возможность поднять локальную копию за 10 минут.**

---

## 2. Варианты установки PostgreSQL

| Способ              | Когда использовать                                      | Плюсы                                       | Минусы                                        |
|---------------------|---------------------------------------------------------|---------------------------------------------|-----------------------------------------------|
| **EDB Installer**   | Windows, первое знакомство                              | Графический мастер, включает pgAdmin        | Сложнее управлять версиями                    |
| **apt / yum**       | Linux (Ubuntu, Debian, RHEL, CentOS)                    | Интеграция с systemd, обновления через пакетный менеджер | Нужен доступ к репозиторию          |
| **Homebrew**        | macOS                                                   | `brew install postgresql@17` — просто       | Только для разработки                         |
| **Docker**          | Любая ОС; несколько версий одновременно; CI/CD          | Изоляция, воспроизводимость, быстрый сброс  | Требует Docker Desktop                        |
| **Managed (RDS, Cloud SQL, YDB)** | Production в облаке                     | Управляемый бэкап, HA из коробки            | Нет прямого доступа к файловой системе        |

### 2.1. Установка через EDB Installer (Windows / macOS)

1. Скачать с https://www.enterprisedb.com/downloads/postgres-postgresql-downloads
2. Запустить установщик → выбрать компоненты: PostgreSQL Server, Command Line Tools, pgAdmin (опционально).
3. Задать **пароль суперпользователя `postgres`** — запомнить!
4. Порт по умолчанию: `5432`.
5. После установки сервис запускается автоматически.

### 2.2. Установка через Docker (рекомендуется для разработки)

Предпочтительный способ — `docker-compose.yml`, чтобы зафиксировать версию и параметры в git:

```yaml
# docker-compose.yml
services:
  postgres:
    image: postgres:17
    container_name: pg_local
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: mysecret
      POSTGRES_DB: dev
    ports:
      - "5432:5432"
    volumes:
      - pg_data:/var/lib/postgresql/data

volumes:
  pg_data:
```

```bash
# Запустить
docker compose up -d

# Подключиться через psql внутри контейнера
docker exec -it pg_local psql -U postgres -d dev

# Остановить (данные сохраняются в volume)
docker compose down

# Остановить И удалить данные (полный сброс)
docker compose down -v
```

Для разовых экспериментов без сохранения данных:

```bash
docker run --rm -d \
  --name pg_local \
  -e POSTGRES_PASSWORD=mysecret \
  -p 5432:5432 \
  postgres:17
```

---

## 3. Структура каталога PGDATA

PGDATA — корневой каталог данных кластера PostgreSQL. На Windows обычно `C:\Program Files\PostgreSQL\17\data`, на Linux — `/var/lib/postgresql/17/main`.

```
PGDATA/
├── base/               ← данные баз (одна папка на базу, имя = OID)
│   ├── 1/              ← template1
│   ├── 4/              ← postgres
│   └── 16384/          ← пользовательская БД
├── global/             ← объекты уровня кластера (роли, pg_database)
├── pg_wal/             ← файлы WAL (сегменты по 16 МБ)
├── log/                ← лог-файлы сервера (настраивается параметром log_directory)
├── pg_tblspc/          ← симлинки на табличные пространства
├── postgresql.conf     ← основная конфигурация
├── pg_hba.conf         ← правила аутентификации клиентов
├── pg_ident.conf        ← маппинг системных пользователей на роли БД
├── postgresql.auto.conf ← параметры, изменённые через ALTER SYSTEM; перекрывает postgresql.conf
├── postmaster.pid       ← PID главного процесса; отсутствует когда сервер остановлен
└── PG_VERSION           ← мажорная версия кластера (например, «17»)
```

> **Важно.** Никогда не редактировать файлы в `base/` или `pg_wal/` вручную — это повреждает кластер. Конфигурационные файлы (`.conf`) редактировать можно.

---

## 4. Конфигурационные файлы

### 4.1. postgresql.conf — основная конфигурация

Ключевые параметры, которые нужно понимать:

| Параметр                    | По умолчанию | Для локальной разработки  | Назначение                                              |
|-----------------------------|--------------|---------------------------|---------------------------------------------------------|
| `listen_addresses`          | `localhost`  | `localhost`               | Сетевые интерфейсы для прослушивания (`*` — все)        |
| `port`                      | `5432`       | `5432`                    | Порт TCP                                               |
| `max_connections`           | `100`        | `20–50`                   | Максимум параллельных соединений к кластеру             |
| `shared_buffers`            | `128MB`      | `256MB`                   | Кэш страниц в оперативной памяти                       |
| `work_mem`                  | `4MB`        | `16–64MB`                 | Память на одну операцию сортировки / хеш-соединения     |
| `maintenance_work_mem`      | `64MB`       | `256MB`                   | Память для VACUUM, CREATE INDEX                        |
| `wal_level`                 | `replica`    | `replica`                 | Уровень детализации WAL                                |
| `log_destination`           | `stderr`     | `stderr`                  | Куда писать логи                                       |
| `logging_collector`         | `off`        | `on`                      | Включить сбор логов в файлы                            |
| `log_directory`             | `log`        | `log`                     | Папка для лог-файлов (относительно PGDATA)             |
| `log_statement`             | `none`       | `all`                     | Какие SQL-операторы логировать                         |
| `log_min_duration_statement`| `-1`         | `100`                     | Логировать запросы дольше N мс (`-1` — отключено)      |
| `effective_cache_size`      | `4GB`        | `512MB`                   | Подсказка планировщику об объёме кэша ОС; влияет на выбор плана запроса |

Применить изменения без перезапуска (для большинства параметров):

```sql
SELECT pg_reload_conf();
```

> **Важно:** параметры `shared_buffers` и `max_connections` требуют **полного перезапуска** сервера — `pg_reload_conf()` для них не работает. Список параметров, требующих перезапуска:
> ```sql
> SELECT name, context FROM pg_settings WHERE context = 'postmaster' ORDER BY name;
> ```

Проверить текущее значение параметра:

```sql
SHOW shared_buffers;
SHOW log_statement;
```

### 4.2. pg_hba.conf — правила аутентификации

Файл читается сверху вниз; применяется первое совпавшее правило.

```
# Тип   База    Пользователь  Адрес            Метод
local   all     postgres                       peer
local   all     all                            scram-sha-256
host    all     all           127.0.0.1/32     scram-sha-256
host    all     all           ::1/128          scram-sha-256
```

| Тип     | Когда используется                                            |
|---------|---------------------------------------------------------------|
| `local` | Подключение через Unix-сокет (только Linux/macOS)            |
| `host`  | Подключение по TCP/IP (в т.ч. localhost через сеть)          |
| `hostssl` | TCP только с TLS                                           |

| Метод           | Суть                                                          |
|-----------------|---------------------------------------------------------------|
| `trust`         | Без пароля — только для локальной разработки в изолированной среде |
| `peer`          | ОС-пользователь совпадает с ролью БД (только Unix-сокет)     |
| `md5`           | Пароль в MD5 (устаревший, небезопасен для production)        |
| `scram-sha-256` | Современный стандарт; рекомендован с PostgreSQL 14+          |

После изменения `pg_hba.conf` нужно перезагрузить конфигурацию:

```sql
SELECT pg_reload_conf();
-- или
pg_ctl reload -D /путь/к/PGDATA
```

---

## 5. Управление сервером

### 5.1. pg_ctl — утилита управления

```bash
# Запустить сервер
pg_ctl start -D /path/to/PGDATA

# Остановить — три режима:
# smart    — ждёт завершения всех соединений (аккуратно, но долго)
# fast     — прерывает соединения, делает checkpoint (обычный выбор)
# immediate — аварийная остановка без checkpoint; при следующем старте потребуется recovery из WAL
pg_ctl stop -D /path/to/PGDATA -m fast

# Перезапустить
pg_ctl restart -D /path/to/PGDATA

# Проверить статус
pg_ctl status -D /path/to/PGDATA

# Перечитать конфигурацию (без перезапуска)
pg_ctl reload -D /path/to/PGDATA
```

### 5.2. systemctl (Linux)

```bash
sudo systemctl start postgresql
sudo systemctl stop postgresql
sudo systemctl restart postgresql
sudo systemctl status postgresql
sudo systemctl enable postgresql   # автозапуск при старте ОС
```

### 5.3. Windows — Службы

Службы → `postgresql-x64-17` → Запустить / Остановить / Перезапустить.  
Или через командную строку (от администратора):

```cmd
net start postgresql-x64-17
net stop  postgresql-x64-17
```

---

## 6. Установка и настройка DBeaver (сторона клиента)

DBeaver — GUI-клиент для работы с PostgreSQL. Выполняет роль инструмента на стороне клиента (ТФ A/04.4).

### 6.1. Установка

Скачать Community-версию: https://dbeaver.io/download/  
Требования: Java 17+ (DBeaver включает JRE).

### 6.2. Создание подключения

1. **Database → New Database Connection → PostgreSQL**
2. Заполнить:
   - Host: `localhost`
   - Port: `5432`
   - Database: `postgres`
   - Username: `postgres`
   - Password: ваш пароль
3. Нажать **Test Connection** — при первом запуске DBeaver предложит скачать JDBC-драйвер.

### 6.3. Обязательная настройка — Local Client

DBeaver использует внешние утилиты `pg_dump` и `pg_restore` для резервного копирования. Без этой настройки кнопки **Dump / Restore** не работают.

Настройки подключения → вкладка **Local Client** → указать путь к папке `bin` установленного PostgreSQL:
- Windows: `C:\Program Files\PostgreSQL\17\bin`
- Linux: `/usr/lib/postgresql/17/bin` (универсальный способ найти путь: `which pg_dump | xargs dirname`)

### 6.4. Полезные возможности DBeaver

| Функция                   | Где найти                                              |
|---------------------------|--------------------------------------------------------|
| SQL-редактор              | SQL Editor → Open SQL Script (Alt+F3)                 |
| ERD-диаграмма             | ПКМ по схеме → View Diagram                           |
| Экспорт данных            | ПКМ по таблице → Export Data                          |
| Dump базы                 | ПКМ по БД → Tools → Dump Database                    |
| Restore базы              | ПКМ по БД → Tools → Restore Database                  |
| EXPLAIN ANALYZE            | Открыть план запроса: Ctrl+Shift+E                    |

---

## 7. psql — командная строка

psql — основной CLI-клиент PostgreSQL; поставляется вместе с сервером.

### 7.1. Подключение

```bash
# Подключиться к базе postgres пользователем postgres
psql -h localhost -p 5432 -U postgres -d postgres

# Подключиться к конкретной базе
psql -h localhost -U postgres -d mydb

# Рекомендованный способ — файл ~/.pgpass (host:port:database:user:password):
#   localhost:5432:*:postgres:mysecret
# Установить права (обязательно, иначе psql игнорирует файл):
#   chmod 600 ~/.pgpass
# После этого psql подключается без запроса пароля:
psql -h localhost -U postgres

# PGPASSWORD=... — не использовать: пароль попадает в историю shell и в ps aux
```

### 7.2. Мета-команды psql

| Команда        | Действие                                              |
|----------------|-------------------------------------------------------|
| `\l`           | Список баз данных кластера                           |
| `\c dbname`    | Переключиться на базу `dbname`                       |
| `\dn`          | Список схем в текущей базе                           |
| `\dt`          | Список таблиц в текущей схеме                        |
| `\dt *.*`      | Список таблиц во всех схемах                         |
| `\d tablename` | Структура таблицы (колонки, индексы, FK)             |
| `\du`          | Список ролей (пользователей)                         |
| `\dp tablename`| Привилегии на таблицу                               |
| `\timing`      | Показывать время выполнения запросов                 |
| `\i file.sql`  | Выполнить SQL-скрипт из файла                       |
| `\e`           | Открыть текущий запрос во внешнем редакторе          |
| `\x`           | Переключить расширенный вывод (удобно для широких строк) |
| `\conninfo`    | Показать параметры текущего подключения              |
| `\h SELECT`    | Справка по синтаксису SQL-команды                    |
| `\q`           | Выйти из psql                                        |

### 7.3. Выполнение SQL-скрипта из файла

```bash
# Выполнить скрипт из командной строки
psql -h localhost -U postgres -d mydb -f migration.sql

# Внутри psql
\i /path/to/migration.sql
```

---

## 8. Конвенции локальной среды разработчика

Чтобы работа с локальной БД была предсказуемой в команде, договоритесь о следующем:

| Параметр          | Рекомендация                                          |
|-------------------|-------------------------------------------------------|
| Версия PostgreSQL | Совпадает с production; фиксируется в `docker-compose.yml` или README |
| Имя базы          | Имя приложения одинаковое, суффикс различается: `myapp_dev` / `myapp_test` / `myapp` (prod) |
| Пользователь      | Отдельная роль приложения (не `postgres`)             |
| Данные            | Только тестовые / анонимизированные — никогда prod-данные |
| Миграции          | Применяются через Flyway: `flyway migrate`            |
| Сброс среды       | `flyway clean && flyway migrate` — **только для dev!** Команда `clean` уничтожает все объекты схемы без подтверждения. На staging/prod обязательно установить `flyway.cleanDisabled=true` |

---

## 9. Итоги лекции

После этой лекции студент умеет:

- **Установить PostgreSQL** через EDB Installer или пакетный менеджер и убедиться, что сервер запущен (`pg_ctl status`, `systemctl status`).
- **Найти и изменить** ключевые параметры в `postgresql.conf` (`shared_buffers`, `work_mem`, `log_*`) и применить через `pg_reload_conf()` или перезапуск.
- **Объяснить разницу** между `postgresql.conf` и `pg_hba.conf`: параметры сервера vs правила аутентификации.
- **Использовать psql**: подключаться, выполнять мета-команды (`\dt`, `\d`, `\l`, `\c`), запускать SQL-файл через `\i`.
- **Подключить DBeaver** к локальному PostgreSQL, настроить Local Client для Dump/Restore.
- **Обосновать** принцип: версия PostgreSQL в локальной среде должна совпадать с production.

---

## Ссылки

- Установка PostgreSQL (EDB): https://www.enterprisedb.com/docs/supported-open-source/postgresql/installing/
- PostgreSQL Docker Hub: https://hub.docker.com/_/postgres
- Документация postgresql.conf: https://www.postgresql.org/docs/current/config-setting.html
- Документация pg_hba.conf: https://www.postgresql.org/docs/current/auth-pg-hba-conf.html
- Документация pg_ctl: https://www.postgresql.org/docs/current/app-pg-ctl.html
- Документация psql: https://www.postgresql.org/docs/current/app-psql.html
- DBeaver Community: https://dbeaver.io/download/
