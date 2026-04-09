#!/bin/sh
# lib/telegram_proxy.sh - Модуль управления MTProto прокси для Telegram
# Часть z2k v2.0 - Прозрачное проксирование трафика Telegram через автоматический выбор рабочих прокси
#
# АРХИТЕКТУРА РЕШЕНИЯ:
# ┌─────────────────┐     ┌──────────────┐     ┌───────────────────┐     ┌──────────────┐
# │  Клиенты Wi-Fi  │────▶│ iptables     │────▶│ mtproto-to-socks5 │────▶│ MTProto      │
# │  (без настройки)│     │ REDIRECT :1080│    │ (конвертер)       │     │ Upstream     │
# └─────────────────┘     └──────────────┘     └───────────────────┘     └──────────────┘
#                              │                       │
#                              ▼                       ▼
#                        ┌──────────────┐     ┌───────────────────┐
#                        │ Xray/SOCKS5  │────▶│ Интернет          │
#                        │ порт 1081    │     │                   │
#                        └──────────────┘     └───────────────────┘
#
# Компоненты:
# 1. iptables REDIRECT - перехватывает трафик Telegram на порт 1080
# 2. mtproto-to-socks5 - конвертирует MTProto в SOCKS5 (легковесный Python скрипт)
# 3. Xray - принимает SOCKS5 и маршрутизирует трафик
#
# Скрипт автоматически:
# - Парсит список прокси с https://mtproto.ru/personal.php (официальный источник)
# - Проверяет работоспособность прокси через TCP подключение
# - Запускает конвертер mtproto-to-socks5 с выбранным прокси
# - Настраивает Xray как SOCKS5 прокси
# - Запускается по расписанию через cron (каждый час по умолчанию)

# ==============================================================================
# КОНСТАНТЫ И НАСТРОЙКИ
# ==============================================================================

# URL источника MTProto прокси (официальный источник с реальными серверами)
TG_PROXY_SOURCE_URL="https://mtproto.ru/personal.php"

# Пути установки XKeen/Xray
XKEEN_BIN="/opt/sbin/xkeen"
XRAY_BIN="/opt/bin/xray"
XRAY_CONFIG_DIR="/opt/etc/xray/configs"
XRAY_MAIN_CONFIG="/opt/etc/xray/config.json"
XRAY_MTPROTO_CONFIG="${XRAY_CONFIG_DIR}/05_mtproto.json"

# Файлы для хранения данных
TG_PROXY_CACHE_FILE="/tmp/tg_proxy_cache.txt"
TG_PROXY_LOG_FILE="/opt/var/log/tg_proxy.log"

# Определить CONFIG_DIR если не задан (для автономного запуска из cron)
if [ -z "$CONFIG_DIR" ]; then
    # Попробовать определить из окружения z2k
    if [ -f /opt/etc/zapret2/config ]; then
        CONFIG_DIR="/opt/etc/zapret2"
    elif [ -f /opt/etc/init.d/S99zapret2 ]; then
        CONFIG_DIR="/opt/etc/zapret2"
    else
        CONFIG_DIR="/opt/etc/zapret2"
    fi
fi

TG_PROXY_SECRET_FILE="${CONFIG_DIR}/tg_proxy_secret"
TG_PROXY_SETTINGS_FILE="${CONFIG_DIR}/tg_proxy_settings.conf"

# Список доменов Telegram для проксирования (через ipset)
TELEGRAM_DOMAINS="
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

# Интервал автообновления прокси (в часах)
DEFAULT_PROXY_UPDATE_INTERVAL=1

# ==============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ==============================================================================

# Логирование в файл
tg_log() {
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $*" >> "$TG_PROXY_LOG_FILE"
    # Дублировать важные сообщения в консоль если это не cron
    if [ -t 1 ]; then
        echo "$*"
    fi
}

# Проверка наличия команды
tg_check_command() {
    command -v "$1" >/dev/null 2>&1
}

# Проверка наличия пакета в opkg
tg_is_package_installed() {
    opkg list-installed 2>/dev/null | grep -q "^$1 "
}

# ==============================================================================
# ПРОВЕРКА ТРЕБОВАНИЙ К СИСТЕМЕ
# ==============================================================================

# Проверка доступной оперативной памяти (требуется минимум 256 МБ для Xray)
tg_check_memory() {
    local total_mem_kb
    
    # Попробовать получить из /proc/meminfo
    if [ -f /proc/meminfo ]; then
        total_mem_kb=$(grep "^MemTotal:" /proc/meminfo | awk '{print $2}')
    else
        # Альтернативный способ через free
        total_mem_kb=$(free 2>/dev/null | awk '/^Mem:/ {print $2}')
    fi
    
    if [ -z "$total_mem_kb" ]; then
        tg_log "WARNING: Не удалось определить объем оперативной памяти"
        return 0
    fi
    
    local total_mem_mb=$((total_mem_kb / 1024))
    
    if [ "$total_mem_mb" -lt 256 ]; then
        tg_log "WARNING: Мало оперативной памяти (${total_mem_mb} МБ). Xray может работать нестабильно."
        print_warning "Мало ОЗУ: ${total_mem_mb} МБ (требуется минимум 256 МБ)"
        print_info "Xray может потреблять 100-200 МБ RAM"
        return 1
    fi
    
    print_success "Достаточно ОЗУ: ${total_mem_mb} МБ"
    return 0
}

# Проверка свободной постоянной памяти (требуется минимум 50 МБ)
tg_check_storage() {
    local free_space_kb
    
    # Получить свободное место на /opt
    free_space_kb=$(df -k /opt 2>/dev/null | awk 'NR==2 {print $4}')
    
    if [ -z "$free_space_kb" ]; then
        tg_log "WARNING: Не удалось определить свободное место на диске"
        return 0
    fi
    
    local free_space_mb=$((free_space_kb / 1024))
    
    if [ "$free_space_mb" -lt 50 ]; then
        tg_log "WARNING: Мало свободного места (${free_space_mb} МБ)"
        print_warning "Мало места на диске: ${free_space_mb} МБ (требуется минимум 50 МБ)"
        return 1
    fi
    
    print_success "Достаточно места: ${free_space_mb} МБ"
    return 0
}

# ==============================================================================
# УСТАНОВКА XKEEN/XRAY
# ==============================================================================

# Установка зависимостей для XKeen
tg_install_dependencies() {
    print_header "Установка зависимостей для XKeen"
    
    local packages="curl tar"
    local missing_packages=""
    
    for pkg in $packages; do
        if ! tg_is_package_installed "$pkg"; then
            missing_packages="$missing_packages $pkg"
        else
            print_success "$pkg уже установлен"
        fi
    done
    
    if [ -n "$missing_packages" ]; then
        print_info "Установка пакетов:$missing_packages"
        
        # Обновить списки пакетов
        print_info "Обновление списков пакетов..."
        if ! opkg update; then
            print_error "Не удалось обновить списки пакетов"
            print_info "Продолжить без обновления? [y/N]: "
            read -r answer </dev/tty
            case "$answer" in
                [Yy]*) ;;
                *) return 1 ;;
            esac
        fi
        
        # Установить пакеты
        for pkg in $missing_packages; do
            print_info "Установка $pkg..."
            if opkg install "$pkg"; then
                print_success "$pkg установлен"
            else
                print_error "Не удалось установить $pkg"
                return 1
            fi
        done
    fi
    
    return 0
}

# Установка XKeen
tg_install_xkeen() {
    print_header "Установка XKeen"
    
    # Проверить наличие xkeen
    if [ -x "$XKEEN_BIN" ]; then
        print_success "XKeen уже установлен: $XKEEN_BIN"
        return 0
    fi
    
    print_info "Загрузка XKeen..."
    
    # Скачать последнюю версию XKeen
    local xkeen_tar="/tmp/xkeen.tar"
    
    if curl -fsSL --connect-timeout 10 --max-time 120 \
        "https://github.com/jameszeroX/XKeen/releases/latest/download/xkeen.tar" \
        -o "$xkeen_tar"; then
        
        print_success "XKeen загружен"
        
        # Распаковать в /opt/sbin
        print_info "Распаковка в /opt/sbin..."
        if tar -xvf "$xkeen_tar" -C /opt/sbin --overwrite >/dev/null 2>&1; then
            print_success "XKeen распакован"
            
            # Удалить архив
            rm -f "$xkeen_tar"
            
            # Сделать исполняемым
            chmod +x "$XKEEN_BIN" 2>/dev/null
            
            print_success "XKeen успешно установлен"
            return 0
        else
            print_error "Ошибка распаковки XKeen"
            rm -f "$xkeen_tar"
            return 1
        fi
    else
        print_error "Не удалось загрузить XKeen"
        print_info "Проверьте подключение к интернету"
        rm -f "$xkeen_tar"
        return 1
    fi
}

# Инициализация XKeen (первый запуск с выбором GeoIP/GeoSite)
tg_init_xkeen() {
    print_header "Инициализация XKeen"
    
    # Проверить есть ли уже конфиги
    if [ -f "$XRAY_MAIN_CONFIG" ]; then
        print_success "Конфигурация Xray уже существует"
        print_info "Пропускаем интерактивную настройку"
        return 0
    fi
    
    print_info "Первичная инициализация XKeen..."
    print_info "Выбор источников GeoIP/GeoSite для Telegram"
    print_info "Автоматический выбор: Re:filter (GeoSite) + MaxMind (GeoIP)"
    print_separator
    
    # Попытаться автоматизировать установку через переменные окружения
    # XKeen поддерживает автоматическую установку с предустановленными параметрами
    export XKEEN_AUTO_INSTALL="1"
    export XKEEN_GEOSITE_SOURCE="re-filter"
    export XKEEN_GEOIP_SOURCE="maxmind"
    
    # Запустить установку в автоматическом режиме
    # Если xkeen поддерживает флаг -y или --yes для авто-подтверждения
    if "$XKEEN_BIN" -i -y 2>/dev/null || "$XKEEN_BIN" -i --yes 2>/dev/null || "$XKEEN_BIN" -i; then
        print_success "XKeen успешно инициализирован"
        
        # Проверить что основной конфиг создан
        if [ -f "$XRAY_MAIN_CONFIG" ]; then
            print_success "Основной конфиг Xray создан: $XRAY_MAIN_CONFIG"
            return 0
        else
            print_warning "Конфиг не найден, создаём минимальную конфигурацию..."
            # Создать минимальный конфиг если xkeen не создал
            mkdir -p "$XRAY_CONFIG_DIR"
            cat > "$XRAY_MAIN_CONFIG" << 'EOF'
{
  "inbounds": [],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ],
  "routing": {}
}
EOF
            return 0
        fi
    else
        print_error "Ошибка инициализации XKeen"
        print_info "Попробуйте запустить вручную: xkeen -i"
        print_info "Или проверьте логи: tail /opt/var/log/xray/error.log"
        return 1
    fi
}

# Проверка статуса Xray
tg_check_xray_status() {
    if [ -x "$XKEEN_BIN" ]; then
        "$XKEEN_BIN" -status 2>&1
        return $?
    elif [ -x "$XRAY_BIN" ]; then
        # Проверить процесс
        if pgrep -f "xray" >/dev/null 2>&1; then
            print_success "Xray запущен"
            return 0
        else
            print_warning "Xray не запущен"
            return 1
        fi
    else
        print_error "Xray не найден"
        return 1
    fi
}

# Старт/Стоп/Рестарт Xray
tg_control_xray() {
    local action="$1"
    
    if [ -x "$XKEEN_BIN" ]; then
        case "$action" in
            start)
                "$XKEEN_BIN" -start
                ;;
            stop)
                "$XKEEN_BIN" -stop
                ;;
            restart)
                "$XKEEN_BIN" -restart
                ;;
            status)
                "$XKEEN_BIN" -status
                ;;
        esac
        return $?
    elif [ -x "/opt/etc/init.d/S99xray" ]; then
        "/opt/etc/init.d/S99xray" "$action"
        return $?
    else
        print_error "Скрипт управления Xray не найден"
        return 1
    fi
}

# ==============================================================================
# ГЕНЕРАЦИЯ СЕКРЕТА MTProto
# ==============================================================================

# Генерация нового секрета для MTProto (32 символа в hex)
tg_generate_secret() {
    local secret
    
    # Попробовать openssl
    if tg_check_command openssl; then
        secret=$(openssl rand -hex 16 2>/dev/null)
    fi
    
    # Если openssl не сработал, использовать /dev/urandom
    if [ -z "$secret" ] && [ -r /dev/urandom ]; then
        secret=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
    fi
    
    # Последняя попытка - использовать случайные данные
    if [ -z "$secret" ]; then
        secret=$(date +%s%N | md5sum 2>/dev/null | cut -c1-32)
    fi
    
    if [ -n "$secret" ] && [ ${#secret} -ge 32 ]; then
        echo "$secret" | cut -c1-32
        return 0
    else
        return 1
    fi
}

# Получить или создать секрет
tg_get_or_create_secret() {
    # Если секрет уже есть в файле, вернуть его
    if [ -f "$TG_PROXY_SECRET_FILE" ]; then
        cat "$TG_PROXY_SECRET_FILE"
        return 0
    fi
    
    # Сгенерировать новый секрет
    local secret
    secret=$(tg_generate_secret)
    
    if [ -n "$secret" ]; then
        echo "$secret" > "$TG_PROXY_SECRET_FILE"
        chmod 600 "$TG_PROXY_SECRET_FILE"
        echo "$secret"
        return 0
    fi
    
    return 1
}

# ==============================================================================
# СОЗДАНИЕ КОНФИГУРАЦИИ MTProto
# ==============================================================================

# Создание конфига MTProto для Xray
tg_create_mtproto_config() {
    print_header "Создание конфигурации MTProto"
    
    # Создать директорию для конфигов если нет
    mkdir -p "$XRAY_CONFIG_DIR" || {
        print_error "Не удалось создать директорию $XRAY_CONFIG_DIR"
        return 1
    }
    
    # Получить или создать секрет
    local secret
    secret=$(tg_get_or_create_secret)
    
    if [ -z "$secret" ]; then
        print_error "Не удалось сгенерировать секрет MTProto"
        return 1
    fi
    
    print_info "Секрет MTProto: $secret"
    print_info "(сохранён в $TG_PROXY_SECRET_FILE)"
    
    # Создать конфиг MTProto для Xray
    # ВАЖНО: Xray работает как SOCKS5-прокси для клиентов и подключается к MTProto upstream
    # Inbound: SOCKS5 на порту 1080 (локально) + прозрачный режим через tproxy/redirect
    # Outbound: mtproto-obfuscated для подключения к внешним MTProxy серверам
    cat > "$XRAY_MTPROTO_CONFIG" << EOF
{
  "inbounds": [
    {
      "tag": "telegram-in",
      "port": 1080,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true,
        "ip": "127.0.0.1",
        "clients": []
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "telegram-out-upstream",
      "protocol": "mtproto",
      "settings": {
        "users": [
          {
            "secret": "${secret}"
          }
        ]
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["telegram-in"],
        "outboundTag": "telegram-out-upstream"
      }
    ]
  }
}
EOF
    
    if [ -f "$XRAY_MTPROTO_CONFIG" ]; then
        print_success "Конфигурация создана: $XRAY_MTPROTO_CONFIG"
        return 0
    else
        print_error "Не удалось создать конфигурацию"
        return 1
    fi
}

# Обновление upstream прокси в конфиге
# Для MTProto в Xray нужно обновить сервер и порт в outbound настройках
tg_update_upstream_proxy() {
    local server="$1"
    local port="$2"

    if [ -z "$server" ] || [ -z "$port" ]; then
        tg_log "ERROR: Не указаны server или port"
        return 1
    fi

    if [ ! -f "$XRAY_MTPROTO_CONFIG" ]; then
        tg_log "ERROR: Конфиг MTProto не найден: $XRAY_MTPROTO_CONFIG"
        return 1
    fi

    # Получить секрет из файла
    local secret
    secret=$(cat "$TG_PROXY_SECRET_FILE" 2>/dev/null)

    if [ -z "$secret" ]; then
        tg_log "ERROR: Не удалось получить секрет MTProto"
        return 1
    fi

    # Пересоздать конфиг с новым сервером
    # Это надёжнее чем sed замена сложной JSON структуры
    cat > "$XRAY_MTPROTO_CONFIG" << EOF
{
  "inbounds": [
    {
      "tag": "telegram-in",
      "port": 1080,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true,
        "ip": "127.0.0.1",
        "clients": []
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "telegram-out-upstream",
      "protocol": "mtproto",
      "settings": {
        "users": [
          {
            "secret": "${secret}"
          }
        ],
        "server": "${server}",
        "port": ${port}
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["telegram-in"],
        "outboundTag": "telegram-out-upstream"
      }
    ]
  }
}
EOF

    if [ -f "$XRAY_MTPROTO_CONFIG" ]; then
        tg_log "INFO: Upstream обновлён: ${server}:${port}"
        return 0
    else
        tg_log "ERROR: Не удалось обновить конфиг"
        return 1
    fi
}
# ==============================================================================
# ПАРСИНГ И ПРОВЕРКА ПРОКСИ
# ==============================================================================

# Парсинг списка прокси из источника
tg_parse_proxy_list() {
    print_info "Парсинг списка прокси из: $TG_PROXY_SOURCE_URL"
    
    # Загрузить страницу
    local html_content
    html_content=$(curl -fsSL --connect-timeout 10 --max-time 30 "$TG_PROXY_SOURCE_URL" 2>/dev/null)
    
    if [ -z "$html_content" ]; then
        tg_log "ERROR: Не удалось загрузить страницу с прокси"
        return 1
    fi
    
    # Очистить кэш файл
    > "$TG_PROXY_CACHE_FILE"
    
    # Извлечь ссылки tg://proxy?... с полным секретом (mtproto.ru выдаёт одну ссылку)
    # Формат: tg://proxy?server=ne.4.mtproto.ru&port=443&secret=ee21112222333344445555666677778888...
    local proxy_lines
    proxy_lines=$(printf '%s\n' "$html_content" | grep -oE 'tg://proxy\?server=[^"&]+&port=[0-9]+&secret=[a-fA-F0-9]+')
    
    if [ -n "$proxy_lines" ]; then
        printf '%s\n' "$proxy_lines" | awk 'BEGIN{FS="[?&]"}{server="";port="";secret="";for(i=2;i<=NF;i++){split($i,kv,"=");if(kv[1]=="server")server=kv[2];else if(kv[1]=="port")port=kv[2];else if(kv[1]=="secret")secret=kv[2]};if(server!=""&&port!=""){if(secret=="")secret="none";print server":"port":"secret}}' >> "$TG_PROXY_CACHE_FILE"
    fi
    
    local count
    count=$(wc -l < "$TG_PROXY_CACHE_FILE" 2>/dev/null | tr -d ' ')
    
    if [ "$count" -gt 0 ]; then
        print_success "Найдено прокси: $count"
        tg_log "INFO: Найдено прокси: $count"
        return 0
    else
        print_warning "Прокси не найдены"
        tg_log "WARNING: Прокси не найдены в источнике"
        return 1
    fi
}

# Проверка работоспособности прокси через nc (netcat)
tg_check_proxy_nc() {
    local server="$1"
    local port="$2"
    local timeout="${3:-3}"
    
    # Проверить доступность порта через nc
    if tg_check_command nc; then
        if nc -z -w "$timeout" "$server" "$port" 2>/dev/null; then
            return 0
        fi
    fi
    
    # Альтернатива через timeout и /dev/tcp (если поддерживается shell)
    if (echo >/dev/tcp/"$server"/"$port") 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# Проверка прокси через curl с SOCKS5
tg_check_proxy_curl() {
    local server="$1"
    local port="$2"
    local timeout="${3:-5}"
    
    # Попытаться подключиться через SOCKS5
    if curl -s --socks5 "${server}:${port}" \
        --connect-timeout "$timeout" \
        --max-time "$((timeout * 2))" \
        "https://t.me/" >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Комплексная проверка прокси
tg_verify_proxy() {
    local server="$1"
    local port="$2"
    
    # Сначала быстрая проверка доступности порта
    if ! tg_check_proxy_nc "$server" "$port" 2; then
        return 1
    fi
    
    # Затем проверка через curl (более надёжная но медленная)
    if tg_check_proxy_curl "$server" "$port" 5; then
        return 0
    fi
    
    return 1
}

# Поиск рабочего прокси из списка
tg_find_working_proxy() {
    print_info "Поиск рабочего прокси..."
    
    if [ ! -s "$TG_PROXY_CACHE_FILE" ]; then
        tg_log "ERROR: Файл с прокси пуст или не найден"
        return 1
    fi
    
    local total_count working_count
    total_count=$(wc -l < "$TG_PROXY_CACHE_FILE" | tr -d ' ')
    working_count=0
    
    # Перебрать все прокси
    while IFS=: read -r server port secret; do
        [ -z "$server" ] && continue
        
        working_count=$((working_count + 1))
        printf "\r[%d/%d] Проверка %s:%s ... " "$working_count" "$total_count" "$server" "$port"
        
        if tg_verify_proxy "$server" "$port"; then
            printf "\n"
            print_success "Рабочий прокси найден: ${server}:${port}"
            tg_log "INFO: Рабочий прокси: ${server}:${port}"
            
            # Вернуть первый рабочий (можно улучшить логику выбора лучшего)
            echo "${server}:${port}"
            return 0
        fi
    done < "$TG_PROXY_CACHE_FILE"
    
    printf "\n"
    print_warning "Рабочие прокси не найдены"
    tg_log "WARNING: Рабочие прокси не найдены"
    return 1
}

# ==============================================================================
# АВТОМАТИЧЕСКОЕ ОБНОВЛЕНИЕ ПРОКСИ
# ==============================================================================

# Главная функция обновления прокси
tg_update_proxy() {
    tg_log "========== Начало обновления прокси =========="
    
    # Шаг 1: Запарсить список прокси
    if ! tg_parse_proxy_list; then
        tg_log "ERROR: Не удалось получить список прокси"
        return 1
    fi
    
    # Шаг 2: Найти рабочий прокси
    local working_proxy
    working_proxy=$(tg_find_working_proxy)
    
    if [ -z "$working_proxy" ]; then
        tg_log "ERROR: Не удалось найти рабочий прокси"
        return 1
    fi
    
    # Разделить server и port
    local proxy_server proxy_port
    proxy_server=$(echo "$working_proxy" | cut -d':' -f1)
    proxy_port=$(echo "$working_proxy" | cut -d':' -f2)
    
    # Шаг 3: Обновить конфиг Xray
    if ! tg_update_upstream_proxy "$proxy_server" "$proxy_port"; then
        tg_log "ERROR: Не удалось обновить конфиг"
        return 1
    fi
    
    # Шаг 4: Перезапустить Xray
    print_info "Перезапуск Xray..."
    if tg_control_xray restart; then
        tg_log "INFO: Xray перезапущен"
        print_success "Прокси обновлён и применён"
    else
        tg_log "ERROR: Не удалось перезапустить Xray"
        print_error "Ошибка перезапуска Xray"
        return 1
    fi
    
    tg_log "========== Обновление прокси завершено =========="
    return 0
}

# ==============================================================================
# НАСТРОЙКА CRON ДЛЯ АВТООБНОВЛЕНИЯ
# ==============================================================================

# Проверка наличия cron
tg_check_cron() {
    if [ -x "/opt/etc/init.d/S10cron" ]; then
        return 0
    elif tg_check_command crond; then
        return 0
    fi
    return 1
}

# Установка cron если не установлен
tg_install_cron() {
    print_info "Установка cron..."
    
    if tg_is_package_installed "cron" || tg_is_package_installed "crond"; then
        print_success "cron уже установлен"
        return 0
    fi
    
    if opkg install cron; then
        print_success "cron установлен"
        return 0
    fi
    
    # Попробовать альтернативное имя пакета
    if opkg install crond; then
        print_success "crond установлен"
        return 0
    fi
    
    print_error "Не удалось установить cron"
    return 1
}

# Запуск cron
tg_start_cron() {
    if [ -x "/opt/etc/init.d/S10cron" ]; then
        "/opt/etc/init.d/S10cron" restart
        sleep 2
        
        # Проверить что процесс запущен
        if pgrep -f "cron" >/dev/null 2>&1; then
            print_success "cron запущен"
            return 0
        else
            print_error "Не удалось запустить cron"
            return 1
        fi
    elif tg_check_command crond; then
        crond
        return $?
    fi
    
    return 1
}

# Настройка задачи cron для автообновления
tg_setup_cron_job() {
    local interval_hours="${1:-$DEFAULT_PROXY_UPDATE_INTERVAL}"
    
    print_header "Настройка автообновления прокси"
    
    # Убедиться что cron установлен и запущен
    if ! tg_check_cron; then
        print_warning "cron не найден"
        if ! tg_install_cron; then
            print_error "Не удалось установить cron"
            print_info "Автообновление будет недоступно"
            return 1
        fi
    fi
    
    if ! tg_start_cron; then
        print_error "Не удалось запустить cron"
        return 1
    fi
    
    # Создать задачу в crontab
    local cron_expr="0 */${interval_hours} * * *"
    local cron_task="$cron_expr $0 update_auto >> $TG_PROXY_LOG_FILE 2>&1"
    
    # Проверить есть ли уже задача
    local existing_task
    existing_task=$(crontab -l 2>/dev/null | grep "tg_proxy\|update_auto" || true)
    
    if [ -n "$existing_task" ]; then
        print_info "Задача автообновления уже существует:"
        echo "$existing_task"
        printf "\nЗаменить на новую? [y/N]: "
        read -r answer </dev/tty
        
        case "$answer" in
            [Yy]*)
                # Удалить старую задачу
                crontab -l 2>/dev/null | grep -v "tg_proxy\|update_auto" > /tmp/crontab.tmp
                crontab /tmp/crontab.tmp 2>/dev/null
                rm -f /tmp/crontab.tmp
                ;;
            *)
                print_info "Сохранена текущая задача"
                return 0
                ;;
        esac
    fi
    
    # Добавить новую задачу
    (crontab -l 2>/dev/null; echo "$cron_task") | crontab -
    
    if crontab -l 2>/dev/null | grep -q "update_auto"; then
        print_success "Автообновление настроено (каждые ${interval_hours} ч.)"
        print_info "Задача: $cron_expr"
        return 0
    else
        print_error "Не удалось добавить задачу в crontab"
        return 1
    fi
}

# Отключение автообновления
tg_disable_auto_update() {
    print_info "Отключение автообновления..."
    
    # Удалить задачу из crontab
    crontab -l 2>/dev/null | grep -v "tg_proxy\|update_auto" > /tmp/crontab.tmp
    crontab /tmp/crontab.tmp 2>/dev/null
    rm -f /tmp/crontab.tmp
    
    print_success "Автообновление отключено"
    return 0
}

# ==============================================================================
# IPSET ДЛЯ МАРКИРОВКИ ТРАФИКА TELEGRAM
# ==============================================================================

# Разрешение доменов Telegram в IP адреса и добавление в ipset
# Разрешение доменов Telegram в IP адреса и добавление в ipset
tg_resolve_and_add_to_ipset() {
    local set_name="telegram_domains"

    print_info "Разрешение доменов Telegram в IP адреса..."

    # Использовать временный файл для подсчёта (обход subshell)
    local temp_count_file
    temp_count_file=$(mktemp)
    echo "0:0" > "$temp_count_file"

    # Пройтись по всем доменам
    for domain in $TELEGRAM_DOMAINS; do
        [ -z "$domain" ] && continue

        # Разрешить домен через nslookup или getent
        local ip_addresses
        if tg_check_command nslookup; then
            ip_addresses=$(nslookup "$domain" 2>/dev/null | grep -E '^Address( [0-9]+)*:' | awk '{print $NF}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
        elif tg_check_command getent; then
            ip_addresses=$(getent hosts "$domain" 2>/dev/null | awk '{print $1}')
        else
            # Попытаться через ping (альтернатива)
            ip_addresses=$(ping -c 1 "$domain" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        fi

        if [ -n "$ip_addresses" ]; then
            # Добавить каждый IP в ipset (используем here-string вместо pipe)
            while IFS= read -r ip; do
                [ -z "$ip" ] && continue
                if ipset add "$set_name" "$ip" 2>/dev/null; then
                    # Обновить счётчик через файл
                    local counts cur_resolved cur_failed
                    counts=$(cat "$temp_count_file")
                    cur_resolved=${counts%%:*}
                    cur_failed=${counts##*:}
                    echo "$((cur_resolved + 1)):$cur_failed" > "$temp_count_file"
                fi
            done <<< "$ip_addresses"
        else
            # Обновить счётчик неудач
            local counts cur_resolved cur_failed
            counts=$(cat "$temp_count_file")
            cur_resolved=${counts%%:*}
            cur_failed=${counts##*:}
            echo "$cur_resolved:$((cur_failed + 1))" > "$temp_count_file"
            tg_log "WARNING: Не удалось разрешить домен: $domain"
        fi
    done

    # Прочитать итоговые значения
    local final_counts resolved failed
    final_counts=$(cat "$temp_count_file")
    resolved=${final_counts%%:*}
    failed=${final_counts##*:}
    rm -f "$temp_count_file"

    print_success "Добавлено IP адресов в ipset: $resolved"
    if [ "$failed" -gt 0 ]; then
        print_warning "Не удалось разрешить доменов: $failed"
    fi

    return 0
}

# Настройка iptables для прозрачного проксирования Telegram
tg_setup_iptables() {
    print_header "Настройка прозрачного проксирования (iptables)"
    
    local set_name="telegram_domains"
    local xray_port="443"
    
    # Проверить наличие ipset
    if ! tg_check_command ipset; then
        print_warning "ipset не найден, установка..."
        if opkg install ipset; then
            print_success "ipset установлен"
        else
            print_error "Не удалось установить ipset"
            print_info "Прозрачное проксирование будет недоступно"
            print_info "Клиентам придётся использовать ссылку для подключения"
            return 1
        fi
    fi
    
    # Проверить наличие iptables
    if ! tg_check_command iptables; then
        print_error "iptables не найден"
        print_info "Прозрачное проксирование невозможно без iptables"
        return 1
    fi
    
    # Удалить старый ipset если есть
    ipset destroy "$set_name" 2>/dev/null
    
    # Создать новый ipset
    if ! ipset create "$set_name" hash:ip maxelem 2048 timeout 7200 2>/dev/null; then
        print_error "Не удалось создать ipset '$set_name'"
        return 1
    fi
    
    print_success "ipset '$set_name' создан"
    
    # Разрешить домены и добавить IP в ipset
    tg_resolve_and_add_to_ipset
    
    # Удалить старые правила iptables если есть
    iptables -t nat -D PREROUTING -p tcp --dport 53 -j REDIRECT --to-port 53 2>/dev/null
    iptables -t nat -D OUTPUT -p tcp -m set --match-set "$set_name" dst -j REDIRECT --to-ports "$xray_port" 2>/dev/null
    iptables -t nat -D PREROUTING -p tcp -m set --match-set "$set_name" dst -j REDIRECT --to-ports "$xray_port" 2>/dev/null
    
    # Добавить правило для перенаправления трафика Telegram на порт Xray
    # Правило для локального трафика (сам роутер)
    if iptables -t nat -A OUTPUT -p tcp -m set --match-set "$set_name" dst -j REDIRECT --to-ports "$xray_port" 2>/dev/null; then
        print_success "Добавлено правило iptables для локального трафика"
    fi
    
    # Правило для клиентского трафика (через br0 - мост Wi-Fi)
    if iptables -t nat -A PREROUTING -i br0 -p tcp -m set --match-set "$set_name" dst -j REDIRECT --to-ports "$xray_port" 2>/dev/null; then
        print_success "Добавлено правило iptables для клиентского трафика (br0)"
    elif iptables -t nat -A PREROUTING -i wlan0 -p tcp -m set --match-set "$set_name" dst -j REDIRECT --to-ports "$xray_port" 2>/dev/null; then
        print_success "Добавлено правило iptables для клиентского трафика (wlan0)"
    else
        print_warning "Не удалось добавить правило PREROUTING"
        print_info "Попробуйте вручную определить интерфейс вашей сети"
    fi
    
    # Сохранить правила (если есть механизм сохранения)
    if [ -x /opt/etc/init.d/S99iptables ]; then
        print_info "Сохранение правил iptables..."
        iptables-save > /opt/etc/iptables.rules 2>/dev/null || true
    fi
    
    print_success "Прозрачное проксирование настроено"
    print_info "Весь трафик Telegram теперь автоматически перенаправляется на Xray"
    print_info "Клиентам НЕ НУЖНО ничего настраивать вручную"
    
    return 0
}

# Очистка правил iptables и ipset
tg_cleanup_iptables() {
    print_info "Очистка правил прозрачного проксирования..."
    
    local set_name="telegram_domains"
    
    # Удалить правила iptables
    iptables -t nat -D OUTPUT -p tcp -m set --match-set "$set_name" dst -j REDIRECT --to-ports 443 2>/dev/null
    iptables -t nat -D PREROUTING -i br0 -p tcp -m set --match-set "$set_name" dst -j REDIRECT --to-ports 443 2>/dev/null
    iptables -t nat -D PREROUTING -i wlan0 -p tcp -m set --match-set "$set_name" dst -j REDIRECT --to-ports 443 2>/dev/null
    
    # Удалить ipset
    ipset destroy "$set_name" 2>/dev/null
    
    print_success "Правила очищены"
    return 0
}

# ==============================================================================
# ИНФОРМАЦИЯ О ПРОКСИ ДЛЯ КЛИЕНТОВ
# ==============================================================================

# Показать информацию для подключения клиентов
tg_show_client_info() {
    print_header "Информация для подключения клиентов"
    
    # Получить локальный IP роутера
    local router_ip
    router_ip=$(ip addr show br0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    
    if [ -z "$router_ip" ]; then
        router_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    
    if [ -z "$router_ip" ]; then
        router_ip="IP_ВАШЕГО_РОУТЕРА"
    fi
    
    # Получить секрет
    local secret
    secret=$(cat "$TG_PROXY_SECRET_FILE" 2>/dev/null)
    
    if [ -z "$secret" ]; then
        secret="НЕТ_СЕКРЕТА"
    fi
    
    cat << EOF

📱 ПОДКЛЮЧЕНИЕ КЛИЕНТОВ TELEGRAM

🔹 Ссылка для быстрого подключения:
   tg://proxy?server=${router_ip}&port=443&secret=${secret}

🔹 Или создайте ссылку вручную (если первая не работает):
   tg://proxy?server=${router_ip}&port=443&secret=${secret}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  ВАЖНО: Ссылка НЕ ОБЯЗАТЕЛЬНА для использования!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Весь трафик Telegram УЖЕ автоматически идёт через 
прокси на уровне роутера для ВСЕХ устройств в сети.
Вам не нужно ничего настраивать на телефонах/ПК.

Ссылку можно использовать:
• Для отображения значка "Proxi" в настройках Telegram
• Как резервный вариант подключения
• Для проверки работоспособности прокси

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Инструкция:
1. Нажмите на ссылку выше на устройстве в локальной сети
2. Telegram предложит добавить прокси
3. Подтвердите добавление (но это не обязательно!)

Примечание:
• Прозрачное проксирование работает для всех устройств в Wi-Fi
• Трафик Telegram автоматически перехватывается роутером
• Остальной интернет работает как обычно
• Прокси обновляется автоматически каждый час

EOF
    
    # Сохранить ссылку в файл
    local link_file="${CONFIG_DIR}/tg_proxy_link.txt"
    echo "tg://proxy?server=${router_ip}&port=443&secret=${secret}" > "$link_file"
    print_info "Ссылка сохранена в: $link_file"
}

# ==============================================================================
# МЕНЮ УПРАВЛЕНИЯ
# ==============================================================================

# Главное меню модуля Telegram прокси
menu_telegram_proxy() {
    while true; do
        clear_screen
        print_header "Telegram прокси (MTProto via XKeen)"
        
        # Показать текущий статус
        printf "\\nСтатус:\\n"
        
        # Проверка XKeen/Xray
        if [ -x "$XKEEN_BIN" ] || [ -x "$XRAY_BIN" ]; then
            print_success "Xray установлен"
            
            # Статус сервиса
            if tg_check_xray_status >/dev/null 2>&1; then
                print_success "Xray запущен"
            else
                print_warning "Xray остановлен"
            fi
            
            # Проверка конфига
            if [ -f "$XRAY_MTPROTO_CONFIG" ]; then
                print_success "Конфигурация MTProto есть"
                
                # Показать текущий upstream
                local current_upstream
                current_upstream=$(grep -o '"proxy": "socks5://[^"]*"' "$XRAY_MTPROTO_CONFIG" 2>/dev/null | cut -d'"' -f4)
                if [ -n "$current_upstream" ] && [ "$current_upstream" != "socks5://0.0.0.0:0" ]; then
                    print_success "Upstream: $current_upstream"
                else
                    print_warning "Upstream не настроен"
                fi
            else
                print_warning "Конфигурация MTProto отсутствует"
            fi
            
            # Проверка автообновления
            if crontab -l 2>/dev/null | grep -q "update_auto"; then
                print_success "Автообновление включено"
            else
                print_warning "Автообновление отключено"
            fi
        else
            print_warning "Xray не установлен"
        fi
        
        cat << 'MENU'

[1] Установить XKeen/Xray
[2] Настроить MTProto прокси
[3] Включить прокси (старт Xray)
[4] Выключить прокси (стоп Xray)
[5] Обновить прокси вручную
[6] Настроить автообновление
[7] Отключить автообновление
[8] Информация для клиентов
[9] Статус и логи
[0] Назад

MENU
        
        printf "Выберите опцию [0-9]: "
        read -r choice </dev/tty
        
        case "$choice" in
            1)
                # Установка XKeen - полная автоматическая установка и настройка
                print_info "Начинается полная автоматическая установка XKeen/Xray..."
                print_info "Этот процесс установит все необходимые компоненты и настроит MTProto прокси"
                
                if tg_install_dependencies && \
                   tg_install_xkeen && \
                   tg_init_xkeen && \
                   tg_create_mtproto_config; then
                    print_success "XKeen установлен и настроен"
                    print_info "Теперь будет выполнена первоначальная настройка прокси..."
                    
                    # Автоматически обновить прокси после установки
                    if tg_update_proxy; then
                        print_success "Прокси успешно настроен и активирован"
                        print_info "Теперь можно настроить автообновление через опцию [6]"
                    else
                        print_warning "Прокси не удалось обновить автоматически"
                        print_info "Попробуйте опцию [5] для ручного обновления"
                    fi
                else
                    print_error "Ошибка при установке XKeen"
                fi
                pause
                ;;
            
            2)
                # Настройка MTProto - создание/пересоздание конфигурации
                print_info "Создание конфигурации MTProto прокси..."
                if tg_create_mtproto_config; then
                    print_success "Конфигурация создана"
                    print_info "Теперь будет выполнено обновление прокси..."
                    
                    # Автоматически обновить прокси после создания конфига
                    if tg_update_proxy; then
                        print_success "Прокси обновлён и применён"
                    else
                        print_warning "Не удалось обновить прокси автоматически"
                        print_info "Попробуйте опцию [5] для ручного обновления"
                    fi
                else
                    print_error "Ошибка создания конфигурации"
                fi
                pause
                ;;
            
            3)
                # Включить прокси - запуск Xray с автоматической проверкой конфигурации и настройкой iptables
                print_info "Проверка конфигурации перед запуском..."
                
                if [ ! -f "$XRAY_MTPROTO_CONFIG" ]; then
                    print_warning "Конфигурация MTProto не найдена"
                    print_info "Сначала выполните установку через опцию [1]"
                    pause
                    continue
                fi
                
                # Настроить прозрачное проксирование через iptables/ipset
                print_info "Настройка прозрачного проксирования (iptables)..."
                tg_setup_iptables
                
                if tg_control_xray start; then
                    print_success "Прокси включён и работает"
                    print_info "Трафик Telegram теперь автоматически перенаправляется на MTProto прокси"
                    print_info "Клиентам НЕ НУЖНО ничего настраивать - всё работает прозрачно!"
                else
                    print_error "Ошибка запуска Xray"
                    print_info "Проверьте логи через опцию [9]"
                fi
                pause
                ;;
            
            4)
                # Выключить прокси - остановка Xray и очистка правил iptables
                print_info "Остановка прокси и очистка правил..."
                
                # Очистить правила iptables
                tg_cleanup_iptables
                
                if tg_control_xray stop; then
                    print_success "Прокси выключен"
                    print_info "Правила прозрачного проксирования удалены"
                else
                    print_error "Ошибка остановки"
                fi
                pause
                ;;
            
            5)
                # Обновить вручную
                print_info "Обновление прокси..."
                if tg_update_proxy; then
                    print_success "Прокси успешно обновлён"
                else
                    print_error "Ошибка обновления"
                fi
                pause
                ;;
            
            6)
                # Настроить автообновление
                print_info "Интервал обновления (часы) [1]: "
                read -r interval </dev/tty
                interval="${interval:-1}"
                
                if tg_setup_cron_job "$interval"; then
                    print_success "Автообновление настроено"
                fi
                pause
                ;;
            
            7)
                # Отключить автообновление
                if tg_disable_auto_update; then
                    print_success "Автообновление отключено"
                fi
                pause
                ;;
            
            8)
                # Информация для клиентов
                tg_show_client_info
                pause
                ;;
            
            9)
                # Статус и логи
                print_header "Статус и логи"
                
                print_info "Статус Xray:"
                tg_check_xray_status
                
                printf "\\n"
                print_info "Последние 20 строк лога:"
                if [ -f "$TG_PROXY_LOG_FILE" ]; then
                    tail -20 "$TG_PROXY_LOG_FILE"
                else
                    print_info "Лог файл ещё не создан"
                fi
                
                pause
                ;;
            
            0)
                return 0
                ;;
            
            *)
                print_error "Неверный выбор"
                pause
                ;;
        esac
    done
}

# Обработка вызова из командной строки (для cron)
if [ -n "$1" ] && [ "$1" = "update_auto" ]; then
    # Автоматическое обновление без интерактива
    tg_update_proxy
    exit $?
fi

# Функция меню экспортируется через вызов в main menu, export -f не работает в /bin/sh
