# Шпаргалка: Git

Команды, необходимые системному аналитику для работы с миграциями и совместной разработки через MR.

---

## 1. Первоначальная настройка

```bash
git config --global user.name  "Имя Фамилия"
git config --global user.email "email@example.com"
git config --global core.editor "code --wait"    # VS Code как редактор
git config --list                                 # проверить настройки
```

---

## 2. Базовый рабочий цикл

```bash
git status                   # что изменилось
git diff                     # изменения в unstaged файлах
git diff --staged            # изменения в staged файлах

git add <файл>               # добавить конкретный файл
git add migrations/          # добавить всю папку
git add -p                   # интерактивно выбирать части изменений

git commit -m "feat: add orders table migration V003"
git push origin <ветка>      # отправить изменения в remote
git pull --rebase            # получить изменения и перебазировать
```

---

## 3. Ветвление

```bash
git branch                          # список веток (локальные)
git branch -a                       # все ветки (включая remote)

git switch -c feature/add-orders    # создать и переключиться (современный синтаксис)
git checkout -b feature/add-orders  # то же, старый синтаксис

git switch main                     # переключиться на main
git switch -                        # вернуться на предыдущую ветку

git branch -d feature/add-orders    # удалить ветку после merge
git push origin --delete feature/add-orders  # удалить remote-ветку
```

---

## 4. Просмотр истории

```bash
git log                             # полная история
git log --oneline                   # сжатый вид (1 строка на коммит)
git log --oneline --graph --all     # дерево веток

git log --oneline -10               # последние 10 коммитов
git log --follow migrations/        # история папки
git log --author="Иванова"          # коммиты конкретного автора

git show <hash>                     # подробности коммита
git show HEAD                       # последний коммит
git show HEAD~2                     # 2 коммита назад
```

---

## 5. Сравнение

```bash
git diff main..feature/add-orders         # разница между ветками
git diff HEAD~1                           # изменения последнего коммита
git diff <hash1> <hash2>                  # между двумя коммитами
git diff --name-only main..HEAD           # только имена изменённых файлов
```

---

## 6. Отмена изменений

```bash
# Ещё не добавлено в index (unstaged)
git restore <файл>                  # отменить изменения в файле
git restore .                       # отменить все изменения в рабочей директории

# Добавлено в index (staged), но не закоммичено
git restore --staged <файл>         # убрать из staged, сохранить изменения
git reset HEAD <файл>               # то же, старый синтаксис

# Уже закоммичено
git revert <hash>                   # новый коммит, отменяющий изменения (безопасно)
git reset --soft HEAD~1             # отменить коммит, сохранить изменения staged
git reset --mixed HEAD~1            # отменить коммит, сохранить изменения unstaged
# git reset --hard — ДЕСТРУКТИВНО, безвозвратно удаляет изменения
```

> **Правило:** `git revert` — безопасный способ отмены опубликованных коммитов.  
> `git reset --hard` — только для локальных, ещё не запушенных изменений.

---

## 7. Stash — временное сохранение

```bash
git stash                           # убрать незакоммиченные изменения «в ящик»
git stash push -m "WIP: V004 draft" # с именем
git stash list                      # список stash-ей
git stash pop                       # восстановить последний stash (и удалить из списка)
git stash apply stash@{1}           # восстановить конкретный stash (не удалять)
git stash drop stash@{0}            # удалить stash
git stash clear                     # удалить все stash-и
```

---

## 8. Remote-репозитории

```bash
git remote -v                        # список remote
git remote add origin <url>          # добавить remote
git fetch origin                     # скачать изменения без слияния
git pull origin main                 # fetch + merge
git pull --rebase origin main        # fetch + rebase (предпочтительно)
git push -u origin feature/my-branch # первый push с привязкой upstream
```

---

## 9. Merge и Rebase

```bash
# Merge: сохраняет историю веток
git switch main
git merge feature/add-orders
git merge --no-ff feature/add-orders   # всегда создавать merge-коммит

# Rebase: линейная история (перед отправкой в MR)
git switch feature/add-orders
git rebase main                         # перебазировать на актуальный main
# При конфликте:
git add <файл>
git rebase --continue
# Для отмены:
git rebase --abort
```

---

## 10. Теги

```bash
git tag                              # список тегов
git tag v1.0.0                       # лёгкий тег на текущий коммит
git tag -a v1.0.0 -m "Release 1.0"  # аннотированный тег
git push origin v1.0.0               # запушить тег
git push origin --tags               # запушить все теги
git tag -d v1.0.0                    # удалить тег локально
```

---

## 11. Поиск и диагностика

```bash
git blame <файл>                     # кто и когда изменил каждую строку
git log -S "orders_discount"         # найти коммит, где появилась строка
git log --grep="V003"                # найти по сообщению коммита
git bisect start                     # бинарный поиск сломавшего коммита
git bisect bad                       # текущий коммит — плохой
git bisect good <hash>               # <hash> — хороший
git bisect reset                     # завершить bisect
```

---

## 12. Типовой workflow для миграций (Flyway + MR)

```bash
# 1. Создать ветку под задачу
git switch -c feature/V009-add-region-to-orders

# 2. Написать миграцию
# → создать migrations/V009__add_region_to_orders.sql

# 3. Закоммитить
git add migrations/V009__add_region_to_orders.sql
git commit -m "migration: add region column to orders (V009)"

# 4. Актуализировать относительно main
git fetch origin
git rebase origin/main

# 5. Запушить и открыть MR
git push -u origin feature/V009-add-region-to-orders
# → открыть Pull Request / Merge Request в GitHub / GitLab

# 6. После merge — удалить ветку
git switch main
git pull --rebase
git branch -d feature/V009-add-region-to-orders
```

> **Правило именования:** `feature/V{N}-{краткое-описание}` — номер версии Flyway в имени ветки исключает конфликты версий.

---

## 13. .gitignore для проекта с Flyway

```gitignore
# Среды и секреты
.env
*.local

# Flyway history (генерируется автоматически)
flyway.conf        # если содержит пароли

# Дампы и бэкапы — не в git
*.dump
*.backup
*.sql.gz

# IDE
.idea/
.vscode/
*.iml
```

---

## 14. Справочник символов статуса (git status)

| Символ | Значение                                    |
|--------|---------------------------------------------|
| `??`   | Untracked — новый файл, не добавлен в git   |
| `A`    | Added — добавлен в index                    |
| `M`    | Modified — изменён                          |
| `D`    | Deleted — удалён                            |
| `R`    | Renamed — переименован                      |
| `C`    | Copied                                      |
| `U`    | Unmerged — конфликт слияния                 |

---

> **Источники:** [[lectures/lec_12]] (MR-процесс для миграций), [[tools/flyway]]  
> **Связанные страницы:** [[cheatsheets/mermaid]], [[procedures/migration-workflow]]
