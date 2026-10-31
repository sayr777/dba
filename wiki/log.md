# Wiki Change Log

Append-only. Add new entries at the top.

---

## [2026-10-31] add | Полное лекторское изложение 10 лекций + 8 новых статей

**Лекции (sources):**
- `lec_01`–`lec_07`, `lec_11`–`lec_13` расширены из тезисов в полноценное лекторское изложение: вводные кейсы, разбор причин, пошаговые процедуры, типичные ошибки, контрольные вопросы.
- Во все лекции добавлены ссылки на соответствующие лабораторные работы (`lab_01`–`lab_10`) и перекрёстные ссылки на wiki.

**Новые концептуальные статьи (`concepts/`):**
- `concepts/erd.md`: нотация Crow's Foot, кардинальность, чек-лист проверки ERD перед миграцией.
- `concepts/privileges.md`: иерархия привилегий, GRANT/REVOKE, DEFAULT PRIVILEGES, владение, колонки.
- `concepts/transaction-isolation.md`: уровни изоляции, аномалии, write skew, обработка `serialization_failure`.
- `concepts/pitr.md`: требования, цели восстановления, LSN, timeline, отдельный экземпляр.
- `concepts/audit.md`: pgAudit, категории событий, правила безопасного логирования.

**Новые статьи по инструментам (`tools/`):**
- `tools/pg-dump.md`: форматы, флаги, ограничения, проверка восстановления.
- `tools/pg-basebackup.md`: физическая копия, standby, инкрементальные копии, восстановление.
- `tools/pg-upgrade.md`: мажорное обновление, `--check`, расширения, альтернатива через логическую репликацию.

**Служебные файлы:**
- `glossary.md`: добавлены 14 терминов (archive_mode, checksum, Column-level privilege, DEFAULT PRIVILEGES, hostssl, log_line_prefix, log_statement, pg_upgrade, pg_waldump, Read Committed, Repeatable Read, Serializable, Timeline, Transaction isolation, USAGE, Write skew).
- `index.md`: обновлены разделы Concepts и Tools.

---

## [2026-10-29] add | Синхронизация с утверждённой РПД и добавление статей по новым технологиям

**Интеграция с РПД:**
- Создана страница `wiki/course/rpd.md`: нормативный паспорт утверждённой программы (`РПД_Администрирование_баз_данных_утв.docx`), матрица компетенций ПК-1, ПК-3, ПК-5 и всех 6 индикаторов УП ГУУ со сквозной линковкой на лекции, лабораторные и статьи базы знаний.
- Слинкованы `wiki/course/lectures-overview.md` и `wiki/course/labs-overview.md` со страницей РПД.

**Новые статьи по технологиям и инструментам (`tools/`):**
- `tools/psql.md`: CLI-интерфейс PostgreSQL, флаги подключения, метакоманды (`\d`, `\l`, `\x`), автоматизация и безопасный запуск сценариев миграций.
- `tools/patroni.md`: HA-оркестратор отказоустойчивости PostgreSQL, распределённый консенсус DCS (etcd), автоматический failover, switchover и защита от split-brain.
- `tools/pgaudit.md`: расширение аудита безопасности PostgreSQL, сессионный и объектный аудит, соответствие 152-ФЗ.
- `tools/pgbench.md`: нагрузочное тестирование и бенчмаркинг TPC-B, замеры TPS и latency, валидация настроек пула соединений PgBouncer.

**Новые концептуальные статьи (`concepts/`):**
- `concepts/locks-concurrency.md`: уровни блокировок (RowShare, Exclusive, AccessExclusive), матрица конфликтов, очередь блокировок (Lock Queue), взаимоблокировки (Deadlocks), таймауты `lock_timeout` и `statement_timeout`.
- `concepts/high-availability.md`: метрики надежности (SLA, MTBF, MTTR, RPO, RTO), архитектура высокой доступности, кворум и защита от split-brain.
- `concepts/dbms-landscape.md`: современный ландшафт СУБД (OLTP, OLAP/ClickHouse, NewSQL, Key-Value/Redis, Vector/pgvector), концепция Polyglot Persistence и выбор аналитика.

**Служебные файлы:**
- `glossary.md`: добавлены 16 новых терминов (AccessExclusiveLock, ClickHouse, deadlock, Lock Queue, lock_timeout, MTBF, MTTR, Patroni, pgbench, pgvector, psql, Redis, SLA, Split-Brain, statement_timeout, switchover). Всего 80 терминов в алфавитном порядке.
- `index.md`: обновлены разделы Concepts, Tools и Course.

---

## [2026-10-28] fix | Аудит wiki (44 файла) + лабораторных (10 файлов)

**Wiki:**
- Удалены `wiki/lectures/lec_03.md` и `wiki/labs/lab_02.md` (source-файлы не должны быть в vault)
- `artifacts/db-health-report.md`: Cache Hit Ratio `> 95%` → `≥ 99%` (противоречие с monitoring.md)
- `artifacts/migration-plan.md` + `artifacts/deployment-runbook.md`: таблица `reviews` и индекс `idx_reviews_product` заменены на `promo_codes` / `idx_promo_codes_code` (соответствие реальному V003 курса); Linux-команды в runbook заменены на PowerShell

**Лабораторные:**
- `lab_02`: добавлен `\c eshop` после `CREATE DATABASE eshop` в psql-пути
- `lab_03`: жёсткая дата `eshop_20240901.dump` → `<имя_вашего_дампа>.dump`; добавлен Windows-путь к pg_hba.conf; предупреждение что `basebackup\` должна не существовать
- `lab_04`: жёсткая дата исправлена; дублирующий `## Часть 2` → `## Часть 3`
- `lab_08`: `shared_preload_libraries = 'pgaudit'` → инструкция добавить через запятую к `pg_stat_statements`
- `lab_10`: неверный SQL с `indexrelname` (не существует) заменён на корректный через `pg_class JOIN pg_index`

---

## [2026-10-28] add | cheatsheets/markdown.md — шпаргалка по Markdown

Создана `cheatsheets/markdown.md`:
- GFM + Obsidian: заголовки, текст, списки, таблицы с выравниванием
- Блоки кода с идентификаторами языков (sql, powershell, yaml, mermaid, plantuml)
- Obsidian wiki-ссылки и callout-блоки; сравнение рендера в GitHub vs Obsidian
- YAML frontmatter для Marp-презентаций
- Таблица частых ошибок
- Обновлён `index.md`: добавлена строка в раздел Cheatsheets

---

## [2026-10-28] add | roles/team-roles.md — командные роли и взаимодействие с SA

Создана `roles/team-roles.md`:
- Описание 6 ролей: DBA, SA, PM, BE, RND, DevOps — зона ответственности и границы
- Mermaid-схема взаимодействия SA со всеми ролями
- 11 use stories: SA+DBA (3), SA+PM (2), SA+BE (2), SA+RND (2), SA+DevOps (2)
- Сводная таблица: SA как связующее звено (что получает / что отдаёт)
- Принцип минимального знания — кто за что отвечает, не перекрывая соседей
- Обновлён `index.md`: добавлена строка в раздел Roles

---

## [2026-10-28] update | wiki/README.md — ссылки на Habr и llm-wiki.net

Вводной блок расширен: добавлены https://habr.com/ru/articles/1031970/ и https://llm-wiki.net/
рядом с гистом Карпаты. Добавлена таблица `## Ссылки` в конце файла.

---

## [2026-10-28] update | labs + lectures — Windows-совместимость, ссылки, бидиректные связи

Обновлены все 10 лабораторных (lab_01–lab_10) и 11 лекций (lec_02–lec_07, lec_08–lec_09, lec_11–lec_13):

- **Windows (PowerShell)**: все `pg_dump`, `pg_restore`, `psql`, `vacuumdb`, `reindexdb` заменены на `& "$pg\*.exe"` с переменной `$pg = "C:\Program Files\PostgreSQL\18\bin"` (lab_03, lab_04, lab_07, lab_08, lab_10)
- **PostgreSQL 18**: исправлены остаточные ссылки на версию 17 (lab_01, lab_08)
- **pgAudit (Windows)**: инструкция apt-get заменена на EDB Stack Builder (lab_08)
- **SSL (Windows)**: инструкция openssl/chmod/chown заменена на Git Bash / PowerShell + icacls (lab_08)
- **pgBadger**: инструкция grep заменена на PowerShell Get-ChildItem + Select-String (lab_08)
- **Flyway (Windows)**: добавлены пошаговые инструкции установки ZIP + PATH (lab_09, wiki/tools/flyway.md)
- **Метки командной строки**: добавлены `> **Командная строка (psql / PowerShell).**` перед PowerShell-блоками
- **Ссылки labs → lectures**: добавлены ссылки на конкретные разделы лекций в начале каждой лабораторной
- **Ссылки lectures → labs**: добавлены blockquote `> **Практика →**` перед «Итоги лекции» в каждой лекции
- **wiki/tools/flyway.md**: добавлен раздел «Установка (Windows)»

---

## [2026-10-28] add | course/trainer.md — тренажёр-собеседник по курсу

Создана `course/trainer.md`:
- Концепция: свободный диалог студента с агентом (не формальный экзамен)
- Три режима в одном разговоре: Экзамен / Оценка / Объяснение (stateDiagram)
- Готовый системный промпт с банком 23 вопросов и правилами поведения агента
- Запуск: Claude (claude.ai, API), Ollama CLI + Python-скрипт, Obsidian Smart Connections
- Пример диалога с переходом из режима экзамена в режим объяснения WAL
- Таблица: блок вопросов → wiki-страницы для объяснений
- Обновлены `index.md`, `log.md`

---

## [2026-10-28] update | tools/obsidian.md — инструкция установки Git и клонирования репозитория

Добавлен раздел «Установка и первый запуск» (5 шагов):
- Шаг 1: установка Git (Windows / macOS / Linux) с проверкой версии
- Шаг 2: git clone https://github.com/sayr777/dba + структура после клонирования
- Шаг 3: установка Obsidian (ссылка на загрузку)
- Шаг 4: Open folder as vault → dba/wiki + Mermaid-схема всего пути
- Шаг 5: git pull для получения обновлений

---

## [2026-10-28] add | tools/obsidian.md — статья об Obsidian как IDE для wiki

Создана `tools/obsidian.md`:
- Core-плагины vault (graph, backlink, outgoing-link, canvas, showOrphans:true)
- Community-плагины с конфигурацией Ollama: Smart Connections, Text Generator, Dataview, Marp
- Workflows: Ingest / Query / Lint с шагами и горячими клавишами
- Настройки редактора и Files & Links для wiki

Обновлены входящие ссылки: `README.md` (3 места), `index.md`, `cheatsheets/mermaid.md`

---

## [2026-10-28] add | Создан README.md с описанием подхода LLM-wiki

Добавлен `wiki/README.md`: концепция Карпаты, трёхслойная архитектура (sources/wiki/schema),
структура директорий, три режима работы (Ingest/Query/Lint), принцип накопления знаний,
разделение ролей преподаватель/LLM/wiki, технические детали.

---

## [2026-10-28] schema | Переписан schema.md как LLM-инструкция (CLAUDE.md-стиль)

Старый schema.md описывал структуру. Новый — говорит LLM что делать:
- Раздел 7 расширен: добавлены workflows Ingest (7.4), Query→страница (7.5), Lint (7.6)
- Lint: таблица 6 типов проблем с критерием обнаружения и способом исправления
- Ingest: полный цикл из 7 шагов; описан интерактивный vs batch-режим
- Query: правило «ответ длиннее 5 предложений → создай страницу»
- Раздел 9: инструкция по эволюции schema.md самим LLM
- Раздел 10: quick-start для новой сессии (4 шага)

---

## [2026-10-28] add | Раздел artifacts — документы из лабораторных работ

Добавлено:
- `artifacts/index.md` — каталог 10 артефактов с указанием источника (лаб.) и получателя
- `artifacts/access-matrix.md` — матрица доступа: GRANT + RLS шаблоны, ловушки (лаб. 02)
- `artifacts/backup-policy.md` — регламент бэкапов: pg_dump форматы, RPO/RTO (лаб. 03)
- `artifacts/failover-runbook.md` — runbook инцидента: 2 сценария, дерево решений Mermaid (лаб. 04)
- `artifacts/db-health-report.md` — отчёт о состоянии БД: pg_stat_* запросы, шаблон (лаб. 05)
- `artifacts/explain-analysis.md` — анализ запроса: EXPLAIN термины, словарь, pg_stat_statements (лаб. 06)
- `artifacts/pgbouncer-justification.md` — обоснование PgBouncer: режимы, ограничения, pgbench (лаб. 07)
- `artifacts/security-checklist.md` — ИБ-чек-лист: 5 блоков, 152-ФЗ требования (лаб. 08)
- `artifacts/migration-plan.md` — план миграции: шаблон + правила именования Flyway (лаб. 09)
- `artifacts/deployment-runbook.md` — runbook деплоя: 5 этапов, stateDiagram состояний (лаб. 09)
- `artifacts/project-report.md` — итоговый отчёт: 9 разделов + 10 экзаменационных вопросов (лаб. 10)
- `index.md` обновлён: добавлен раздел Artifacts

---

## [2026-10-28] add | Шпаргалки и статья об управлении доступом

Добавлено:
- `concepts/access-control-models.md` — DAC, RBAC (NIST уровни), ABAC/RLS, MAC, ReBAC; алгоритм выбора модели; источники: lec_03, lec_04
- `cheatsheets/mermaid.md` — flowchart (направления, формы, стрелки, subgraph), erDiagram (атрибуты, кардинальность), stateDiagram-v2; примеры из курса
- `cheatsheets/git.md` — настройка, базовый workflow, ветвление, rebase, stash, MR-процесс для миграций Flyway, .gitignore
- `index.md` обновлён: добавлены разделы Cheatsheets и новая строка в Concepts

---

## 2026-10-28 — Initial generation

Created complete wiki from sources: lec_01–lec_13, lab_01–lab_10, docs/exam.md, docs/reports.md, README.md.

Pages created:
- `schema.md`, `index.md`, `log.md`, `glossary.md`
- `concepts/postgresql-architecture.md`
- `concepts/wal-mvcc.md`
- `concepts/indexes.md`
- `concepts/backup-recovery.md`
- `concepts/replication.md`
- `concepts/security.md`
- `concepts/monitoring.md`
- `concepts/connection-pooling.md`
- `tools/flyway.md`
- `tools/pgbadger.md`
- `tools/pgbouncer.md`
- `tools/dbeaver.md`
- `procedures/migration-workflow.md`
- `procedures/rollback-strategies.md`
- `procedures/zero-downtime.md`
- `procedures/failover-runbook.md`
- `roles/dba-vs-sa.md`
- `course/lectures-overview.md`
- `course/labs-overview.md`
- `course/eshop-schema.md`
