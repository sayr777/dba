# Артефакты лабораторных работ

> Документы, которые студент создаёт в ходе курса. Каждый артефакт — реальный рабочий инструмент системного аналитика.

## Все артефакты

| Артефакт | Назначение | Лаб. | Файл |
|----------|-----------|------|------|
| Матрица доступа + требования к ролям | Передаётся DBA для настройки GRANT/REVOKE и pg_hba.conf | 02 | [access-matrix.md](access-matrix.md) |
| Регламент резервного копирования | Фиксирует стратегию бэкапов: частоту, форматы, сроки хранения | 03 | [backup-policy.md](backup-policy.md) |
| Failover Runbook | Пошаговые действия при отказе БД; роль аналитика vs DBA | 04 | [failover-runbook.md](failover-runbook.md) |
| Отчёт о состоянии БД | Заполняется числами по метрикам pg_stat_*; основа для алертов | 05 | [db-health-report.md](db-health-report.md) |
| Анализ медленного запроса | Структурированный отчёт по EXPLAIN ANALYZE + pg_stat_statements | 06 | [explain-analysis.md](explain-analysis.md) |
| Обоснование PgBouncer | Аргументированный документ для архитектурного решения | 07 | [pgbouncer-justification.md](pgbouncer-justification.md) |
| ИБ-чек-лист | Проверка защищённости БД: auth, audit, TLS, crypto, 152-ФЗ | 08 | [security-checklist.md](security-checklist.md) |
| Migration Plan | Описание изменений схемы до открытия MR; читается DBA и тимлидом | 09 | [migration-plan.md](migration-plan.md) |
| Runbook деплоя | Пошаговая инструкция для production-деплоя миграции | 09 | [deployment-runbook.md](deployment-runbook.md) |
| Итоговый отчёт по проекту | Портфолио eshop для зачёта: все 8 разделов курса | 10 | [project-report.md](project-report.md) |

## Когда что создавать

```
Лаб. 02 → access-matrix.md        (до запроса к DBA на создание ролей)
Лаб. 03 → backup-policy.md         (регламент бэкапов)
Лаб. 04 → failover-runbook.md      (до первого инцидента)
Лаб. 05 → db-health-report.md      (после каждого мониторинга)
Лаб. 06 → explain-analysis.md      (при анализе медленного запроса)
Лаб. 07 → pgbouncer-justification  (перед внедрением пулера)
Лаб. 08 → security-checklist.md    (аудит ИБ)
Лаб. 09 → migration-plan.md        (до открытия MR с миграцией)
         → deployment-runbook.md   (в день деплоя)
Лаб. 10 → project-report.md        (итоговый отчёт для зачёта)
```

> **Связанные страницы:** [[procedures/migration-workflow]], [[concepts/access-control-models]], [[concepts/security]]
