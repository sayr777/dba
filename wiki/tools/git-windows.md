# Настройка Git для Windows

## Шаг 1. Скачивание

1. Перейдите на [git-scm.com/downloads](https://git-scm.com/downloads)
2. Скачайте установщик для Windows (Auto-detect — обычно подходит)
3. Или скачайте напрямую: [git-scm.com/downloads/win](https://git-scm.com/download/win)

## Шаг 2. Установка

Запустите скачанный `.exe` файл и следуйте мастеру установки.

### Ключевые настройки в мастере

| Шаг | Настройка | Рекомендация | Почему |
|-----|-----------|--------------|--------|
| Components | Компоненты | Оставьте всё по умолчанию | Все компоненты нужны |
| Start Menu | Ярлыки | Оставьте по умолчанию | — |
| Explorer Integration | Контекстное меню | **✓** Все пункты | Удобно через правый клик |
| Git Bash Default | Терминал по умолчанию | **Use Git Bash only** | Git Bash — Unix-подобный терминал |
| HTTPS Backend | HTTPS | **Use OpenSSL library** | Совместимость с GitHub/GitLab |
| Line Endings | Переносы строк | **Checkout Windows-style, commit Unix-style** | Избежит проблем при работе на Windows |
| Terminal | Эмулятор | **Use Windows' default console window** | Лучше поддержка цветов |
| Extra | Дополнительно | Оставьте по умолчанию | — |

## Шаг 3. Проверка установки

Откройте **Git Bash** (через меню Пуск) и выполните:

```bash
git --version
```

Должно вывести что-то вроде: `git version 2.47.0.windows.1`

## Шаг 4. Первичная настройка

Выполните в Git Bash (замените данные на свои):

```bash
# Имя и email (те же, что в GitHub/GitVerse)
git config --global user.name "Иван Иванов"
git config --global user.email "ivanov@example.com"

# Кодировка
git config --global core.quotepath false
git config --global gui.encoding utf-8

# Переносы строк
git config --global core.autocrlf true

# Терминал
git config --global core.pager "less -R"

# Проверка
git config --global --list
```

## Шаг 5. Настройка SSH-ключей (рекомендуется)

### 5.1. Проверка существующих ключей

```bash
ls ~/.ssh/id_*.pub
```

Если файлы есть — переходите к шагу 5.3.

### 5.2. Генерация нового ключа

```bash
ssh-keygen -t ed25519 -C "ivanov@example.com"
```

Нажмите Enter для сохранения в стандартное место. При желании задайте пароль (passphrase).

### 5.3. Добавление ключа в буфер обмена

```bash
# Скопировать публичный ключ
cat ~/.ssh/id_ed25519.pub | clip
```

### 5.4. Добавление ключа в GitHub/GitVerse

1. Откройте GitHub → Settings → SSH and GPG keys
2. Нажмите **New SSH key**
3. Вставьте ключ из буфера обмена
4. Назовите (например: "Windows Laptop")
5. Нажмите **Add SSH key**

### 5.5. Проверка подключения

```bash
ssh -T git@github.com
```

Должно вывести: `Hi ivanov! You've successfully authenticated...`

## Шаг 6. VS Code (опционально)

Если используете VS Code:

1. Установите [VS Code](https://code.visualstudio.com/)
2. VS Code автоматически подхватит Git
3. Проверьте: `Ctrl+Shift+P` → «Git: Status»

## Частые проблемы

### «git не найден»

Добавьте Git в PATH:
1. Перезапустите Git Bash
2. Или: Пуск → Git → Git Bash

### Проблемы с кодировкой

```bash
git config --global core.quotepath false
git config --global gui.encoding utf-8
```

### Ошибка SSL при clone

```bash
git config --global http.sslBackend openssl
```

### Конфликт переносов строк

```bash
git config --global core.autocrlf true
```
