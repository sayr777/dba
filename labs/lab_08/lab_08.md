# Лабораторная работа №8
## Информационная безопасность eshop: pgAudit, TLS, шифрование

**Неделя:** 11  
**Ориентировочное время:** 2 занятия (≈ 4 ак. ч.)

---

## Цель работы

- Включить и настроить аудит через расширение `pgAudit`.
- Настроить TLS-соединения (ssl=on).
- Применить шифрование чувствительных данных через `pgcrypto`.
- Составить ИБ-чек-лист для базы `eshop` с учётом 152-ФЗ.

---

## Предварительные требования

- Завершена лаб. 02: ролевая модель `eshop` создана.
- Прочитана [Лек. 11 — Информационная безопасность на уровне БД. Аудит](../../lectures/lec_11/lec_11.md).

---

## Часть 1. pgAudit: аудит действий в БД

### 1.1. Установить расширение

> **Командная строка (PowerShell).** Для остановки и запуска службы используйте PowerShell от имени администратора. Наличие pgAudit в EDB Stack Builder не гарантируется; если пакета нет в списке, используйте отдельную Windows-сборку.

**Установка pgAudit для PostgreSQL 18 (Windows x64):**

1. Откройте репозиторий [pgextwin/pgaudit — Windows-сборки pgAudit](https://github.com/pgextwin/pgaudit).
2. На [странице релиза v18.0-windows.2](https://github.com/pgextwin/pgaudit/releases/tag/v18.0-windows.2) скачайте **[pgaudit-18.0-pg18-windows-x64.zip](https://github.com/pgextwin/pgaudit/releases/download/v18.0-windows.2/pgaudit-18.0-pg18-windows-x64.zip)** и файл `SHA256SUMS.txt`. Версия должна соответствовать мажорной версии PostgreSQL: `pgAudit 18.x` — для PostgreSQL 18, `pgAudit 1.7.x` — для PostgreSQL 15.
   > **Важно:** это неофициальная сборка проекта `pgextwin`, а не пакет EDB или бинарный релиз разработчиков pgAudit. Используйте её на учебном стенде по согласованию с преподавателем. Перед установкой сделайте резервную копию БД и `postgresql.conf`.
3. Проверьте SHA-256 архива и сравните с записью в `SHA256SUMS.txt`, затем распакуйте ZIP и прочитайте `PACKAGE-INFO.txt`:
   ```powershell
   Get-FileHash "$env:USERPROFILE\Downloads\pgaudit-18.0-pg18-windows-x64.zip" -Algorithm SHA256
   ```
4. Остановите службу и скопируйте содержимое каталогов архива в соответствующие каталоги PostgreSQL:
   ```powershell
   Stop-Service postgresql-x64-18
   ```
   ```text
   lib\*              → C:\Program Files\PostgreSQL\18\lib\
   share\extension\*  → C:\Program Files\PostgreSQL\18\share\extension\
   ```
   Нужны как `pgaudit.dll`, так и `pgaudit.control` и SQL-файлы расширения. Отсутствие control-файла вызывает ошибку `could not open extension control file`, а отсутствие или несовместимость DLL — ошибку загрузки библиотеки.
   > **Если GitHub недоступен:** возьмите этот комплект файлов у преподавателя. Не добавляйте `pgaudit` в `shared_preload_libraries`, пока библиотека не установлена: иначе PostgreSQL может не запуститься.
5. Проверьте текущее значение `shared_preload_libraries` в `postgresql.conf` (после lab_06 там уже `pg_stat_statements`). **Добавьте `pgaudit` через запятую** к существующему значению:
   ```ini
   shared_preload_libraries = 'pg_stat_statements,pgaudit'
   ```
   > **Важно:** не заменяйте всю строку — иначе потеряете `pg_stat_statements`.
6. Запустите службу PostgreSQL (PowerShell от имени администратора):
   ```powershell
   Start-Service postgresql-x64-18
   ```
   Если служба не запускается из-за загрузки pgAudit, уберите только `pgaudit` из `shared_preload_libraries`, снова запустите службу и проверьте совместимость установленной сборки. Параметр `pgaudit.log` включайте только после создания расширения в следующем шаге.
7. Переподключитесь к базе `eshop` под `postgres` и выполните:

```sql
-- После запуска — создать расширение
CREATE EXTENSION IF NOT EXISTS pgaudit;

-- Проверить
SELECT * FROM pg_extension WHERE extname = 'pgaudit';
```

### 1.2. Настройка сессионного аудита

В `postgresql.conf` добавьте:

```ini
pgaudit.log = 'write,ddl,role'
pgaudit.log_catalog = off
pgaudit.log_relation = on
pgaudit.log_statement_once = off
```

После `SELECT pg_reload_conf();` аудит запросов пойдёт в лог PostgreSQL.

### 1.3. Проверка аудита

```sql
-- Выполнить действия, которые должны аудироваться
INSERT INTO customers (name, email, region) VALUES ('Аудит-тест', 'audit@test.com', 'MSK');
UPDATE customers SET phone = '+7-999-999-99-99' WHERE email = 'audit@test.com';
DELETE FROM customers WHERE email = 'audit@test.com';
CREATE TABLE audit_test_table (id SERIAL PRIMARY KEY, val TEXT);
DROP TABLE audit_test_table;
```

Найдите в лог-файле строки с `AUDIT`:

> **Командная строка (PowerShell).** Путь к папке логов — `C:\Program Files\PostgreSQL\18\data\log`.

```powershell
$logDir = "C:\Program Files\PostgreSQL\18\data\log"
Get-ChildItem $logDir -Filter "postgresql-*.log" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 |
    ForEach-Object { Select-String -Path $_.FullName -Pattern "AUDIT" } |
    Select-Object -Last 20
```

Пример строки аудита:
```
2024-09-01 15:30:00 MSK [1234]: [1-1] user=postgres,db=eshop AUDIT: SESSION,1,1,WRITE,INSERT,TABLE,public.customers,...
```

### 1.4. Объектный аудит через роль

Для аудита только конкретных таблиц (более гранулярно):

```sql
-- Создать роль-аудитор (повторный запуск лабораторной не должен падать)
DROP ROLE IF EXISTS eshop_auditor;
CREATE ROLE eshop_auditor;
GRANT SELECT ON customers, orders TO eshop_auditor;

-- Настроить pgaudit для этой роли
SET pgaudit.role = 'eshop_auditor';
```

В `postgresql.conf`:
```ini
pgaudit.role = 'eshop_auditor'
```

```sql
SELECT pg_reload_conf();
```

Теперь аудируются только обращения к `customers` и `orders`, независимо от пользователя.

---

## Часть 2. TLS: шифрование соединений

### 2.1. Проверить текущее состояние SSL

```sql
SHOW ssl;                   -- on или off?
SELECT ssl, client_addr, usename, datname
FROM   pg_stat_ssl
JOIN   pg_stat_activity USING (pid)
WHERE  pid = pg_backend_pid();
```

### 2.2. Включить SSL

Если `ssl = off`, добавьте в `postgresql.conf`:
```ini
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file  = 'server.key'
```

Для учебного стенда можно создать самоподписанный сертификат:

> **Командная строка (Git Bash / PowerShell).** Используйте один из вариантов ниже.

**Вариант A — Git Bash (рекомендуется, если установлен Git for Windows):**

```bash
PGDATA="C:/Program Files/PostgreSQL/18/data"
openssl req -new -x509 -days 365 -nodes \
    -out "$PGDATA/server.crt" \
    -keyout "$PGDATA/server.key" \
    -subj "/CN=localhost"
```

**Вариант Б — PowerShell (без openssl):**

```powershell
$pgdata = "C:\Program Files\PostgreSQL\18\data"
# Создать самоподписанный сертификат средствами Windows
$cert = New-SelfSignedCertificate -DnsName "localhost" -CertStoreLocation "cert:\LocalMachine\My" -NotAfter (Get-Date).AddDays(365)
# Экспортировать в файлы PEM (требует OpenSSL или certutil)
# Проще использовать Git Bash с openssl (Вариант A)
```

После создания файлов ограничьте права на закрытый ключ (PowerShell от имени администратора):

```powershell
$keyFile = "C:\Program Files\PostgreSQL\18\data\server.key"
icacls $keyFile /inheritance:r /grant:r "NT AUTHORITY\NetworkService:(R)" /grant:r "BUILTIN\Administrators:(F)"
```

> **Нужен перезапуск службы.** Параметры `ssl`, `ssl_cert_file`, `ssl_key_file` относятся к контексту `postmaster`: `pg_reload_conf()` их не применяет. После создания сертификата и прав перезапустите службу:
> ```powershell
> Restart-Service postgresql-x64-18
> ```
> Проверьте: `SHOW ssl;` должно вернуть `on`. В DBeaver выполните **Invalidate/Reconnect**: старое соединение остаётся без TLS, и `pg_stat_ssl` для него покажет `ssl = false`.

### 2.3. Принудительное использование SSL в pg_hba.conf

```
# Заменить в pg_hba.conf (только SSL-соединения для app_backend):
# Обе строки должны стоять ВЫШЕ общего правила host all all 127.0.0.1/32 ...
hostssl    eshop  app_backend  127.0.0.1/32  scram-sha-256
hostnossl  eshop  app_backend  127.0.0.1/32  reject
```

> **Порядок правил.** `pg_hba.conf` применяет **первое совпавшее** правило. Если выше уже есть `host eshop app_backend 127.0.0.1/32 ...`, оно сработает раньше и разрешит соединение без TLS. Строки `hostssl`/`hostnossl` поставьте **выше** любых `host`-правил для этой базы и пользователя (или удалите/закомментируйте старую строку `host`). Строка `hostnossl ... reject` нужна, чтобы `sslmode=disable` действительно получил отказ, а не прошёл по общему правилу.

```sql
SELECT pg_reload_conf();

-- Проверить текущее (уже переподключённое) соединение
SELECT ssl, usename FROM pg_stat_ssl
JOIN pg_stat_activity USING (pid)
WHERE pid = pg_backend_pid();
-- ssl = true
```

> Соединение `app_backend` проверяется в п. 2.4 — после того, как psql действительно подключится под этой ролью. В только что выполненном запросе строки `app_backend` нет: этот пользователь ещё не подключён.

### 2.4. Проверить через psql

> **Командная строка (PowerShell).**

```powershell
$pg = "C:\Program Files\PostgreSQL\18\bin"

# Должно подключиться без ошибок
& "$pg\psql.exe" "host=127.0.0.1 dbname=eshop user=app_backend sslmode=require" -c "SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid();"

# Должна быть ошибка: SSL required
& "$pg\psql.exe" "host=127.0.0.1 dbname=eshop user=app_backend sslmode=disable" -c "SELECT 1;"
```

---

## Часть 3. pgcrypto: шифрование данных

### 3.1. Установить расширение

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```

### 3.2. Шифрование телефонов клиентов

В таблице `customers` поле `phone` хранит персональные данные. Добавим зашифрованное поле:

```sql
ALTER TABLE customers ADD COLUMN IF NOT EXISTS phone_encrypted BYTEA;

-- В данных лаб. 06 телефон не заполнялся (вставлялись только name, email, region).
-- Подготовим тестовые номера, иначе шифровать будет нечего.
UPDATE customers
SET    phone = '+7-900-' || lpad((id % 10000000)::text, 7, '0')
WHERE  phone IS NULL;

-- Шифровать телефон (симметричный ключ AES)
UPDATE customers
SET    phone_encrypted = pgp_sym_encrypt(phone, 'secret_key_2024')
WHERE  phone IS NOT NULL;

-- Проверить: зашифрованные данные выглядят как байты
SELECT id, phone, phone_encrypted FROM customers LIMIT 3;
```

### 3.3. Расшифровка

```sql
-- Расшифровать — только тот, кто знает ключ, получит данные
SELECT id, name,
       pgp_sym_decrypt(phone_encrypted, 'secret_key_2024') AS phone_decrypted
FROM   customers;
```

### 3.4. Права доступа к зашифрованным данным

```sql
-- Аналитик НЕ должен видеть незашифрованный phone
-- Убедиться, что колонка phone уже защищена (или обнулить)
UPDATE customers SET phone = '***';

-- Аналитик видит маскированный phone
SET ROLE analyst_ivanova;
SET app.current_region = 'MSK';   -- без этого RLS-политика вернёт 0 строк
SELECT name, phone, phone_encrypted FROM customers;
-- phone_encrypted — байты, прочитать без ключа нельзя
RESET ROLE;
```

> **Почему нужен `SET app.current_region`.** В лаб. 02 включена RLS-политика `customers_by_region`, которая сравнивает `region` с `current_setting('app.current_region', true)`. Если параметр не задан, выражение равно `NULL`, и аналитик не увидит ни одной строки. Это не ошибка прав — это работающая защита.

> **В production:** ключ шифрования хранится НЕ в SQL, а в Vault/HSM. Передаётся приложением при каждом запросе.

---

## Часть 4. ИБ-чек-лист для eshop

Заполните чек-лист (сохраните как `ib_checklist.md`):

```markdown
## ИБ-чек-лист: eshop

### Аутентификация и авторизация
- [ ] Метод аутентификации в pg_hba.conf: scram-sha-256 (не trust, не md5)
- [ ] Нет пользователей с пустым паролем
- [ ] Роли разделены: readonly / app / dba
- [ ] RLS включён для чувствительных таблиц: customers ✓

### Сеть и транспорт
- [ ] SSL включён: ssl = on ✓
- [ ] Для приложения: hostssl в pg_hba.conf ✓
- [ ] Порт 5432 не открыт наружу (только через VPN / jump-host)

### Аудит
- [ ] pgaudit установлен и настроен: pgaudit.log = 'write,ddl,role'
- [ ] Логи аудита хранятся отдельно и не перезаписываются
- [ ] Период хранения логов: 1 год (требование 152-ФЗ)

### Шифрование данных
- [ ] Поля с персональными данными (phone) зашифрованы: pgcrypto ✓
- [ ] Ключ шифрования НЕ хранится в БД
- [ ] Резервные копии зашифрованы (gpg -r / openssl)

### 152-ФЗ (персональные данные)
- [ ] Локализация: PostgreSQL установлен на серверах в РФ
- [ ] Категория ПДн: общие (ФИО, email, phone) — 3-й уровень защищённости
- [ ] Документ «Согласие на обработку ПДн» подписан пользователями
- [ ] Назначен ответственный за обработку ПДн

### Статус на дату проверки
Дата: ___  
Проверил: ___  
Замечания: ___
```

---

## Чек-лист «работа зачтена»

- [ ] `pgaudit` установлен; строки с `AUDIT` появляются в логе после INSERT/DDL.
- [ ] `ssl = on`; `pg_stat_ssl` показывает `ssl = true` для текущего соединения.
- [ ] `pgcrypto` установлен; `phone_encrypted` заполнен зашифрованными значениями.
- [ ] Расшифровка работает: `pgp_sym_decrypt` возвращает исходный телефон.
- [ ] `ib_checklist.md` заполнен.

---

## Самостоятельное задание

1. Добавьте аудит на операцию `SELECT` для таблицы `customers`. Убедитесь, что SELECT аналитиком оставляет след в логе.
2. Как называется уровень защищённости ПДн для eshop по 152-ФЗ (ФИО + email + телефон)? Какие организационные меры требуются?
3. Что нужно изменить, если ключ шифрования скомпрометирован?

---

## Ссылки

- pgAudit (исходный проект): https://github.com/pgaudit/pgaudit
- Неофициальные Windows x64-сборки pgAudit: https://github.com/pgextwin/pgaudit
- Windows-релиз для установки в п. 1.1: https://github.com/pgextwin/pgaudit/releases/tag/v18.0-windows.2
- pg_stat_ssl: https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STAT-SSL-VIEW
- pgcrypto: https://www.postgresql.org/docs/current/pgcrypto.html
- 152-ФЗ (регулятор): https://pd.rkn.gov.ru/
