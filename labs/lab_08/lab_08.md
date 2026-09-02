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
- Прочитана лек. 11.

---

## Часть 1. pgAudit: аудит действий в БД

### 1.1. Установить расширение

```bash
# Linux (Debian/Ubuntu)
apt-get install postgresql-17-pgaudit

# После установки добавить в postgresql.conf:
# shared_preload_libraries = 'pgaudit'
# И перезапустить PostgreSQL
```

```sql
-- После перезапуска — создать расширение
CREATE EXTENSION pgaudit;

-- Проверить
SELECT * FROM pg_extension WHERE extname = 'pgaudit';
```

### 1.2. Настройка сессионного аудита

В `postgresql.conf` добавьте:

```ini
pgaudit.log = 'write, ddl, role'
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
```bash
# Linux
grep "AUDIT" /var/log/postgresql/postgresql-$(date +%Y-%m-%d).log | tail -20

# Windows
findstr "AUDIT" "C:\Program Files\PostgreSQL\17\data\log\postgresql-2024-09-01.log"
```

Пример строки аудита:
```
2024-09-01 15:30:00 MSK [1234]: [1-1] user=postgres,db=eshop AUDIT: SESSION,1,1,WRITE,INSERT,TABLE,public.customers,...
```

### 1.4. Объектный аудит через роль

Для аудита только конкретных таблиц (более гранулярно):

```sql
-- Создать роль-аудитор
CREATE ROLE eshop_auditor;
GRANT SELECT ON customers, orders TO eshop_auditor;

-- Настроить pgaudit для этой роли
SET pgaudit.role = 'eshop_auditor';
```

В `postgresql.conf`:
```ini
pgaudit.role = 'eshop_auditor'
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

```bash
# Linux
openssl req -new -x509 -days 365 -nodes \
    -out /etc/ssl/certs/pg_server.crt \
    -keyout /etc/ssl/private/pg_server.key \
    -subj "/CN=localhost"

cp /etc/ssl/certs/pg_server.crt $PGDATA/server.crt
cp /etc/ssl/private/pg_server.key $PGDATA/server.key
chmod 600 $PGDATA/server.key
chown postgres:postgres $PGDATA/server.key
```

### 2.3. Принудительное использование SSL в pg_hba.conf

```
# Заменить в pg_hba.conf (только SSL-соединения для app_backend):
hostssl  eshop  app_backend  127.0.0.1/32  scram-sha-256
```

```sql
SELECT pg_reload_conf();

-- Проверить
SELECT ssl, usename FROM pg_stat_ssl
JOIN pg_stat_activity USING (pid)
WHERE usename = 'app_backend';
-- ssl = true
```

### 2.4. Проверить через psql

```bash
psql "host=localhost dbname=eshop user=app_backend sslmode=require"
# Должно подключиться без ошибок

psql "host=localhost dbname=eshop user=app_backend sslmode=disable"
# Должна быть ошибка: SSL required
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
ALTER TABLE customers ADD COLUMN phone_encrypted BYTEA;

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
SELECT name, phone, phone_encrypted FROM customers;
-- phone_encrypted — байты, прочитать без ключа нельзя
RESET ROLE;
```

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

- pgAudit: https://github.com/pgaudit/pgaudit
- pg_stat_ssl: https://www.postgresql.org/docs/current/monitoring-stats.html#MONITORING-PG-STAT-SSL-VIEW
- pgcrypto: https://www.postgresql.org/docs/current/pgcrypto.html
- 152-ФЗ (регулятор): https://pd.rkn.gov.ru/
