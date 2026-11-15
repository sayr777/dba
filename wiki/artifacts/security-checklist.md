# ИБ-чек-лист PostgreSQL

**Источник:** лаб. 08 — «Информационная безопасность»  
**Кто создаёт:** системный аналитик совместно с DBA  
**Периодичность:** при вводе в эксплуатацию, ежегодно, после инцидента

---

## Зачем этот документ

Безопасность PostgreSQL из коробки — небезопасна (trust-авторизация, нет SSL, нет аудита). Чек-лист формализует минимальный уровень защиты для production и требования 152-ФЗ.

> **Запомнить:** 152-ФЗ (персональные данные) применяется к любой БД, содержащей ФИО, телефон, email, адрес. eshop подпадает. Ответственность — на операторе ПДн (организации).

---

## Чек-лист

### Блок 1: Аутентификация и авторизация

```markdown
- [ ] Метод аутентификации: scram-sha-256 (не md5, не trust)
      Проверить: grep "host" $PGDATA/pg_hba.conf
      Ожидаемое: host all all 0.0.0.0/0 scram-sha-256

- [ ] Нет пользователей с пустым паролем
      SQL: SELECT usename FROM pg_shadow WHERE passwd IS NULL OR passwd = '';
      Ожидаемое: 0 строк

- [ ] Суперпользователь postgres не используется приложением
      SQL: SELECT datname, usename FROM pg_stat_activity WHERE usename = 'postgres';
      Ожидаемое: только psql/DBA-сессии

- [ ] Роли разделены: readonly / app / admin
      SQL: \du в psql или SELECT * FROM pg_roles;

- [ ] RLS включён на таблицах с ПДн
      SQL: SELECT relname, relrowsecurity FROM pg_class WHERE relname IN ('customers');
      Ожидаемое: relrowsecurity = true
```

### Блок 2: Сеть и транспорт

```markdown
- [ ] SSL включён
      SQL: SHOW ssl;
      Ожидаемое: on

- [ ] В pg_hba.conf используется hostssl вместо host
      Проверить: grep "^host" $PGDATA/pg_hba.conf
      Ожидаемое: строки начинаются с hostssl

- [ ] Порт 5432 не открыт напрямую в интернет
      Команда: netstat -tlnp | grep 5432
      Ожидаемое: 127.0.0.1:5432 или внутренний IP

- [ ] listen_addresses не равен '*' без файрволла
      SQL: SHOW listen_addresses;
```

### Блок 3: Аудит

```markdown
- [ ] pgAudit установлен и подключён
      SQL: SELECT * FROM pg_extension WHERE extname = 'pgaudit';
      Конфиг: shared_preload_libraries = 'pgaudit'

- [ ] Логируются DDL и изменения ролей
      Конфиг: pgaudit.log = 'write,ddl,role'

- [ ] Логи хранятся отдельно от данных (другой диск/сервер)

- [ ] Срок хранения логов: не менее 1 года (требование 152-ФЗ для ПДн 3-го уровня)
      Реализация: logrotate / rsyslog / централизованный SIEM
```

### Блок 4: Шифрование данных

```markdown
- [ ] Чувствительные поля (телефон, email) зашифрованы
      SQL: SELECT pg_column_size(pgp_sym_encrypt('test','key')) FROM (SELECT 1) t;
      Расширение: pgcrypto (CREATE EXTENSION pgcrypto)

- [ ] Ключ шифрования НЕ хранится в БД
      Хранится в: переменная окружения / HashiCorp Vault / секреты K8s

- [ ] Бэкапы зашифрованы
      Команда: pg_dump ... | openssl enc -aes-256-cbc -out backup.enc
```

### Блок 5: Требования 152-ФЗ

```markdown
- [ ] Данные локализованы на территории РФ (серверы в РФ или сертифицированное облако)

- [ ] Определена категория ПДн: общие (3-й уровень защищённости)
      Проверить: есть ли в БД: ФИО + хотя бы один из (телефон, email, адрес)

- [ ] Разработана и принята модель угроз

- [ ] Получено согласие субъектов на обработку ПДн

- [ ] Назначен ответственный за обработку ПДн (должностное лицо)

- [ ] Реестр ПДн актуален
```

---

## Результат проверки

```markdown
Дата проверки: __________  
Проверял: __________  

| Блок                     | Статус     | Замечания |
|--------------------------|------------|-----------|
| Аутентификация           | ✓ / ✗      |           |
| Сеть и транспорт         | ✓ / ✗      |           |
| Аудит                    | ✓ / ✗      |           |
| Шифрование               | ✓ / ✗      |           |
| 152-ФЗ                   | ✓ / ✗      |           |
```

---

## Ключевые команды

```sql
-- Проверить метод авторизации для активных сессий:
SELECT usename, ssl, client_addr
FROM pg_stat_ssl
JOIN pg_stat_activity USING (pid);

-- Показать все роли и их флаги:
SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolcanlogin
FROM pg_roles
ORDER BY rolsuper DESC;

-- Политики RLS:
SELECT tablename, policyname, cmd, roles, qual
FROM pg_policies;

-- Проверить pgAudit в логах:
grep "AUDIT:" $PGDATA/log/postgresql-*.log | tail -20
```

---

## Частые ошибки

| Ошибка | Последствие | Исправление |
|--------|-------------|-------------|
| `pg_hba.conf`: `trust` для localhost | Любой локальный пользователь без пароля | Заменить на `scram-sha-256` |
| SSL выключен (ssl=off) | Пароли передаются открытым текстом | `ssl=on` в postgresql.conf + сертификат |
| pgAudit не в shared_preload_libraries | Аудит не работает после установки | Перезапустить PostgreSQL |
| Ключ шифрования в таблице eshop | При утечке БД — утечка ключа | Вынести в переменную среды / Vault |

---

> **Связанные страницы:** [[concepts/security]], [[concepts/access-control-models]], [[artifacts/access-matrix]]
