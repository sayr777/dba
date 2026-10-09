# Лекция 6. Восстановление, PITR, отработка сбоев

**Неделя:** 6
**Среда:** PostgreSQL 18, Windows, PowerShell

---

## Цель лекции

По итогам лекции студент:

- знает типовые сценарии потери данных и соответствующие методы восстановления;
- умеет описать процедуру восстановления из логического и физического дампа;
- понимает механизм PITR, его условия и ограничения;
- знает, как оформить регламент восстановления (failover runbook) для DBA.

---

## 0. Правила работы в PowerShell

Все команды лекции выполняются в PowerShell. Нарушение этих правил — частая причина ошибок.

| Правило | Причина |
|---------|---------|
| Перенос строки — обратный апостроф `` ` `` в конце строки | `\` из bash в PowerShell не работает |
| Вывод утилит PostgreSQL в файл — только через флаг `-f`, не через `>` | В Windows PowerShell 5.1 `>` пишет файл в UTF-16; `pg_restore`, `psql -f` такой файл не читают |
| Остановка и запуск службы — в PowerShell **от имени администратора** | `Stop-Service` / `Start-Service` требуют прав администратора |
| Пути с пробелами — в кавычках | `C:\Program Files\...` |

Подготовка сессии:

```powershell
# Утилиты PostgreSQL в PATH (на время сессии)
$env:Path += ";C:\Program Files\PostgreSQL\18\bin"

# Каталог данных кластера (по умолчанию установщика)
$env:PGDATA = "C:\Program Files\PostgreSQL\18\data"

# Имя службы
$svc = "postgresql-x64-18"

# Пути стенда (лаб. 03–04)
$backup  = "C:\backup\eshop"
$dump    = "$backup\eshop_20240901.dump"
$archive = "$backup\wal_archive"

# Если кириллица в выводе psql искажена
chcp 1251
```

Пароль не вводить в каждой команде: файл `%APPDATA%\postgresql\pgpass.conf` или переменная `$env:PGPASSWORD` (только на учебном стенде).

---
### 0.1. Термины
 
| Термин | Значение |
|--------|----------|
| PGDATA | Каталог данных кластера |
| WAL | Журнал предзаписи: все изменения данных записываются в него до записи в файлы таблиц |
| Сегмент WAL | Файл журнала (16 МБ); в архив уходит целиком |
| LSN | Позиция в журнале WAL, например `0/05A3B2C8` |
| Timeline (линия времени) | Ветка истории кластера; новая линия начинается после каждого PITR с переходом в рабочий режим |
| RPO | Максимально допустимая потеря данных, во времени |
| RTO | Максимально допустимое время простоя; отсчёт — от начала инцидента |
 
---

## 1. Сценарии потери данных

Прежде чем выбирать метод восстановления, нужно понять причину:

| Сценарий                                        | Что пострадало              | Метод восстановления                                         |
|-------------------------------------------------|-----------------------------|--------------------------------------------------------------|
| Случайный `DELETE` без `WHERE`                  | Данные в таблице            | PITR на отдельный экземпляр + перенос строк; или логический дамп |
| `DROP TABLE` / `DROP DATABASE`                  | Схема + данные              | PITR на отдельный экземпляр; или pg_restore из дампа         |
| Плохая миграция (`UPDATE` с неверным условием)  | Данные в нескольких строках | Forward-fix миграция; если невозможно — PITR на отдельный экземпляр + перенос строк |
| Отказ диска / повреждение файловой системы      | Весь PGDATA                 | Failover на реплику; или pg_basebackup + весь WAL-архив      |
| Аппаратный сбой (полная потеря сервера)         | Всё                         | Failover на реплику; или pg_basebackup + весь WAL-архив на новом сервере |

> **Первый вопрос при инциденте:** «Когда была последняя заведомо корректная точка?» — это определяет RPO и метод восстановления.

### 1.1. Главное ограничение PITR

PITR возвращает в прошлое **весь кластер** (все базы экземпляра), а не одну таблицу или базу. Все транзакции после целевой точки теряются, в том числе корректные.

Поэтому при **логической ошибке** (DELETE, DROP, плохая миграция) PITR выполняют **на отдельном экземпляре**:

1. Поднять копию кластера на другом сервере или порту (например, 5433).
2. Восстановить её на момент до ошибки.
3. Извлечь нужные данные (`pg_dump -t`, `COPY`).
4. Загрузить их в рабочую базу.

Рабочий сервер при этом продолжает работать.

### 1.2. Сравнение методов по RPO

| Метод                          | Фактическое RPO                         | Типичное RTO                  |
|--------------------------------|-----------------------------------------|-------------------------------|
| Логический дамп                | Время с момента последнего дампа (часы) | Зависит от объёма базы        |
| pg_basebackup + WAL-архив      | Секунды–минуты (последний сегмент WAL)  | Копирование PGDATA + применение WAL |
| Асинхронная реплика (failover) | Секунды                                 | Минуты                        |

---

## 2. Восстановление из логического дампа

### 2.1. Восстановление всей базы (custom-формат)

```powershell
# Создать базу-приёмник
createdb -h localhost -U postgres eshop_restore_test

# Восстановить из custom-дампа (формат pg_restore определяет сам)
pg_restore -h localhost -U postgres `
  -d eshop_restore_test `
  --verbose `
  C:\backup\eshop\eshop_20240901.dump

# Параллельное восстановление (только custom- и directory-формат)
pg_restore -h localhost -U postgres `
  -d eshop_restore_test `
  -j 4 --verbose `
  C:\backup\eshop\eshop_20240901.dump
```

Вариант с созданием базы из дампа. Флаг `-C` создаёт базу; подключение идёт к служебной базе `postgres`:

```powershell
pg_restore -h localhost -U postgres `
  -C --clean --if-exists `
  -d postgres `
  C:\backup\eshop\eshop_20240901.dump
```

### 2.2. Выборочное восстановление

**Правило:** не восстанавливать таблицу напрямую в рабочую базу. Сначала восстановить во временную базу, проверить, затем перенести данные.

```powershell
# Только схема (без данных)
pg_restore -h localhost -U postgres `
  -d eshop_restore_test --schema-only `
  C:\backup\eshop\eshop_20240901.dump

# Просмотр объектов в дампе
pg_restore --list C:\backup\eshop\eshop_20240901.dump |
  Select-String "TABLE DATA"
```

#### Ограничение флага `-t`

`pg_restore -t orders` восстанавливает только `CREATE TABLE` и данные. Флаг **не** восстанавливает:

- первичный ключ и уникальные ограничения;
- индексы;
- внешние ключи;
- триггеры;
- DEFAULT / последовательность для столбца id.

Таблица после `-t` выглядит целой (`COUNT(*)` верный), но следующий `INSERT` может упасть.

#### Полное восстановление одной таблицы через оглавление дампа

```powershell
# 1. Выгрузить оглавление дампа (-f, а не >)
pg_restore -l -f C:\backup\eshop\toc.txt $dump

# 2. Оставить строки, относящиеся к таблице.
#    WriteAllLines пишет UTF-8 без BOM — pg_restore читает такой файл корректно
$lines = Get-Content C:\backup\eshop\toc.txt |
  Select-String -SimpleMatch "orders" |
  ForEach-Object { $_.Line }
[System.IO.File]::WriteAllLines("C:\backup\eshop\toc_orders.txt", [string[]]$lines)

# 3. Проверить toc_orders.txt вручную (notepad):
#    индекс с именем без "orders" в фильтр не попадёт — добавить его строку;
#    лишние объекты (например, order_items) — удалить
notepad C:\backup\eshop\toc_orders.txt

# 4. Восстановить по списку во временную базу
createdb -h localhost -U postgres orders_tmp
pg_restore -h localhost -U postgres `
  -d orders_tmp -L C:\backup\eshop\toc_orders.txt `
  $dump
```

Проверка после восстановления (в psql): `\d orders` показывает PK, индексы и FK.

### 2.3. Типичные ошибки при восстановлении

| Ошибка                                           | Причина                                              | Решение                                                        |
|--------------------------------------------------|------------------------------------------------------|----------------------------------------------------------------|
| `role "app_user" does not exist`                 | Роли не восстановлены (pg_dump не выгружает роли)    | Сначала `psql -U postgres -d postgres -f C:\backup\eshop\globals.sql` (файл из `pg_dumpall --globals-only -f ...`) |
| `database "eshop" already exists`                | Запуск с `-C`, база уже существует                   | `-C --clean --if-exists -d postgres` или `dropdb` перед запуском |
| `duplicate key value violates unique constraint` | Данные уже есть в таблице                            | Восстанавливать в пустую базу; или `--clean --if-exists`        |
| Медленное восстановление                         | Один поток; малый `maintenance_work_mem` при построении индексов | `-j 4`; временно увеличить `maintenance_work_mem`        |
| `invalid byte sequence` / `syntax error at or near "ÿþ"` при `psql -f` или `pg_restore -L` | Файл записан через `>` в UTF-16 | Пересоздать файл через `-f` или `WriteAllLines` |

> Индексы `pg_restore` строит **после** загрузки данных (секция post-data). Поэтому основное время уходит на `COPY` и `CREATE INDEX`, и параллельность `-j` даёт большой выигрыш.

### 2.4. Статистика планировщика (PostgreSQL 18)

В PostgreSQL 18 `pg_dump` может выгружать статистику планировщика (`--with-statistics`). Если дамп снят без неё, после восстановления статистики нет, и первые запросы выполняются по неоптимальным планам.

Правило: после восстановления без статистики выполнить:

```sql
ANALYZE;
```

Новые флаги `pg_restore` в PostgreSQL 18: `--no-statistics`, `--statistics-only`, `--no-data`, `--no-schema`.

---

## 3. Восстановление из физической копии (pg_basebackup)

Физическое восстановление заменяет **весь** PGDATA. Без WAL-архива данные вернутся на момент окончания копии.

Особенности Windows:

- PGDATA по умолчанию: `C:\Program Files\PostgreSQL\18\data`;
- `postgresql.conf` и `postgresql.auto.conf` находятся в PGDATA;
- логи: `PGDATA\log\`;
- служба работает от учётной записи `NT AUTHORITY\NetworkService`; у неё должен быть полный доступ к PGDATA.

Команды раздела выполнять в PowerShell **от имени администратора**.

```powershell
$damaged = "$env:PGDATA" + "_damaged"

# 1. Остановить службу
Stop-Service $svc

# 2. Переименовать (не удалять!) текущий PGDATA — нужен для анализа и для WAL
Rename-Item $env:PGDATA $damaged

# 3а. Восстановить (plain-формат: pg_basebackup -Fp)
Copy-Item -Recurse C:\backup\eshop\basebackup $env:PGDATA

# 3б. Или восстановить из tar-формата (pg_basebackup -Ft); tar.exe встроен в Windows 10+
New-Item -ItemType Directory $env:PGDATA | Out-Null
tar -xf C:\backup\eshop\basebackup\base.tar   -C $env:PGDATA
tar -xf C:\backup\eshop\basebackup\pg_wal.tar -C "$env:PGDATA\pg_wal"

# 4. Скопировать неархивированные сегменты WAL из повреждённого кластера
#    (если каталог доступен) — это уменьшает фактическое RPO
Copy-Item "$damaged\pg_wal\0000*" "$env:PGDATA\pg_wal\" -Force -ErrorAction SilentlyContinue

# 5. Выдать права учётной записи службы
icacls $env:PGDATA /grant "NT AUTHORITY\NetworkService:(OI)(CI)F" /T /Q
```

Далее: запуск с `recovery.signal` (раздел 4) — сервер применит WAL из архива.

### 3.1. Инкрементальные копии (PostgreSQL 17+)

Инкрементальная копия содержит только блоки, изменённые после предыдущей копии. Требование: `summarize_wal = on`.

```powershell
# Полная копия
pg_basebackup -h localhost -U postgres -D C:\backup\eshop\full -X stream -P

# Инкрементальная копия относительно полной (по её манифесту)
pg_basebackup -h localhost -U postgres -D C:\backup\eshop\incr1 -X stream -P `
  --incremental=C:\backup\eshop\full\backup_manifest

# Восстановление: объединить цепочку в один PGDATA
pg_combinebackup C:\backup\eshop\full C:\backup\eshop\incr1 -o $env:PGDATA
```

Далее — как для обычной копии: права, `recovery.signal`, WAL-архив. Цепочка должна быть полной: потеря любой копии в ней делает следующие непригодными.

---

## 4. Point-in-Time Recovery (PITR)

PITR позволяет восстановить кластер **на конкретный момент времени** — например, за 1 минуту до случайного `DROP TABLE`.

### 4.1. Требования

Все требования выполняются **до** инцидента. После инцидента их настроить нельзя.

- `wal_level = replica` (или `logical`).
- `archive_mode = on` и работает `archive_command` (проверка: `pg_stat_archiver`, поле `failed_count`).
- Есть копия `pg_basebackup`, которая **завершилась** до целевого момента.
- В архиве есть **все** сегменты WAL от начала этой копии до целевого момента, без пропусков.

### 4.2. Процедура PITR на отдельном экземпляре

Для логической ошибки рабочую службу не останавливают. Копия поднимается вручную через `pg_ctl` на порту 5433. Права администратора для этого не нужны: каталог `C:\pitr\data` принадлежит текущему пользователю.

```powershell
$pitr = "C:\pitr\data"

# 1. Развернуть базовую копию в отдельный каталог
#    (заранее снятую копию — Copy-Item; или pg_combinebackup для цепочки)
Copy-Item -Recurse C:\backup\eshop\basebackup $pitr

# 2. Создать файл-сигнал режима recovery
New-Item -ItemType File "$pitr\recovery.signal" | Out-Null

# 3. Добавить параметры восстановления в postgresql.auto.conf.
#    Одинарные кавычки @' '@ — PowerShell не подставляет переменные и не трогает \\ и %
Add-Content -Path "$pitr\postgresql.auto.conf" -Encoding ascii -Value @'
port = 5433
archive_mode = off
restore_command = 'copy "C:\\backup\\eshop\\wal_archive\\%f" "%p"'
recovery_target_time = '2024-09-01 14:30:00+03'
recovery_target_action = 'pause'
'@

# 4. Запустить экземпляр — он войдёт в режим recovery
pg_ctl -D $pitr -l C:\pitr\pitr.log start

# 5. Наблюдать журнал
Get-Content C:\pitr\pitr.log -Tail 30 -Wait
```

Для отказа сервера (раздел 3) процедура та же, но в рабочем PGDATA, без `port` и `archive_mode = off`, без `recovery_target_*`, с запуском `Start-Service $svc`. Журнал службы:

```powershell
Get-ChildItem "$env:PGDATA\log" | Sort-Object LastWriteTime |
  Select-Object -Last 1 | Get-Content -Tail 30 -Wait
```

Обязательные правила:

- **`archive_mode = off` на отдельном экземпляре.** Иначе он запишет WAL новой линии времени в боевой архив.
- **Часовой пояс.** Время без смещения читается в `timezone` сервера. Всегда указывать смещение: `+03`.
- **`pause`, а не `promote`.** Экземпляр останавливается на цели и принимает запросы на чтение (`hot_standby = on`). Можно проверить данные до завершения recovery. Без `hot_standby` значение `pause` работает как `shutdown`.
- **Двойные `\\` в `restore_command`.** В строках конфигурации `\` — экранирующий символ.

### 4.3. Точная цель: поиск LSN через pg_waldump

Время инцидента часто известно неточно. `pg_waldump` показывает записи WAL и позволяет найти точную позицию.

```powershell
# Найти коммит транзакции, которая удалила файлы таблицы (DROP TABLE)
pg_waldump -p C:\backup\eshop\wal_archive `
  000000010000000000000005 000000010000000000000007 |
  Select-String "COMMIT.*rels"

# Пример строки вывода:
# rmgr: Transaction ... lsn: 0/05A3B2C8 ... desc: COMMIT 2024-09-01 14:31:02 MSK; rels: base/16384/16390
```

Параметры для остановки **перед** этой транзакцией (вместо `recovery_target_time`):

```
recovery_target_lsn       = '0/05A3B2C8'
recovery_target_inclusive = off
```

### 4.4. Ключевые параметры PITR

| Параметр                    | Описание                                                                   |
|-----------------------------|----------------------------------------------------------------------------|
| `restore_command`           | Команда копирования WAL-файла из архива (`%f` — имя файла, `%p` — путь назначения) |
| `recovery_target_time`      | Целевой момент времени (указывать со смещением часового пояса)             |
| `recovery_target_lsn`       | Целевая позиция в журнале (LSN)                                            |
| `recovery_target_xid`       | Целевой номер транзакции                                                   |
| `recovery_target_inclusive` | `on` (по умолчанию) — применить целевую транзакцию; `off` — остановиться перед ней |
| `recovery_target_timeline`  | Линия времени для восстановления; по умолчанию `latest`                    |
| `recovery_target_action`    | `pause` / `promote` / `shutdown` по достижении цели                        |

> Без `recovery_target_*` сервер применяет **весь** архив. Это режим для отказа диска или сервера: цель — минимальная потеря данных, а не возврат в прошлое.

### 4.5. Проверка результата и завершение PITR

```powershell
psql -p 5433 -U postgres -d eshop -c "SELECT pg_is_in_recovery(), pg_last_xact_replay_timestamp();"
psql -p 5433 -U postgres -d eshop -c "SELECT COUNT(*) FROM orders;"
```

Далее — один из вариантов:

| Результат проверки           | Действие                                                                         |
|------------------------------|----------------------------------------------------------------------------------|
| Данные корректны, нужен перенос строк (логическая ошибка) | Выгрузить данные с 5433 и загрузить в рабочую базу (ниже); остановить экземпляр |
| Данные корректны, экземпляр станет рабочим | `SELECT pg_wal_replay_resume();` — recovery завершается, сервер переходит в рабочий режим |
| Цель выбрана неверно         | Остановить экземпляр, изменить `recovery_target_*`, запустить снова (только если цель **дальше** текущей точки; иначе — заново с шага 1) |

Перенос строк с отдельного экземпляра в рабочую базу:

```powershell
# Выгрузить данные таблицы с экземпляра PITR (-f, а не >)
pg_dump -p 5433 -U postgres -d eshop --data-only -t orders `
  -f C:\pitr\orders_data.sql

# Загрузить в рабочую базу (порт 5432); при необходимости — сначала во временную таблицу
psql -p 5432 -U postgres -d eshop -f C:\pitr\orders_data.sql

# Остановить экземпляр PITR
pg_ctl -D C:\pitr\data stop -m fast
```

Если экземпляр после PITR становится рабочим:

- Сервер начинает новую линию времени (timeline): имена новых WAL-файлов начинаются с `00000002...`.
- Удалить параметры `recovery_target_*` и `restore_command` из `postgresql.auto.conf`.
- Вернуть `archive_mode = on` и **сразу** снять новый `pg_basebackup`.

---

## 5. Failover и Runbook

### 5.1. Failover на реплику

Если есть реплика, переключение на неё — самый быстрый путь при отказе сервера (RTO — минуты).

**Порядок обязателен:**

1. **Изолировать старый primary.** Остановить службу или закрыть порт 5432 в брандмауэре. Если старый primary вернётся и примет запись, возникнет **split-brain**: две базы с разными данными.
   ```powershell
   # На старом primary (администратор), если сервер доступен
   Stop-Service $svc
   Set-Service $svc -StartupType Disabled
   # Или закрыть порт
   New-NetFirewallRule -DisplayName "Block PG 5432" -Direction Inbound `
     -Protocol TCP -LocalPort 5432 -Action Block
   ```
2. Проверить отставание реплики:
   ```sql
   SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();
   ```
3. Повысить реплику:
   ```sql
   SELECT pg_promote();
   ```
4. Переключить приложение на новый primary (строка подключения, DNS, балансировщик).
5. Включить архивирование на новом primary; снять новый `pg_basebackup`.
6. Старый primary вернуть в работу **только** как новую реплику (`pg_rewind` или новая копия).

`pg_rewind` требует контрольных сумм страниц или `wal_log_hints = on`. В PostgreSQL 18 `initdb` включает контрольные суммы по умолчанию. Кластер, перенесённый с ранней версии через `pg_upgrade`, сохраняет прежнюю настройку. Проверка:

```sql
SHOW data_checksums;   -- on
SHOW wal_log_hints;
```

### 5.2. Шаблон Failover Runbook

Failover Runbook — регламент действий при сбое, который команда согласует **заранее**.

```markdown
## Failover Runbook: production

### Контакты
- Дежурный DBA: [телефон, Telegram]
- Ответственный за приложение: [контакт]
- Служба ИБ: [контакт]

### Признаки отказа
- PostgreSQL не отвечает более 5 минут
- Ошибки подключения: connection refused / FATAL
- Мониторинг показывает: сервер недоступен
- Данные в отчётах пустые или неверные (логическая ошибка)

### Общие шаги
1. Зафиксировать время начала инцидента.
2. Определить тип: отказ сервера (A) или логическая ошибка в данных (B).

### Сценарий A: отказ сервера
1. Служба запускается? Get-Service postgresql-x64-18; журнал в PGDATA\log.
   - Да → устранить причину; Start-Service; перейти к проверкам.
2. PGDATA повреждён или недоступен:
   - Есть реплика → изолировать старый primary → pg_promote() на реплике → переключить приложение.
   - Реплики нет → pg_basebackup + ВЕСЬ WAL-архив (без recovery_target_*).
3. Скопировать неархивированные WAL из старого pg_wal, если доступен.

### Сценарий B: логическая ошибка (DELETE, DROP, плохая миграция)
1. Определить последнюю корректную точку (время или LSN через pg_waldump).
2. Можно исправить forward-fix миграцией? → да → исправить.
3. Нет → PITR на отдельный экземпляр (порт 5433) с recovery_target_action = 'pause'.
4. Проверить данные → выгрузить нужные строки → загрузить в рабочую базу.
5. Рабочий сервер НЕ откатывать: PITR откатит все базы кластера.

### Проверки после восстановления
- Версия схемы корректна (flyway info / таблица истории миграций).
- Счётчики строк ключевых таблиц совпадают с ожидаемыми.
- Smoke-тест приложения.

### После восстановления
- Зафиксировать: время начала и конца (факт RTO), что потеряно (факт RPO).
- Убедиться, что архивирование работает (pg_stat_archiver).
- Снять новый pg_basebackup.
- Постмортем: причина, timeline, что пошло не так.
- Обновить runbook.
```

---

## 6. Регулярное тестирование восстановления

Непроверенная резервная копия — не резервная копия. Тест выполняют на отдельном стенде или отдельном экземпляре.

| Что тестировать              | Частота    | Как                                                          | Критерий успеха                           |
|------------------------------|------------|--------------------------------------------------------------|-------------------------------------------|
| pg_restore логического дампа | Ежемесячно | Восстановить в тестовую БД; сравнить счётчики строк          | Счётчики совпадают; время ≤ целевого RTO  |
| PITR                         | Квартально | Восстановить на произвольную точку на порту 5433; проверить данные | Данные на точку совпадают; время ≤ RTO |
| Failover на реплику          | Квартально | Симулировать остановку primary; переключить трафик           | Приложение работает; потери ≤ целевого RPO |

Замер времени теста в PowerShell:

```powershell
Measure-Command {
  pg_restore -h localhost -U postgres -d eshop_restore_test -j 4 C:\backup\eshop\eshop_20240901.dump
} | Select-Object TotalMinutes
```

> На тестовом экземпляре установить `archive_mode = off` или другой каталог архива. Иначе тест запишет WAL новой линии времени в боевой архив.

---

## 7. Итоги лекции

После этой лекции студент умеет:

- **Выбрать метод восстановления** по сценарию и по требуемому RPO: дамп, PITR, failover на реплику.
- **Восстановить одну таблицу** без потери ограничений и индексов: через временную базу и оглавление дампа (`-l` / `-L`).
- **Выполнить PITR** на отдельном экземпляре: `recovery.signal`, `restore_command`, цель по времени или LSN, `pause` для проверки, перенос данных или завершение через `pg_wal_replay_resume()`.
- **Объяснить**, почему PITR при логической ошибке выполняют на отдельном экземпляре.
- **Объяснить**, почему PITR без заранее настроенного `archive_mode = on` невозможен.
- **Составить Failover Runbook** с контактами, признаками отказа и шагами по двум сценариям: отказ сервера и логическая ошибка.
- **Встроить тест восстановления** в регламент: периодичность, сценарий, критерии успеха.

---

## Ссылки

- Непрерывное архивирование и PITR: https://www.postgresql.org/docs/current/continuous-archiving.html
- pg_restore: https://www.postgresql.org/docs/current/app-pgrestore.html
- pg_basebackup: https://www.postgresql.org/docs/current/app-pgbasebackup.html
- pg_combinebackup: https://www.postgresql.org/docs/current/app-pgcombinebackup.html
- pg_waldump: https://www.postgresql.org/docs/current/pgwaldump.html
- pg_ctl: https://www.postgresql.org/docs/current/app-pg-ctl.html
- Параметры цели восстановления: https://www.postgresql.org/docs/current/runtime-config-wal.html#RUNTIME-CONFIG-WAL-RECOVERY-TARGET
- Функции управления восстановлением (`pg_promote`, `pg_wal_replay_resume`): https://www.postgresql.org/docs/current/functions-admin.html#FUNCTIONS-RECOVERY-CONTROL
