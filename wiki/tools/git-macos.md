# Настройка Git для macOS

## Шаг 1. Установка через Homebrew (рекомендуется)

### 1.1. Установка Homebrew (если нет)

Откройте **Terminal** и выполните:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Следуйте инструкциям на экране (может потребоваться пароль администратора).

### 1.2. Установка Git

```bash
brew install git
```

## Шаг 1b. Альтернатива: Xcode Command Line Tools

Если не хотите использовать Homebrew:

```bash
xcode-select --install
```

Нажмите «Install» в появившемся окне.

## Шаг 2. Проверка установки

```bash
git --version
```

Должно вывести что-то вроде: `git version 2.47.0`

## Шаг 3. Первичная настройка

Выполните в Terminal (замените данные на свои):

```bash
# Имя и email (те же, что в GitHub/GitVerse)
git config --global user.name "Иван Иванов"
git config --global user.email "ivanov@example.com"

# Кодировка
git config --global core.quotepath false

# Переносы строк (macOS — Unix, LF по умолчанию)
git config --global core.autocrlf input

# Терминал
git config --global core.pager "less -R"

# Editor по умолчанию (опционально)
git config --global core.editor "code --wait"
# или
# git config --global core.editor "nano"

# Проверка
git config --global --list
```

## Шаг 4. Настройка SSH-ключей (рекомендуется)

### 4.1. Проверка существующих ключей

```bash
ls ~/.ssh/id_*.pub
```

Если файлы есть — переходите к шагу 4.3.

### 4.2. Генерация нового ключа

```bash
ssh-keygen -t ed25519 -C "ivanov@example.com"
```

Нажмите Enter для сохранения в стандартное место. При желании задайте пароль (passphrase).

### 4.3. Добавление ключа в буфер обмена

```bash
# macOS Sonoma 14.2+ и новее
pbcopy < ~/.ssh/id_ed25519.pub

# Старые версии macOS
cat ~/.ssh/id_ed25519.pub | pbcopy
```

### 4.4. Добавление ключа в GitHub/GitVerse

1. Откройте GitHub → Settings → SSH and GPG keys
2. Нажмите **New SSH key**
3. Вставьте ключ из буфера обмена
4. Назовите (например: "MacBook Pro")
5. Нажмите **Add SSH key**

### 4.5. Проверка подключения

```bash
ssh -T git@github.com
```

Должно вывести: `Hi ivanov! You've successfully authenticated...`

### 4.6. SSH Agent (автоматическое добавление ключа)

Добавьте в `~/.zshrc` (или `~/.bash_profile`):

```bash
# SSH Agent
eval "$(ssh-agent -s)"
echo 'ssh-add --apple-use-keychain ~/.ssh/id_ed25519' >> ~/.zshrc
```

Примените настройки:

```bash
source ~/.zshrc
```

## Шаг 5. VS Code (опционально)

Если используете VS Code:

1. Установите [VS Code](https://code.visualstudio.com/)
2. VS Code автоматически подхватит Git
3. Проверьте: `Cmd+Shift+P` → «Git: Status»

## Частые проблемы

### «git: command not found»

- Перезапустите Terminal
- Или: `export PATH="/opt/homebrew/bin:$PATH"` (Apple Silicon)
- Или: `export PATH="/usr/local/bin:$PATH"` (Intel)

### Ошибка SSL при clone

```bash
git config --global http.sslBackend openssl
```

### Проблемы с кодировкой

```bash
git config --global core.quotepath false
```

### Ключ не добавился в keychain

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

### Homebrew не установлен

См. шаг 1.1. После установки Homebrew выполните:

```bash
brew doctor
```

Проверьте, что система в порядке.
