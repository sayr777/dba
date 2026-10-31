# Аудит (Audit)

Аудит БД — структурированная фиксация действий с данными и схемой (кто, когда, что сделал), необходимая для расследования инцидентов, соответствия 152-ФЗ и контроля привилегированных операций.

---

## 1. Зачем аудит, если есть лог

Обычный лог PostgreSQL (`log_statement`) пишет либо ничего, либо всё подряд. Он не различает типы событий и может содержать пароли и персональные данные.

`pgAudit` даёт:

- категории событий (`read`, `write`, `ddl`, `role`, `function`, `misc`);
- структурированный формат;
- сессионный и объектный аудит;
- возможность не логировать параметры запросов.

---

## 2. Что аудировать

| Категория | События | Приоритет |
|---|---|---|
| `ddl` | `CREATE`, `ALTER`, `DROP` | Обязательно |
| `role` | `CREATE ROLE`, `GRANT`, `REVOKE` | Обязательно |
| `write` | `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE` | Для ПДн и финансов |
| `read` | `SELECT` | Для таблиц с ПДн |
| `function` | вызовы функций | По необходимости |
| `misc_set` | `SET`, `RESET` | Для расследований |

---

## 3. Настройка

```ini
# postgresql.conf — требует перезапуска
shared_preload_libraries = 'pg_stat_statements,pgaudit'
pgaudit.log = 'ddl, role, write'
pgaudit.log_catalog = off
pgaudit.log_relation = on
pgaudit.log_parameter = off
```

```sql
CREATE EXTENSION pgaudit;
```

Объектный аудит:

```sql
ALTER ROLE analyst_ivanova SET pgaudit.log = 'read';
```

---

## 4. Формат записи

```text
2024-09-01 16:22:33 MSK [12345]: LOG: AUDIT: SESSION,1,1,DDL,DROP TABLE,TABLE,
  public.orders,"DROP TABLE orders",<not logged>
```

Поля: тип аудита, класс, команда, объект, текст, параметры.

---

## 5. Правила безопасного аудита

- Не включайте `log_parameter = on` без необходимости: там могут быть ПДн.
- Защищайте лог-файлы: они содержат чувствительные данные.
- Ротируйте и храните логи в соответствии с политикой.
- Не используйте `log_statement = all` как замену аудиту.
- При инциденте сначала сохраните логи, потом реагируйте.

---

## 6. См. также

- [Безопасность](security.md)
- [pgAudit](../tools/pgaudit.md)
- [ИБ-чек-лист](../artifacts/security-checklist.md)
- [Привилегии](privileges.md)

---

> **Источники:** [[lec_11]], [[lab_08]]
