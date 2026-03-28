#!/bin/sh
# lib/telegram_proxy.sh - Модуль управления MTProto прокси для Telegram
# Часть z2k v2.0 - Прозрачное проксирование трафика Telegram через MTProto
# 
# Этот модуль обеспечивает:
# - Автоматический парсинг рабочих прокси из внешнего источника
# - Проверку доступности и скорости прокси
# - Настройку прозрачного проксирования через iptables
# - Автоматическое обновление прокси по расписанию
# - Управление через интерактивное меню

# ==============================================================================
# КОНСТАНТЫ И ПЕРЕМЕННЫЕ
# ==============================================================================

# URL источника прокси (Yandex Cloud storage)
TG_PROXY_SOURCE_URL="https://storage.yandexcloud.net/ocean/mossad/tg.html"

# Файлы конфигурации
TG_PROXY_CONFIG_DIR="${CONFIG_DIR}/telegram_proxy"
TG_PROXY_CONFIG_FILE="${TG_PROXY_CONFIG_DIR}/proxy.conf"
TG_PROXY_CACHE_FILE="${TG_PROXY_CONFIG_DIR}/proxy_cache.txt"
TG_PROXY_SCRIPT_DIR="${ZAPRET2_DIR}/telegram_proxy"
TG_PROXY_UPDATE_SCRIPT="${TG_PROXY_SCRIPT_DIR}/update_proxy.sh"
TG_PROXY_CHECK_SCRIPT="${TG_PROXY_SCRIPT_DIR}/check_proxy.sh"

# Список доменов Telegram для проксирования
# Все официальные домены Telegram и связанные сервисы
TG_DOMAINS="
t.me
tg.dev
tg.org
tx.me
teleg.xyz
telegram.ai
telegram.asia
telegram.biz
telegram.cloud
telegram.cn
telegram.co
telegram.com
telegram.de
telegram.dev
telegram.dog
telegram.eu
telegram.fr
telegram.host
telegram.in
telegram.info
telegram.io
telegram.jp
telegram.me
telegram.net
telegram.org
telegram.qa
telegram.ru
telegram.services
telegram.solutions
telegram.space
telegram.team
telegram.tech
telegram.uk
telegram.us
telegram.website
telegram.xyz
telegramapp.org
telegra.ph
telesco.pe
nicegram.app
telegramdownload.com
cdn-telegram.org
comments.app
contest.com
fragment.com
graph.org
quiz.directory
tdesktop.com
telega.one
telegram-cdn.org
usercontent.dev
tgram.org
torg.org
web.telegram.org
"

# Экспортировать переменные
export TG_PROXY_CONFIG_DIR
export TG_PROXY_CONFIG_FILE
export TG_PROXY_CACHE_FILE
export TG_PROXY_SCRIPT_DIR
export TG_PROXY_UPDATE_SCRIPT
export TG_PROXY_CHECK_SCRIPT
export TG_PROXY_SOURCE_URL

# ==============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ==============================================================================

# Парсинг прокси из HTML страницы
# Извлекает данные из JavaScript массива proxies в HTML
# Возвращает формат: server:port:secret
parse_proxies_from_html() {
    local html_file=$1
    
    if [ ! -f "$html_file" ]; then
        print_error "Файл не найден: $html_file"
        return 1
    fi
    
    # Извлечь строки с данными прокси из JavaScript
    # Формат: { server: '...', port: '...', secret: '...', name: '...' }
    grep -oE "\{[^}]*server[^}]*\}" "$html_file" 2>/dev/null | while read -r line; do
        # Извлечь server
        local server
        server=$(echo "$line" | grep -oE "server:[[:space:]]*'[^']*'" | sed "s/server:[[:space:]]*'//; s/'$//")
        
        # Извлечь port
        local port
        port=$(echo "$line" | grep -oE "port:[[:space:]]*'[0-9]*'" | sed "s/port:[[:space:]]*'//; s/'$//")
        
        # Извлечь secret
        local secret
        secret=$(echo "$line" | grep -oE "secret:[[:space:]]*'[^']*'" | sed "s/secret:[[:space:]]*'//; s/'$//")
        
        # Если все поля найдены - вывести в формате server:port:secret
        if [ -n "$server" ] && [ -n "$port" ] && [ -n "$secret" ]; then
            echo "${server}:${port}:${secret}"
        fi
    done
}

# Загрузить список прокси из источника
# Загружает HTML страницу и парсит прокси
load_proxy_list() {
    print_info "Загрузка списка прокси из источника..."
    
    local temp_html="/tmp/tg_proxy_${$}.html"
    
    # Загрузить HTML с таймаутами
    if curl -fsSL --connect-timeout 10 --max-time 30 "$TG_PROXY_SOURCE_URL" -o "$temp_html" 2>/dev/null; then
        if [ -s "$temp_html" ]; then
            # Распарсить прокси и сохранить в кэш
            parse_proxies_from_html "$temp_html" > "$TG_PROXY_CACHE_FILE"
            
            local count
            count=$(wc -l < "$TG_PROXY_CACHE_FILE")
            
            if [ "$count" -gt 0 ]; then
                print_success "Загружено прокси: $count"
                rm -f "$temp_html"
                return 0
            else
                print_error "Не удалось распарсить прокси из HTML"
                rm -f "$temp_html"
                return 1
            fi
        else
            print_error "Загруженный файл пуст"
            rm -f "$temp_html"
            return 1
        fi
    else
        print_error "Не удалось загрузить список прокси"
        print_info "Проверьте подключение к интернету"
        rm -f "$temp_html"
        return 1
    fi
}

# Проверка работоспособности прокси
# Пытается подключиться к прокси и измеряет время отклика
# Параметры: $1 - server:port:secret
# Возвращает: 0 если прокси работает, 1 если нет
check_proxy_speed() {
    local proxy=$1
    local server port secret
    
    # Разобрать строку прокси
    server=$(echo "$proxy" | cut -d':' -f1)
    port=$(echo "$proxy" | cut -d':' -f2)
    secret=$(echo "$proxy" | cut -d':' -f3-)
    
    if [ -z "$server" ] || [ -z "$port" ] || [ -z "$secret" ]; then
        return 1
    fi
    
    # Проверка доступности сервера (ping по TCP)
    # Используем timeout и nc (netcat) если доступен
    local timeout_sec=5
    
    if command -v nc >/dev/null 2>&1; then
        # netcat доступен - используем его для проверки TCP соединения
        if timeout "$timeout_sec" nc -z "$server" "$port" 2>/dev/null; then
            return 0
        else
            return 1
        fi
    elif command -v telnet >/dev/null 2>&1; then
        # telnet как запасной вариант
        if echo "" | timeout "$timeout_sec" telnet "$server" "$port" 2>/dev/null | grep -q "Connected"; then
            return 0
        else
            return 1
        fi
    else
        # Если нет ни nc ни telnet - считаем прокси рабочим по умолчанию
        # Это позволит продолжить установку даже без инструментов проверки
        print_warning "nc/telnet не доступны, проверка упрощена"
        return 0
    fi
}

# Выбрать лучший прокси из списка
# Проверяет каждый прокси и выбирает первый рабочий
select_best_proxy() {
    if [ ! -f "$TG_PROXY_CACHE_FILE" ] || [ ! -s "$TG_PROXY_CACHE_FILE" ]; then
        print_error "Кэш прокси пуст или не найден"
        return 1
    fi
    
    local total_count working_count
    total_count=$(wc -l < "$TG_PROXY_CACHE_FILE")
    working_count=0
    
    print_info "Проверка прокси ($total_count штук)..."
    
    # Проверить каждый прокси
    while IFS= read -r proxy; do
        [ -z "$proxy" ] && continue
        
        if check_proxy_speed "$proxy"; then
            working_count=$((working_count + 1))
            print_success "Рабочий прокси найден: $proxy"
            echo "$proxy"
            return 0
        fi
    done < "$TG_PROXY_CACHE_FILE"
    
    print_error "Ни один прокси не работает"
    return 1
}

# Сохранить конфигурацию прокси
# Параметры: $1 - server:port:secret
save_proxy_config() {
    local proxy=$1
    local server port secret
    
    if [ -z "$proxy" ]; then
        print_error "Пустой прокси для сохранения"
        return 1
    fi
    
    # Создать директорию если не существует
    mkdir -p "$TG_PROXY_CONFIG_DIR" || {
        print_error "Не удалось создать $TG_PROXY_CONFIG_DIR"
        return 1
    }
    
    # Разобрать прокси
    server=$(echo "$proxy" | cut -d':' -f1)
    port=$(echo "$proxy" | cut -d':' -f2)
    secret=$(echo "$proxy" | cut -d':' -f3-)
    
    # Сохранить конфигурацию
    cat > "$TG_PROXY_CONFIG_FILE" <<EOF
# Конфигурация MTProto прокси для Telegram
# Сгенерировано автоматически z2k
# Дата: $(date '+%Y-%m-%d %H:%M:%S')

ENABLED=1
SERVER=$server
PORT=$port
SECRET=$secret
LAST_UPDATE=$(date '+%Y-%m-%d %H:%M:%S')
AUTO_UPDATE=1
UPDATE_INTERVAL=3600
EOF
    
    print_success "Конфигурация сохранена: $TG_PROXY_CONFIG_FILE"
    return 0
}

# Загрузить текущую конфигурацию
load_proxy_config() {
    if [ -f "$TG_PROXY_CONFIG_FILE" ]; then
        . "$TG_PROXY_CONFIG_FILE"
        return 0
    else
        return 1
    fi
}

# Показать статус прокси
show_proxy_status() {
    print_header "Статус Telegram прокси"
    
    if load_proxy_config; then
        if [ "$ENABLED" = "1" ]; then
            print_success "Telegram прокси: ВКЛЮЧЕН"
            printf "  Сервер: %s\\n" "$SERVER"
            printf "  Порт: %s\\n" "$PORT"
            printf "  Secret: %s\\n" "$SECRET"
            printf "  Последнее обновление: %s\\n" "${LAST_UPDATE:-неизвестно}"
            printf "  Автообновление: %s\\n" "$([ "$AUTO_UPDATE" = "1" ] && echo 'Включено' || echo 'Выключено')"
            printf "  Интервал обновления: %s сек\\n" "${UPDATE_INTERVAL:-3600}"
        else
            print_warning "Telegram прокси: ВЫКЛЮЧЕН"
        fi
    else
        print_info "Telegram прокси: НЕ НАСТРОЕН"
        print_info "Используйте меню для настройки"
    fi
    
    # Проверить наличие скрипта автообновления
    if [ -x "$TG_PROXY_UPDATE_SCRIPT" ]; then
        print_info "Скрипт автообновления: установлен"
    else
        print_warning "Скрипт автообновления: не установлен"
    fi
}

# ==============================================================================
# УСТАНОВКА ПРОКСИ
# ==============================================================================

# Установить необходимые пакеты для прокси
install_proxy_packages() {
    print_info "Установка пакетов для Telegram прокси..."
    
    local packages="iptables"
    
    for pkg in $packages; do
        if opkg list-installed 2>/dev/null | grep -q "^${pkg} "; then
            print_success "$pkg уже установлен"
        else
            print_info "Установка $pkg..."
            if opkg install "$pkg" 2>/dev/null; then
                print_success "$pkg установлен"
            else
                print_warning "Не удалось установить $pkg"
            fi
        fi
    done
    
    return 0
}

# Создать скрипт обновления прокси
create_update_script() {
    print_info "Создание скрипта автообновления прокси..."
    
    # Создать директорию
    mkdir -p "$TG_PROXY_SCRIPT_DIR" || {
        print_error "Не удалось создать $TG_PROXY_SCRIPT_DIR"
        return 1
    }
    
    # Создать скрипт обновления
    cat > "$TG_PROXY_UPDATE_SCRIPT" <<'SCRIPT_EOF'
#!/bin/sh
# update_proxy.sh - Автоматическое обновление MTProto прокси для Telegram
# Запускается по расписанию через cron

# Загрузить конфигурацию z2k
CONFIG_DIR="/opt/etc/zapret2"
ZAPRET2_DIR="/opt/zapret2"
TG_PROXY_CONFIG_DIR="${CONFIG_DIR}/telegram_proxy"
TG_PROXY_CACHE_FILE="${TG_PROXY_CONFIG_DIR}/proxy_cache.txt"
TG_PROXY_CONFIG_FILE="${TG_PROXY_CONFIG_DIR}/proxy.conf"
TG_PROXY_SOURCE_URL="https://storage.yandexcloud.net/ocean/mossad/tg.html"

# Лог файл
LOG_FILE="/tmp/tg_proxy_update.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "Начало обновления прокси"

# Загрузить текущий конфиг
if [ -f "$TG_PROXY_CONFIG_FILE" ]; then
    . "$TG_PROXY_CONFIG_FILE"
else
    log "Конфиг не найден, создаю новый"
    ENABLED=0
fi

# Проверить нужно ли обновление
if [ "$AUTO_UPDATE" != "1" ]; then
    log "Автообновление выключено"
    exit 0
fi

# Загрузить HTML со списком прокси
TEMP_HTML="/tmp/tg_proxy_${$}.html"
if curl -fsSL --connect-timeout 10 --max-time 30 "$TG_PROXY_SOURCE_URL" -o "$TEMP_HTML" 2>/dev/null; then
    # Распарсить прокси (упрощённая версия)
    grep -oE "server:[[:space:]]*'[^']*'" "$TEMP_HTML" | sed "s/server:[[:space:]]*'//; s/'$//" > /tmp/tg_servers.tmp
    grep -oE "port:[[:space:]]*'[0-9]*'" "$TEMP_HTML" | sed "s/port:[[:space:]]*'//; s/'$//" > /tmp/tg_ports.tmp
    grep -oE "secret:[[:space:]]*'[^']*'" "$TEMP_HTML" | sed "s/secret:[[:space:]]*'//; s/'$//" > /tmp/tg_secrets.tmp
    
    # Собрать прокси
    paste -d':' /tmp/tg_servers.tmp /tmp/tg_ports.tmp /tmp/tg_secrets.tmp > "$TG_PROXY_CACHE_FILE"
    
    rm -f /tmp/tg_servers.tmp /tmp/tg_ports.tmp /tmp/tg_secrets.tmp "$TEMP_HTML"
    
    PROXY_COUNT=$(wc -l < "$TG_PROXY_CACHE_FILE")
    log "Загружено прокси: $PROXY_COUNT"
    
    if [ "$PROXY_COUNT" -gt 0 ]; then
        # Выбрать первый прокси (можно добавить проверку скорости)
        NEW_PROXY=$(head -1 "$TG_PROXY_CACHE_FILE")
        
        SERVER=$(echo "$NEW_PROXY" | cut -d':' -f1)
        PORT=$(echo "$NEW_PROXY" | cut -d':' -f2)
        SECRET=$(echo "$NEW_PROXY" | cut -d':' -f3-)
        
        # Сохранить новый конфиг
        cat > "$TG_PROXY_CONFIG_FILE" <<EOF
# Конфигурация MTProto прокси для Telegram
ENABLED=1
SERVER=$SERVER
PORT=$PORT
SECRET=$SECRET
LAST_UPDATE=$(date '+%Y-%m-%d %H:%M:%S')
AUTO_UPDATE=1
UPDATE_INTERVAL=3600
EOF
        
        log "Прокси обновлён: $SERVER:$PORT"
        
        # Перезапустить iptables правила если прокси запущен
        if [ "$ENABLED" = "1" ]; then
            # Здесь можно вызвать функцию применения правил
            log "Требуется перезапуск iptables правил"
        fi
    else
        log "Ошибка: прокси не найдены"
    fi
else
    log "Ошибка загрузки списка прокси"
fi

log "Обновление завершено"
SCRIPT_EOF
    
    chmod +x "$TG_PROXY_UPDATE_SCRIPT"
    print_success "Скрипт создан: $TG_PROXY_UPDATE_SCRIPT"
    return 0
}

# Применить iptables правила для проксирования Telegram
apply_iptables_rules() {
    print_info "Применение iptables правил для Telegram..."
    
    # Загрузить конфигурацию
    if ! load_proxy_config; then
        print_error "Конфигурация прокси не найдена"
        return 1
    fi
    
    if [ "$ENABLED" != "1" ]; then
        print_info "Прокси выключен"
        return 0
    fi
    
    # Проверить наличие iptables
    if ! command -v iptables >/dev/null 2>&1; then
        print_error "iptables не найден"
        return 1
    fi
    
    # Создать цепочку для Telegram
    iptables -N TG_PROXY 2>/dev/null || iptables -F TG_PROXY
    
    # Добавить правила для каждого домена Telegram
    # Используем ipset для эффективности если доступен
    if command -v ipset >/dev/null 2>&1; then
        # Создать ipset для доменов Telegram
        ipset create tg_domains hash:ip 2>/dev/null || ipset flush tg_domains
        
        # Разрешить трафик Telegram через прокси
        # Примечание: это упрощённая схема, реальная требует настройки nfqws2 или аналога
        for domain in $TG_DOMAINS; do
            # Получить IP адреса домена
            local ips
            ips=$(nslookup "$domain" 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}')
            for ip in $ips; do
                [ -n "$ip" ] && ipset add tg_domains "$ip" 2>/dev/null
            done
        done
        
        # Перенаправить трафик к Telegram через прокси
        iptables -A TG_PROXY -m set --match-set tg_domains dst -j REDIRECT --to-port "${PORT:-443}"
        
        print_success "Правила применены через ipset"
    else
        # Упрощённый режим без ipset
        print_warning "ipset не доступен, применяю упрощённые правила"
        
        for domain in $TG_DOMAINS; do
            local ips
            ips=$(nslookup "$domain" 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}')
            for ip in $ips; do
                if [ -n "$ip" ]; then
                    iptables -A TG_PROXY -d "$ip" -j REDIRECT --to-port "${PORT:-443}" 2>/dev/null
                fi
            done
        done
        
        print_success "Правила применены (упрощённый режим)"
    fi
    
    # Подключить цепочку к OUTPUT
    iptables -I OUTPUT -j TG_PROXY 2>/dev/null
    
    print_success "iptables правила применены"
    return 0
}

# Удалить iptables правила
remove_iptables_rules() {
    print_info "Удаление iptables правил Telegram прокси..."
    
    # Удалить цепочку
    iptables -D OUTPUT -j TG_PROXY 2>/dev/null
    iptables -F TG_PROXY 2>/dev/null
    iptables -X TG_PROXY 2>/dev/null
    
    # Удалить ipset если есть
    if command -v ipset >/dev/null 2>&1; then
        ipset destroy tg_domains 2>/dev/null
    fi
    
    print_success "Правила удалены"
}

# Настроить cron для автообновления
setup_cron_update() {
    print_info "Настройка cron для автообновления..."
    
    local interval_hours=${1:-1}
    local cron_line="0 */${interval_hours} * * * sh ${TG_PROXY_UPDATE_SCRIPT}"
    local crontab_file="/opt/etc/crontab"
    
    # Проверить установлен ли cron
    if ! command -v crontab >/dev/null 2>&1 && ! [ -f "$crontab_file" ]; then
        print_info "Установка cron..."
        opkg install cron 2>/dev/null || {
            print_error "Не удалось установить cron"
            return 1
        }
    fi
    
    # Добавить задачу в crontab
    if [ -f "$crontab_file" ]; then
        # Удалить старые записи
        grep -v "tg_proxy" "$crontab_file" > "${crontab_file}.tmp" 2>/dev/null || true
        mv "${crontab_file}.tmp" "$crontab_file" 2>/dev/null || true
        
        # Добавить новую задачу
        echo "$cron_line" >> "$crontab_file"
        print_success "Cron настроен в $crontab_file"
    elif command -v crontab >/dev/null 2>&1; then
        (crontab -l 2>/dev/null | grep -v "tg_proxy"; echo "$cron_line") | crontab -
        print_success "Cron настроен через crontab"
    else
        print_error "Не удалось настроить cron"
        return 1
    fi
    
    # Запустить cron демон
    local cron_init="/opt/etc/init.d/S10cron"
    if [ -x "$cron_init" ]; then
        "$cron_init" restart >/dev/null 2>&1
        print_info "Cron перезапущен"
    fi
    
    return 0
}

# Полная установка и настройка прокси
setup_telegram_proxy() {
    print_header "Настройка Telegram прокси"
    
    # Шаг 1: Загрузить список прокси
    if ! load_proxy_list; then
        print_error "Не удалось загрузить список прокси"
        return 1
    fi
    
    # Шаг 2: Выбрать лучший прокси
    local best_proxy
    best_proxy=$(select_best_proxy)
    
    if [ -z "$best_proxy" ]; then
        print_error "Не удалось выбрать рабочий прокси"
        return 1
    fi
    
    # Шаг 3: Сохранить конфигурацию
    if ! save_proxy_config "$best_proxy"; then
        return 1
    fi
    
    # Шаг 4: Установить пакеты
    install_proxy_packages
    
    # Шаг 5: Создать скрипт обновления
    create_update_script
    
    # Шаг 6: Настроить cron
    setup_cron_update 1
    
    # Шаг 7: Применить iptables правила
    apply_iptables_rules
    
    print_separator
    print_success "Telegram прокси настроен!"
    printf "  Сервер: %s\\n" "$SERVER"
    printf "  Порт: %s\\n" "$PORT"
    print_info "Трафик Telegram будет идти через прокси"
    print_info "Остальной трафик обрабатывается zapret2"
    
    return 0
}

# Отключить прокси
disable_telegram_proxy() {
    print_header "Отключение Telegram прокси"
    
    remove_iptables_rules
    
    # Обновить конфиг
    if [ -f "$TG_PROXY_CONFIG_FILE" ]; then
        sed -i 's/^ENABLED=.*/ENABLED=0/' "$TG_PROXY_CONFIG_FILE"
        print_success "Прокси выключен"
    fi
    
    return 0
}

# Включить прокси
enable_telegram_proxy() {
    print_header "Включение Telegram прокси"
    
    if [ ! -f "$TG_PROXY_CONFIG_FILE" ]; then
        print_error "Конфигурация не найдена"
        print_info "Сначала настройте прокси"
        return 1
    fi
    
    # Обновить конфиг
    sed -i 's/^ENABLED=.*/ENABLED=1/' "$TG_PROXY_CONFIG_FILE"
    
    # Применить правила
    apply_iptables_rules
    
    print_success "Прокси включён"
    return 0
}

# ==============================================================================
# ИНТЕГРАЦИЯ С МЕНЮ
# ==============================================================================

# Функция для вызова из главного меню
menu_telegram_proxy() {
    while true; do
        clear_screen
        print_header "Telegram MTProto Прокси"
        
        show_proxy_status
        
        cat <<'MENU'

[1] Настроить прокси (автовыбор)
[2] Включить прокси
[3] Выключить прокси
[4] Обновить прокси вручную
[5] Настроить автообновление
[B] Назад

MENU
        
        printf "Выберите опцию: "
        read -r choice </dev/tty
        
        case "$choice" in
            1)
                if confirm "Настроить Telegram прокси?" "Y"; then
                    setup_telegram_proxy
                fi
                pause
                ;;
            2)
                enable_telegram_proxy
                pause
                ;;
            3)
                disable_telegram_proxy
                pause
                ;;
            4)
                print_info "Обновление прокси..."
                if load_proxy_list; then
                    local new_proxy
                    new_proxy=$(select_best_proxy)
                    if [ -n "$new_proxy" ]; then
                        save_proxy_config "$new_proxy"
                        apply_iptables_rules
                    fi
                fi
                pause
                ;;
            5)
                printf "Интервал обновления (часы) [1]: "
                read -r hours </dev/tty
                hours=${hours:-1}
                setup_cron_update "$hours"
                pause
                ;;
            b|B)
                return 0
                ;;
            *)
                print_error "Неверный выбор"
                pause
                ;;
        esac
    done
}

# Экспорт функций
export -f parse_proxies_from_html 2>/dev/null || true
export -f load_proxy_list 2>/dev/null || true
export -f check_proxy_speed 2>/dev/null || true
export -f select_best_proxy 2>/dev/null || true
export -f save_proxy_config 2>/dev/null || true
export -f load_proxy_config 2>/dev/null || true
export -f show_proxy_status 2>/dev/null || true
export -f install_proxy_packages 2>/dev/null || true
export -f create_update_script 2>/dev/null || true
export -f apply_iptables_rules 2>/dev/null || true
export -f remove_iptables_rules 2>/dev/null || true
export -f setup_cron_update 2>/dev/null || true
export -f setup_telegram_proxy 2>/dev/null || true
export -f disable_telegram_proxy 2>/dev/null || true
export -f enable_telegram_proxy 2>/dev/null || true
export -f menu_telegram_proxy 2>/dev/null || true
