# Источник комплекта pgAudit для лабораторной №8

Неофициальная Windows x64-сборка pgAudit 18.0 для PostgreSQL 18. Файлы распакованы из опубликованного архива без изменения; этот файл добавлен для фиксации источника.

- Репозиторий: https://github.com/pgextwin/pgaudit
- Релиз: https://github.com/pgextwin/pgaudit/releases/tag/v18.0-windows.2
- Архив: https://github.com/pgextwin/pgaudit/releases/download/v18.0-windows.2/pgaudit-18.0-pg18-windows-x64.zip
- SHA-256 исходного архива: `a0aff6be2ef840bfb105eb8143e6338b49476b908d75858fd31e8acdd7926a26`

При скачивании SHA-256 архива проверен и совпал с digest, опубликованным в GitHub Releases. Это проверка целостности, а не гарантия безопасности или совместимости. Работа DLL на локальном сервере не проверялась.

## Файлы для установки

| Файл в комплекте | Каталог назначения |
| --- | --- |
| `lib/pgaudit.dll` | `C:\Program Files\PostgreSQL\18\lib\` |
| `share/extension/pgaudit.control` | `C:\Program Files\PostgreSQL\18\share\extension\` |
| `share/extension/pgaudit--18.0.sql` | `C:\Program Files\PostgreSQL\18\share\extension\` |

Порядок остановки службы, настройки и запуска описан в [лабораторной №8](../lab_08.md#11-установить-расширение). Перед установкой сделайте резервную копию учебной БД и конфигурации. Не используйте этот комплект для других мажорных версий PostgreSQL.

В комплекте сохранены оригинальные `LICENSE`, `PACKAGE-INFO.txt`, `PACKAGE-INFO.json` и документация поставщика.
