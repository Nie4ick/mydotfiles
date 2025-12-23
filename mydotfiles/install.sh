#!/bin/bash

# Скрипт установки dotfiles с использованием GNU Stow
# Автор: Nie4ick
# Репозиторий: https://github.com/Nie4ick/mydotfiles

set -e  # Прекратить выполнение при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # Без цвета

# Функции для вывода
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка, что скрипт запущен не от root
if [ "$EUID" -eq 0 ]; then 
    print_error "Не запускайте этот скрипт от root!"
    exit 1
fi

# Проверка, что мы на Arch Linux
if [ ! -f /etc/arch-release ]; then
    print_error "Этот скрипт предназначен для Arch Linux"
    exit 1
fi

# Обновление системы
print_info "Обновление системы..."
sudo pacman -Syu --noconfirm

# Установка базовых зависимостей
print_info "Установка базовых зависимостей..."
sudo pacman -S --needed --noconfirm base-devel git stow

# Установка yay (AUR helper)
install_yay() {
    if command -v yay &> /dev/null; then
        print_success "yay уже установлен"
        return 0
    fi
    
    print_info "Установка yay (AUR helper)..."
    
    # Сохраняем текущую директорию
    local CURRENT_DIR=$(pwd)
    
    # Клонирование yay
    cd /tmp
    if [ -d "yay" ]; then
        rm -rf yay
    fi
    
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    
    # Возвращаемся в исходную директорию
    cd "$CURRENT_DIR"
    rm -rf /tmp/yay
    
    print_success "yay установлен успешно"
}

# Клонирование dotfiles репозитория
clone_dotfiles() {
    local DOTFILES_DIR="$HOME/mydotfiles"
    
    # Переходим в домашнюю директорию для безопасности
    cd "$HOME"
    
    if [ -d "$DOTFILES_DIR" ]; then
        print_warning "Директория $DOTFILES_DIR уже существует"
        read -p "Удалить и склонировать заново? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Удаление старой директории..."
            rm -rf "$DOTFILES_DIR"
        else
            print_info "Используем существующую директорию"
            cd "$DOTFILES_DIR"
            print_info "Обновление репозитория..."
            git pull || print_warning "Не удалось обновить репозиторий"
            return 0
        fi
    fi
    
    print_info "Клонирование dotfiles репозитория..."
    git clone https://github.com/Nie4ick/mydotfiles.git "$DOTFILES_DIR"
    
    if [ $? -eq 0 ]; then
        cd "$DOTFILES_DIR"
        print_success "Репозиторий склонирован в $DOTFILES_DIR"
    else
        print_error "Не удалось склонировать репозиторий"
        exit 1
    fi
}

# Создание backup существующих конфигов
backup_configs() {
    local BACKUP_DIR="$HOME/.config_backup_$(date +%Y%m%d_%H%M%S)"
    
    if [ -d "$HOME/.config" ]; then
        print_info "Создание резервной копии существующих конфигов..."
        mkdir -p "$BACKUP_DIR"
        
        # Копируем только те директории, которые будут перезаписаны
        for dir in "$HOME/mydotfiles/.config"/*; do
            if [ -d "$dir" ]; then
                local dirname=$(basename "$dir")
                if [ -d "$HOME/.config/$dirname" ]; then
                    cp -r "$HOME/.config/$dirname" "$BACKUP_DIR/"
                    print_info "Создан backup: $dirname -> $BACKUP_DIR"
                fi
            fi
        done
        
        print_success "Backup создан в $BACKUP_DIR"
    fi
}

# Установка конфигов с помощью stow
install_configs() {
    print_info "Установка конфигурационных файлов с помощью stow..."
    
    cd "$HOME/mydotfiles"
    
    # Удаляем старые символические ссылки если они есть
    stow -D . 2>/dev/null || true
    
    # Пробуем создать символические ссылки
    if stow . 2>/dev/null ; then
        print_success "Конфиги успешно установлены с помощью stow"
        return 0
    fi
    
    # Если есть конфликты, предлагаем варианты
    print_warning "Обнаружены конфликты с существующими файлами!"
    echo ""
    echo "Выберите действие:"
    echo "1) Удалить ВСЕ конфликтующие директории (.config, .icons) и установить чистые конфиги"
    echo "2) Удалить только конфликтующие файлы (умное удаление)"
    echo "3) Использовать --adopt (заменит файлы в репозитории на ваши текущие)"
    echo "4) Пропустить установку конфигов"
    echo ""
    read -p "Ваш выбор (1/2/3/4): " -n 1 -r choice
    echo ""
    
    case $choice in
        1)
            print_warning "ВНИМАНИЕ: Будут удалены директории ~/.config и ~/.icons"
            read -p "Вы уверены? Введите 'yes' для подтверждения: " confirm
            if [ "$confirm" = "yes" ]; then
                print_info "Удаление ~/.config и ~/.icons..."
                rm -rf ~/.config ~/.icons
                print_info "Создание базовых директорий..."
                mkdir -p ~/.config ~/.icons
                
                if stow . ; then
                    print_success "Конфиги успешно установлены!"
                else
                    print_error "Ошибка при установке"
                    exit 1
                fi
            else
                print_warning "Отменено"
                exit 1
            fi
            ;;
        2)
            print_info "Умное удаление конфликтов..."
            handle_conflicts_delete
            ;;
        3)
            print_info "Использование --adopt для разрешения конфликтов..."
            # Сначала удаляем проблемные директории, которые --adopt не может обработать
            print_info "Удаление проблемных директорий перед --adopt..."
            rm -rf ~/.config/rofi/rofi/bin 2>/dev/null || true
            rm -rf ~/.icons/catppuccin-frappe-dark-cursors 2>/dev/null || true
            
            if stow --adopt . ; then
                print_success "Конфиги установлены с использованием --adopt"
                print_warning "Некоторые файлы в репозитории были заменены вашими текущими конфигами"
            else
                print_error "Ошибка при установке с --adopt"
                print_info "Попробуйте вариант 1 или 2"
                exit 1
            fi
            ;;
        4)
            print_warning "Установка конфигов пропущена"
            return 0
            ;;
        *)
            print_error "Неверный выбор"
            exit 1
            ;;
    esac
}

# Обработка конфликтов путём удаления существующих файлов
handle_conflicts_delete() {
    print_info "Анализ конфликтов..."
    
    # Получаем список конфликтующих путей из вывода stow
    local conflicts=$(stow -n -v . 2>&1 | grep -E "existing target|cannot stow" | sed -E 's/.*: (\..*)/\1/' | sort -u)
    
    if [ -z "$conflicts" ]; then
        print_info "Нет конфликтов для обработки"
        return 0
    fi
    
    echo ""
    print_warning "Найдены следующие конфликты:"
    echo "$conflicts" | head -20
    if [ $(echo "$conflicts" | wc -l) -gt 20 ]; then
        echo "... и ещё $(( $(echo "$conflicts" | wc -l) - 20 )) файлов"
    fi
    echo ""
    
    read -p "Удалить все конфликтующие файлы и директории? (y/N): " -n 1 -r confirm
    echo ""
    
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        print_warning "Отменено пользователем"
        exit 1
    fi
    
    # Удаляем конфликтующие директории целиком (более агрессивный подход)
    print_info "Удаление конфликтующих директорий..."
    
    # Извлекаем уникальные базовые директории
    local dirs_to_remove=$(echo "$conflicts" | cut -d'/' -f1-3 | sort -u)
    
    for dir in $dirs_to_remove; do
        local full_path="$HOME/$dir"
        if [ -e "$full_path" ] || [ -L "$full_path" ]; then
            print_info "Удаление: $full_path"
            rm -rf "$full_path"
        fi
    done
    
    # Теперь пробуем установить снова
    print_info "Повторная попытка установки..."
    if stow -v . 2>&1 | tee /tmp/stow_output.log; then
        print_success "Конфиги успешно установлены после разрешения конфликтов"
    else
        print_error "Всё ещё есть ошибки при установке конфигов"
        print_info "Лог сохранён в /tmp/stow_output.log"
        echo ""
        print_info "Попробуйте вручную:"
        echo "  cd ~/mydotfiles"
        echo "  stow -v ."
        exit 1
    fi
}

# Установка необходимых пакетов
install_packages() {
    print_info "Установка пакетов из официальных репозиториев..."
    
    # Список пакетов можно расширить в зависимости от конфигов
    local PACKAGES=(
        # Терминал и оболочка
        alacritty
        zsh
        
        # Window Manager / Desktop Environment
        hyprland
        
        # Файловый менеджер
        thunar
        thunar-volman
        thunar-archive-plugin
        
        # Утилиты
        neovim
        tmux
        fzf
        ripgrep
        fd
        bat
        
        # Системные утилиты
        htop
        btop
        
        # Шрифты
        ttf-fira-code
        ttf-font-awesome
        noto-fonts-emoji
    )
    
    for package in "${PACKAGES[@]}"; do
        if ! pacman -Qi "$package" &> /dev/null; then
            print_info "Установка $package..."
            sudo pacman -S --needed --noconfirm "$package" || print_warning "Не удалось установить $package"
        fi
    done
    
    print_success "Пакеты из официальных репозиториев установлены"
}

# Установка AUR пакетов
install_aur_packages() {
    print_info "Установка пакетов из AUR..."
    
    local AUR_PACKAGES=(
        # Утилиты для Hyprland
        hyprshot
        
        # Добавьте другие AUR пакеты здесь
        # catppuccin-cursors-frappe  # пример
    )
    
    for package in "${AUR_PACKAGES[@]}"; do
        # Пропускаем закомментированные строки
        if [[ "$package" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        if ! pacman -Qi "$package" &> /dev/null; then
            print_info "Установка $package из AUR..."
            yay -S --needed --noconfirm "$package" || print_warning "Не удалось установить $package"
        else
            print_info "$package уже установлен"
        fi
    done
    
    print_success "AUR пакеты установлены"
}

# Пост-установочные действия
post_install() {
    print_info "Выполнение пост-установочных действий..."
    
    # Установка zsh как оболочки по умолчанию
    if command -v zsh &> /dev/null; then
        if [ "$SHELL" != "$(which zsh)" ]; then
            print_info "Установка zsh как оболочки по умолчанию..."
            chsh -s $(which zsh)
            print_success "zsh установлен как оболочка по умолчанию"
        fi
    fi
    
    # Установка курсоров
    if [ -d "$HOME/mydotfiles/.icons" ]; then
        print_info "Копирование иконок и курсоров..."
        mkdir -p "$HOME/.icons"
        cp -r "$HOME/mydotfiles/.icons"/* "$HOME/.icons/" 2>/dev/null || true
    fi
    
    # Установка обоев
    if [ -d "$HOME/mydotfiles/Wallpapers" ]; then
        print_info "Копирование обоев..."
        mkdir -p "$HOME/Pictures/Wallpapers"
        cp -r "$HOME/mydotfiles/Wallpapers"/* "$HOME/Pictures/Wallpapers/" 2>/dev/null || true
    fi
}

# Главная функция
main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║     Установщик Dotfiles от Nie4ick                   ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    
    print_info "Начало установки..."
    
    # Основные шаги установки
    install_yay
    clone_dotfiles
    backup_configs
    install_packages
    install_aur_packages
    install_configs
    post_install
    
    echo ""
    print_success "┌───────────────────────────────────────────────────┐"
    print_success "│ Установка завершена успешно!                     │"
    print_success "└───────────────────────────────────────────────────┘"
    echo ""
    print_info "Рекомендуется перезагрузить систему или перелогиниться"
    print_info "Для применения всех изменений выполните: exec zsh"
    echo ""
}

# Запуск скрипта
main "$@"
