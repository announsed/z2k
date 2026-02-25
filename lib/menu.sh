#!/bin/sh
# lib/menu.sh - РРЅС‚РµСЂР°РєС‚РёРІРЅРѕРµ РјРµРЅСЋ СѓРїСЂР°РІР»РµРЅРёСЏ z2k
# 9 РѕРїС†РёР№ РґР»СЏ РїРѕР»РЅРѕРіРѕ СѓРїСЂР°РІР»РµРЅРёСЏ zapret2

# ==============================================================================
# Р’РЎРџРћРњРћР“РђРўР•Р›Р¬РќРђРЇ Р¤РЈРќРљР¦РРЇ Р”Р›РЇ Р§РўР•РќРРЇ Р’Р’РћР”Рђ
# ==============================================================================

# Р§РёС‚Р°С‚СЊ РІРІРѕРґ РїРѕР»СЊР·РѕРІР°С‚РµР»СЏ (СЂР°Р±РѕС‚Р°РµС‚ РґР°Р¶Рµ РєРѕРіРґР° stdin РїРµСЂРµРЅР°РїСЂР°РІР»РµРЅ С‡РµСЂРµР· pipe)
read_input() {
    read -r "$@" </dev/tty
}

# ==============================================================================
# Р“Р›РђР’РќРћР• РњР•РќР®
# ==============================================================================

show_main_menu() {
    while true; do
        clear_screen

        cat <<'MENU'
+===================================================+
|   z2k - Zapret2 РґР»СЏ Keenetic (BETA)             |
+===================================================+


MENU

        # РџРѕРєР°Р·Р°С‚СЊ С‚РµРєСѓС‰РёР№ СЃС‚Р°С‚СѓСЃ
        printf "\n"
        printf " РЎРѕСЃС‚РѕСЏРЅРёРµ: %s\n" "$(is_zapret2_installed && echo 'РЈСЃС‚Р°РЅРѕРІР»РµРЅ' || echo 'РќРµ СѓСЃС‚Р°РЅРѕРІР»РµРЅ')"

        if is_zapret2_installed; then
            printf " РЎРµСЂРІРёСЃ: %s\n" "$(get_service_status)"

            # РџСЂРѕРІРµСЂРёС‚СЊ СЂРµР¶РёРј СЃС‚СЂР°С‚РµРіРёР№
            if [ -f "$CATEGORY_STRATEGIES_CONF" ]; then
                local count
                count=$(grep -c ":" "$CATEGORY_STRATEGIES_CONF" 2>/dev/null || echo 0)
                printf " РЎС‚СЂР°С‚РµРіРёРё: %s РєР°С‚РµРіРѕСЂРёР№\n" "$count"
            else
                printf " РўРµРєСѓС‰Р°СЏ СЃС‚СЂР°С‚РµРіРёСЏ: #%s\n" "$(get_current_strategy)"
            fi

            # РџСЂРѕРІРµСЂРёС‚СЊ СЂРµР¶РёРј ALL TCP-443
            local all_tcp443_conf="${CONFIG_DIR}/all_tcp443.conf"
            if [ -f "$all_tcp443_conf" ]; then
                . "$all_tcp443_conf"
                if [ "$ENABLED" = "1" ]; then
                    printf " ALL TCP-443: Р’РєР»СЋС‡РµРЅ (СЃС‚СЂР°С‚РµРіРёСЏ #%s)\n" "$STRATEGY"
                fi
            fi

        fi

        cat <<'MENU'

[1] РЈСЃС‚Р°РЅРѕРІРёС‚СЊ/РџРµСЂРµСѓСЃС‚Р°РЅРѕРІРёС‚СЊ zapret2
[2] Р’С‹Р±СЂР°С‚СЊ СЃС‚СЂР°С‚РµРіРёСЋ
[3] RuTracker blockcheck
[4] РЈРїСЂР°РІР»РµРЅРёРµ СЃРµСЂРІРёСЃРѕРј
[5] РћР±РЅРѕРІРёС‚СЊ СЃРїРёСЃРєРё РґРѕРјРµРЅРѕРІ
[6] Р РµР·РµСЂРІРЅР°СЏ РєРѕРїРёСЏ/Р’РѕСЃСЃС‚Р°РЅРѕРІР»РµРЅРёРµ
[7] РЈРґР°Р»РёС‚СЊ zapret2
[A] Р РµР¶РёРј ALL TCP-443 (Р±РµР· С…РѕСЃС‚Р»РёСЃС‚РѕРІ)
[Q] РќР°СЃС‚СЂРѕР№РєРё QUIC
[W] Whitelist (РёСЃРєР»СЋС‡РµРЅРёСЏ)
[0] Р’С‹С…РѕРґ

MENU

        printf "Р’С‹Р±РµСЂРёС‚Рµ РѕРїС†РёСЋ [0-7,A,Q,W]: "
        read_input choice

        case "$choice" in
            1)
                menu_install
                ;;
            2)
                menu_select_strategy
                ;;
            3)
                menu_rutracker_blockcheck
                ;;
            4)
                menu_service_control
                ;;
            5)
                menu_update_lists
                ;;
            6)
                menu_backup_restore
                ;;
            7)
                menu_uninstall
                ;;
            a|A)
                menu_all_tcp443
                ;;
            q|Q)
                menu_quic_settings
                ;;
            w|W)
                menu_whitelist
                ;;
            0)
                print_info "Р’С‹С…РѕРґ РёР· РјРµРЅСЋ"
                return 0
                ;;
            *)
                print_error "РќРµРІРµСЂРЅС‹Р№ РІС‹Р±РѕСЂ: $choice"
                pause
                ;;
        esac
    done
}

# ==============================================================================
# РџРћР”РњР•РќР®: РЈРЎРўРђРќРћР’РљРђ
# ==============================================================================

menu_install() {
    clear_screen
    print_header "[1] РЈСЃС‚Р°РЅРѕРІРєР°/РџРµСЂРµСѓСЃС‚Р°РЅРѕРІРєР° zapret2"

    if is_zapret2_installed; then
        print_warning "zapret2 СѓР¶Рµ СѓСЃС‚Р°РЅРѕРІР»РµРЅ"
        printf "\nРџРµСЂРµСѓСЃС‚Р°РЅРѕРІРёС‚СЊ? [y/N]: "
        read_input answer

        case "$answer" in
            [Yy]|[Yy][Ee][Ss])
                run_full_install
                ;;
            *)
                print_info "РЈСЃС‚Р°РЅРѕРІРєР° РѕС‚РјРµРЅРµРЅР°"
                ;;
        esac
    else
        run_full_install
    fi

    pause
}

# ==============================================================================
# РџРћР”РњР•РќР®: Р’Р«Р‘РћР  РЎРўР РђРўР•Р“РР
# ==============================================================================

menu_select_strategy() {
    clear_screen
    print_header "[2] Р’С‹Р±РѕСЂ СЃС‚СЂР°С‚РµРіРёРё РїРѕ РєР°С‚РµРіРѕСЂРёСЏРј"

    if ! is_zapret2_installed; then
        print_error "zapret2 РЅРµ СѓСЃС‚Р°РЅРѕРІР»РµРЅ"
        print_info "РЎРЅР°С‡Р°Р»Р° РІС‹РїРѕР»РЅРёС‚Рµ СѓСЃС‚Р°РЅРѕРІРєСѓ (РѕРїС†РёСЏ 1)"
        pause
        return
    fi

    local total_count
    total_count=$(get_strategies_count)
    # РџСЂРѕС‡РёС‚Р°С‚СЊ С‚РµРєСѓС‰РёРµ СЃС‚СЂР°С‚РµРіРёРё
    local config_file="${CONFIG_DIR}/category_strategies.conf"
    local current_yt_tcp="1"
    local current_yt_gv="1"
    local current_rkn="1"

    if [ -f "$config_file" ]; then
        current_yt_tcp=$(grep "^youtube_tcp:" "$config_file" 2>/dev/null | cut -d':' -f2)
        current_yt_gv=$(grep "^youtube_gv:" "$config_file" 2>/dev/null | cut -d':' -f2)
        current_rkn=$(grep "^rkn:" "$config_file" 2>/dev/null | cut -d':' -f2)
        [ -z "$current_yt_tcp" ] && current_yt_tcp="1"
        [ -z "$current_yt_gv" ] && current_yt_gv="1"
        [ -z "$current_rkn" ] && current_rkn="1"
    fi

    print_separator
    print_info "РўРµРєСѓС‰РёРµ СЃС‚СЂР°С‚РµРіРёРё (autocircular):"
    printf "  YouTube TCP: #%s\n" "$current_yt_tcp"
    printf "  YouTube GV:  #%s\n" "$current_yt_gv"
    printf "  RKN:         #%s\n" "$current_rkn"
    printf "  QUIC YouTube: #%s\n" "$(get_current_quic_strategy)"
    print_separator

    # РџРѕРґРјРµРЅСЋ РІС‹Р±РѕСЂР° РєР°С‚РµРіРѕСЂРёРё
    cat <<'SUBMENU'

Р’С‹Р±РµСЂРёС‚Рµ РєР°С‚РµРіРѕСЂРёСЋ РґР»СЏ РїСЂРёРјРµРЅРµРЅРёСЏ СЃС‚СЂР°С‚РµРіРёРё:
[1] YouTube TCP (youtube.com)   -> СЃС‚СЂР°С‚РµРіРёСЏ #2
[2] YouTube GV (googlevideo CDN) -> СЃС‚СЂР°С‚РµРіРёСЏ #3
[3] RKN (Р·Р°Р±Р»РѕРєРёСЂРѕРІР°РЅРЅС‹Рµ СЃР°Р№С‚С‹) -> СЃС‚СЂР°С‚РµРіРёСЏ #1
[4] QUIC (UDP 443)
[B] РќР°Р·Р°Рґ

SUBMENU
    printf "Р’Р°С€ РІС‹Р±РѕСЂ: "
    read_input category_choice

    case "$category_choice" in
        1)
            # YouTube TCP вЂ” С„РёРєСЃРёСЂРѕРІР°РЅРЅР°СЏ СЃС‚СЂР°С‚РµРіРёСЏ #2
            local new_strategy=2
            print_separator
            print_info "РџСЂРёРјРµРЅСЏСЋ autocircular СЃС‚СЂР°С‚РµРіРёСЋ #$new_strategy РґР»СЏ YouTube TCP..."
            apply_category_strategies_v2 "$new_strategy" "$current_yt_gv" "$current_rkn"
            print_separator
            test_category_availability "YouTube TCP" "youtube.com"
            print_separator

            printf "РЎРѕС…СЂР°РЅРёС‚СЊ? [Y/n]: "
            read_input apply_confirm
            case "$apply_confirm" in
                [Nn]|[Nn][Oo])
                    print_info "РћС‚РєР°С‚С‹РІР°СЋ..."
                    apply_category_strategies_v2 "$current_yt_tcp" "$current_yt_gv" "$current_rkn"
                    print_success "РћС‚РєР°С‚ РІС‹РїРѕР»РЅРµРЅ"
                    ;;
                *)
                    save_category_strategies "$new_strategy" "$current_yt_gv" "$current_rkn"
                    print_success "РЎС‚СЂР°С‚РµРіРёСЏ YouTube TCP СЃРѕС…СЂР°РЅРµРЅР°!"
                    ;;
            esac
            return
            ;;
        2)
            # YouTube GV вЂ” С„РёРєСЃРёСЂРѕРІР°РЅРЅР°СЏ СЃС‚СЂР°С‚РµРіРёСЏ #3
            local new_strategy=3
            print_separator
            print_info "РџСЂРёРјРµРЅСЏСЋ autocircular СЃС‚СЂР°С‚РµРіРёСЋ #$new_strategy РґР»СЏ YouTube GV..."
            apply_category_strategies_v2 "$current_yt_tcp" "$new_strategy" "$current_rkn"
            print_separator
            local gv_domain
            gv_domain=$(generate_gv_domain)
            test_category_availability "YouTube GV" "$gv_domain"
            print_separator

            printf "РЎРѕС…СЂР°РЅРёС‚СЊ? [Y/n]: "
            read_input apply_confirm
            case "$apply_confirm" in
                [Nn]|[Nn][Oo])
                    print_info "РћС‚РєР°С‚С‹РІР°СЋ..."
                    apply_category_strategies_v2 "$current_yt_tcp" "$current_yt_gv" "$current_rkn"
                    print_success "РћС‚РєР°С‚ РІС‹РїРѕР»РЅРµРЅ"
                    ;;
                *)
                    save_category_strategies "$current_yt_tcp" "$new_strategy" "$current_rkn"
                    print_success "РЎС‚СЂР°С‚РµРіРёСЏ YouTube GV СЃРѕС…СЂР°РЅРµРЅР°!"
                    ;;
            esac
            return
            ;;
        3)
            # RKN вЂ” С„РёРєСЃРёСЂРѕРІР°РЅРЅР°СЏ СЃС‚СЂР°С‚РµРіРёСЏ #1
            local new_strategy=1
            print_separator
            print_info "РџСЂРёРјРµРЅСЏСЋ autocircular СЃС‚СЂР°С‚РµРіРёСЋ #$new_strategy РґР»СЏ RKN..."
            apply_category_strategies_v2 "$current_yt_tcp" "$current_yt_gv" "$new_strategy"
            print_separator
            test_category_availability_rkn
            print_separator

            printf "РЎРѕС…СЂР°РЅРёС‚СЊ? [Y/n]: "
            read_input apply_confirm
            case "$apply_confirm" in
                [Nn]|[Nn][Oo])
                    print_info "РћС‚РєР°С‚С‹РІР°СЋ..."
                    apply_category_strategies_v2 "$current_yt_tcp" "$current_yt_gv" "$current_rkn"
                    print_success "РћС‚РєР°С‚ РІС‹РїРѕР»РЅРµРЅ"
                    ;;
                *)
                    save_category_strategies "$current_yt_tcp" "$current_yt_gv" "$new_strategy"
                    print_success "РЎС‚СЂР°С‚РµРіРёСЏ RKN СЃРѕС…СЂР°РЅРµРЅР°!"
                    ;;
            esac
            return
            ;;
        4)
            # QUIC (UDP 443)
            menu_quic_settings
            return
            ;;
        [Bb])
            return
            ;;
        *)
            print_error "РќРµРІРµСЂРЅС‹Р№ РІС‹Р±РѕСЂ"
            pause
            return
            ;;
    esac
}

# Р’СЃРїРѕРјРѕРіР°С‚РµР»СЊРЅР°СЏ С„СѓРЅРєС†РёСЏ: РїСЂРѕРІРµСЂРєР° РґРѕСЃС‚СѓРїРЅРѕСЃС‚Рё РєР°С‚РµРіРѕСЂРёРё
test_category_availability() {
    local category_name=$1
    local test_domain=$2

    print_info "РџСЂРѕРІРµСЂРєР° РґРѕСЃС‚СѓРїРЅРѕСЃС‚Рё: $category_name ($test_domain)..."

    # РџРѕРґРѕР¶РґР°С‚СЊ 2 СЃРµРєСѓРЅРґС‹ РґР»СЏ РїСЂРёРјРµРЅРµРЅРёСЏ РїСЂР°РІРёР»
    sleep 2

    # Р—Р°РїСѓСЃС‚РёС‚СЊ С‚РµСЃС‚
    if test_strategy_tls "$test_domain" 5; then
        print_success "[OK] $category_name РґРѕСЃС‚СѓРїРµРЅ! РЎС‚СЂР°С‚РµРіРёСЏ СЂР°Р±РѕС‚Р°РµС‚."
    else
        print_error "[FAIL] $category_name РЅРµРґРѕСЃС‚СѓРїРµРЅ. РџРѕРїСЂРѕР±СѓР№С‚Рµ РґСЂСѓРіСѓСЋ СЃС‚СЂР°С‚РµРіРёСЋ."
        print_info "Р РµРєРѕРјРµРЅРґР°С†РёСЏ: Р·Р°РїСѓСЃС‚РёС‚Рµ Р°РІС‚РѕС‚РµСЃС‚ [3] РґР»СЏ РїРѕРёСЃРєР° СЂР°Р±РѕС‡РµР№ СЃС‚СЂР°С‚РµРіРёРё"
    fi
}

# Р’СЃРїРѕРјРѕРіР°С‚РµР»СЊРЅР°СЏ С„СѓРЅРєС†РёСЏ: РїСЂРѕРІРµСЂРєР° РґРѕСЃС‚СѓРїРЅРѕСЃС‚Рё RKN (3 РґРѕРјРµРЅР°)
test_category_availability_rkn() {
    local test_domains="meduza.io facebook.com rutracker.org"
    local success_count=0

    print_info "РџСЂРѕРІРµСЂРєР° РґРѕСЃС‚СѓРїРЅРѕСЃС‚Рё: RKN (meduza.io, facebook.com, rutracker.org)..."

    sleep 2

    for domain in $test_domains; do
        if test_strategy_tls "$domain" 5; then
            success_count=$((success_count + 1))
        fi
    done

    if [ "$success_count" -ge 2 ]; then
        print_success "[OK] RKN РґРѕСЃС‚СѓРїРµРЅ! РЎС‚СЂР°С‚РµРіРёСЏ СЂР°Р±РѕС‚Р°РµС‚. (${success_count}/3)"
    else
        print_error "[FAIL] RKN РЅРµРґРѕСЃС‚СѓРїРµРЅ. РџРѕРїСЂРѕР±СѓР№С‚Рµ РґСЂСѓРіСѓСЋ СЃС‚СЂР°С‚РµРіРёСЋ. (${success_count}/3)"
        print_info "Р РµРєРѕРјРµРЅРґР°С†РёСЏ: Р·Р°РїСѓСЃС‚РёС‚Рµ Р°РІС‚РѕС‚РµСЃС‚ [3] РґР»СЏ РїРѕРёСЃРєР° СЂР°Р±РѕС‡РµР№ СЃС‚СЂР°С‚РµРіРёРё"
    fi
}

# ==============================================================================
# РџРћР”РњР•РќР®: РђР’РўРћРўР•РЎРў
# ==============================================================================

menu_rutracker_blockcheck() {
    clear_screen
    print_header "[3] RuTracker blockcheck"

    if ! is_zapret2_installed; then
        print_error "zapret2 РЅРµ СѓСЃС‚Р°РЅРѕРІР»РµРЅ"
        pause
        return
    fi

    print_info "Р—Р°РїСѓСЃРє blockcheck РґР»СЏ rutracker.org"
    if confirm "РџСЂРѕРґРѕР»Р¶РёС‚СЊ?" "Y"; then
        run_blockcheck_modern "rutracker.org"
    fi

    pause
}

# ==============================================================================
# РџРћР”РњР•РќР®: РЈРџР РђР’Р›Р•РќРР• РЎР•Р Р’РРЎРћРњ
# ==============================================================================

menu_service_control() {
    clear_screen
    print_header "[4] РЈРїСЂР°РІР»РµРЅРёРµ СЃРµСЂРІРёСЃРѕРј"

    if ! is_zapret2_installed; then
        print_error "zapret2 РЅРµ СѓСЃС‚Р°РЅРѕРІР»РµРЅ"
        pause
        return
    fi

    cat <<'SUBMENU'
[1] Р—Р°РїСѓСЃС‚РёС‚СЊ СЃРµСЂРІРёСЃ
[2] РћСЃС‚Р°РЅРѕРІРёС‚СЊ СЃРµСЂРІРёСЃ
[3] РџРµСЂРµР·Р°РїСѓСЃС‚РёС‚СЊ СЃРµСЂРІРёСЃ
[4] РЎС‚Р°С‚СѓСЃ СЃРµСЂРІРёСЃР°
[B] РќР°Р·Р°Рґ

SUBMENU

    printf "Р’С‹Р±РµСЂРёС‚Рµ РґРµР№СЃС‚РІРёРµ: "
    read_input action

    case "$action" in
        1)
            print_info "Р—Р°РїСѓСЃРє СЃРµСЂРІРёСЃР°..."
            "$INIT_SCRIPT" start
            ;;
        2)
            print_info "РћСЃС‚Р°РЅРѕРІРєР° СЃРµСЂРІРёСЃР°..."
            "$INIT_SCRIPT" stop
            ;;
        3)
            print_info "РџРµСЂРµР·Р°РїСѓСЃРє СЃРµСЂРІРёСЃР°..."
            "$INIT_SCRIPT" restart
            ;;
        4)
            "$INIT_SCRIPT" status
            ;;
        [Bb])
            return
            ;;
        *)
            print_error "РќРµРІРµСЂРЅС‹Р№ РІС‹Р±РѕСЂ"
            ;;
    esac

    pause
}

# ==============================================================================
# РџРћР”РњР•РќР®: РџР РћРЎРњРћРўР  РЎРўР РђРўР•Р“РР
# ==============================================================================

menu_view_strategy() {
    clear_screen
    print_header "[5] РўРµРєСѓС‰РёРµ СЃС‚СЂР°С‚РµРіРёРё"

    if ! is_zapret2_installed; then
        print_error "zapret2 РЅРµ СѓСЃС‚Р°РЅРѕРІР»РµРЅ"
        pause
        return
    fi

    # РџСЂРѕРІРµСЂРёС‚СЊ РЅР°Р»РёС‡РёРµ С„Р°Р№Р»Р° СЃ РєР°С‚РµРіРѕСЂРёСЏРјРё
    if [ -f "$CATEGORY_STRATEGIES_CONF" ]; then
        print_info "РЎС‚СЂР°С‚РµРіРёРё РїРѕ РєР°С‚РµРіРѕСЂРёСЏРј:"
        print_separator

        # РџСЂРѕС‡РёС‚Р°С‚СЊ Рё РїРѕРєР°Р·Р°С‚СЊ СЃС‚СЂР°С‚РµРіРёРё РґР»СЏ РєР°Р¶РґРѕР№ РєР°С‚РµРіРѕСЂРёРё
        while IFS=':' read -r category strategy score; do
            [ -z "$category" ] && continue

            local params
            local type
            params=$(get_strategy "$strategy" 2>/dev/null)
            type=$(get_strategy_type "$strategy" 2>/dev/null)

            printf "\n[%s]\n" "$(echo "$category" | tr '[:lower:]' '[:upper:]')"
            printf "  РЎС‚СЂР°С‚РµРіРёСЏ: #%s (РѕС†РµРЅРєР°: %s/5)\n" "$strategy" "$score"
            printf "  РўРёРї: %s\n" "$type"
        done < "$CATEGORY_STRATEGIES_CONF"

        print_separator
    else
        # РЎС‚Р°СЂС‹Р№ СЂРµР¶РёРј - РѕРґРЅР° СЃС‚СЂР°С‚РµРіРёСЏ
        local current
        current=$(get_current_strategy)

        if [ "$current" = "РЅРµ Р·Р°РґР°РЅР°" ] || [ -z "$current" ]; then
            print_warning "РЎС‚СЂР°С‚РµРіРёСЏ РЅРµ РІС‹Р±СЂР°РЅР°"
            print_info "РСЃРїРѕР»СЊР·СѓРµС‚СЃСЏ СЃС‚СЂР°С‚РµРіРёСЏ РїРѕ СѓРјРѕР»С‡Р°РЅРёСЋ РёР· init СЃРєСЂРёРїС‚Р°"
        else
            print_info "РўРµРєСѓС‰Р°СЏ СЃС‚СЂР°С‚РµРіРёСЏ: #$current"
            print_separator

            local params
            params=$(get_strategy "$current")
            local type
            type=$(get_strategy_type "$current")

            printf "РўРёРї: %s\n\n" "$type"
            printf "РџР°СЂР°РјРµС‚СЂС‹:\n%s\n" "$params"
            print_separator
        fi
    fi

    # РџРѕРєР°Р·Р°С‚СЊ СЃС‚Р°С‚СѓСЃ СЃРµСЂРІРёСЃР°
    printf "\nРЎС‚Р°С‚СѓСЃ СЃРµСЂРІРёСЃР°: %s\n" "$(get_service_status)"

    if is_zapret2_running; then
        printf "\nРџСЂРѕС†РµСЃСЃС‹ nfqws2:\n"
        pgrep -af "nfqws2" 2>/dev/null || print_info "РџСЂРѕС†РµСЃСЃС‹ РЅРµ РЅР°Р№РґРµРЅС‹"
    fi

    pause
}

# ==============================================================================
# РџРћР”РњР•РќР®: РћР‘РќРћР’Р›Р•РќРР• РЎРџРРЎРљРћР’
# ==============================================================================

menu_update_lists() {
    clear_screen
    print_header "[6] РћР±РЅРѕРІР»РµРЅРёРµ СЃРїРёСЃРєРѕРІ РґРѕРјРµРЅРѕРІ"

    if ! is_zapret2_installed; then
        print_error "zapret2 РЅРµ СѓСЃС‚Р°РЅРѕРІР»РµРЅ"
        pause
        return
    fi

    # РџРѕРєР°Р·Р°С‚СЊ С‚РµРєСѓС‰РёРµ СЃРїРёСЃРєРё
    show_domain_lists_stats

    printf "\nРћР±РЅРѕРІРёС‚СЊ СЃРїРёСЃРєРё РёР· zapret4rocket? [Y/n]: "
    read_input answer

    case "$answer" in
        [Nn]|[Nn][Oo])
            print_info "РћС‚РјРµРЅРµРЅРѕ"
            ;;
        *)
            update_domain_lists
            ;;
    esac

    pause
}

# ==============================================================================
# РџРћР”РњР•РќР®: BACKUP/RESTORE
# ==============================================================================

menu_backup_restore() {
    clear_screen
    print_header "[8] Р РµР·РµСЂРІРЅР°СЏ РєРѕРїРёСЏ/Р’РѕСЃСЃС‚Р°РЅРѕРІР»РµРЅРёРµ"

    if ! is_zapret2_installed; then
        print_error "zapret2 РЅРµ СѓСЃС‚Р°РЅРѕРІР»РµРЅ"
        pause
        return
    fi

    cat <<'SUBMENU'
[1] РЎРѕР·РґР°С‚СЊ СЂРµР·РµСЂРІРЅСѓСЋ РєРѕРїРёСЋ
[2] Р’РѕСЃСЃС‚Р°РЅРѕРІРёС‚СЊ РёР· СЂРµР·РµСЂРІРЅРѕР№ РєРѕРїРёРё
[3] РЎР±СЂРѕСЃРёС‚СЊ РєРѕРЅС„РёРіСѓСЂР°С†РёСЋ
[B] РќР°Р·Р°Рґ

SUBMENU

    printf "Р’С‹Р±РµСЂРёС‚Рµ РґРµР№СЃС‚РІРёРµ: "
    read_input action

    case "$action" in
        1)
            backup_config
            ;;
        2)
            restore_config
            ;;
        3)
            reset_config
            ;;
        [Bb])
            return
            ;;
        *)
            print_error "РќРµРІРµСЂРЅС‹Р№ РІС‹Р±РѕСЂ"
            ;;
    esac

    pause
}

# ==============================================================================
# РџРћР”РњР•РќР®: РЈР”РђР›Р•РќРР•
# ==============================================================================

menu_uninstall() {
    clear_screen
    print_header "[9] РЈРґР°Р»РµРЅРёРµ zapret2"

    if ! is_zapret2_installed; then
        print_info "zapret2 РЅРµ СѓСЃС‚Р°РЅРѕРІР»РµРЅ"
        pause
        return
    fi

    uninstall_zapret2

    pause
}

# ==============================================================================
# РџРћР”РњР•РќР®: Р Р•Р–РРњ ALL TCP-443 (Р‘Р•Р— РҐРћРЎРўР›РРЎРўРћР’)
# ==============================================================================

menu_all_tcp443() {
    clear_screen
    print_header "Р РµР¶РёРј ALL TCP-443 (Р±РµР· С…РѕСЃС‚Р»РёСЃС‚РѕРІ)"

    local conf_file="${CONFIG_DIR}/all_tcp443.conf"

    # РџСЂРѕРІРµСЂРёС‚СЊ СЃСѓС‰РµСЃС‚РІРѕРІР°РЅРёРµ РєРѕРЅС„РёРіР°
    if [ ! -f "$conf_file" ]; then
        print_error "Р¤Р°Р№Р» РєРѕРЅС„РёРіСѓСЂР°С†РёРё РЅРµ РЅР°Р№РґРµРЅ: $conf_file"
        print_info "Р—Р°РїСѓСЃС‚РёС‚Рµ СѓСЃС‚Р°РЅРѕРІРєСѓ СЃРЅР°С‡Р°Р»Р°"
        pause
        return 1
    fi

    # РџСЂРѕС‡РёС‚Р°С‚СЊ С‚РµРєСѓС‰СѓСЋ РєРѕРЅС„РёРіСѓСЂР°С†РёСЋ
    . "$conf_file"
    local current_enabled=$ENABLED
    local current_strategy=$STRATEGY

    print_separator

    print_info "РўРµРєСѓС‰Р°СЏ РєРѕРЅС„РёРіСѓСЂР°С†РёСЏ:"
    printf "  РЎС‚Р°С‚СѓСЃ: %s\n" "$([ "$current_enabled" = "1" ] && echo 'Р’РєР»СЋС‡РµРЅ' || echo 'Р’С‹РєР»СЋС‡РµРЅ')"
    printf "  РЎС‚СЂР°С‚РµРіРёСЏ: #%s\n" "$current_strategy"

    print_separator

    cat <<'SUBMENU'

Р’РќРРњРђРќРР•: Р­С‚РѕС‚ СЂРµР¶РёРј РїСЂРёРјРµРЅСЏРµС‚ СЃС‚СЂР°С‚РµРіРёСЋ РєРѕ Р’РЎР•РњРЈ С‚СЂР°С„РёРєСѓ HTTPS (TCP-443)
Р±РµР· С„РёР»СЊС‚СЂР°С†РёРё РїРѕ РґРѕРјРµРЅР°Рј РёР· С…РѕСЃС‚Р»РёСЃС‚РѕРІ!

РСЃРїРѕР»СЊР·РѕРІР°РЅРёРµ:
  - Р”Р»СЏ РѕР±С…РѕРґР° Р±Р»РѕРєРёСЂРѕРІРѕРє Р’РЎР•РҐ СЃР°Р№С‚РѕРІ РѕРґРЅРѕР№ СЃС‚СЂР°С‚РµРіРёРµР№
  - РљРѕРіРґР° С…РѕСЃС‚Р»РёСЃС‚С‹ РЅРµ РїРѕРјРѕРіР°СЋС‚
  - Р”Р»СЏ С‚РµСЃС‚РёСЂРѕРІР°РЅРёСЏ СѓРЅРёРІРµСЂСЃР°Р»СЊРЅС‹С… СЃС‚СЂР°С‚РµРіРёР№

РќРµРґРѕСЃС‚Р°С‚РєРё:
  - РњРѕР¶РµС‚ Р·Р°РјРµРґР»РёС‚СЊ Р’РЎР• HTTPS СЃРѕРµРґРёРЅРµРЅРёСЏ
  - РЈРІРµР»РёС‡РёРІР°РµС‚ РЅР°РіСЂСѓР·РєСѓ РЅР° СЂРѕСѓС‚РµСЂ
  - РњРѕР¶РµС‚ РІС‹Р·РІР°С‚СЊ РїСЂРѕР±Р»РµРјС‹ СЃ РЅРµРєРѕС‚РѕСЂС‹РјРё СЃР°Р№С‚Р°РјРё

[1] Р’РєР»СЋС‡РёС‚СЊ СЂРµР¶РёРј ALL TCP-443
[2] Р’С‹РєР»СЋС‡РёС‚СЊ СЂРµР¶РёРј ALL TCP-443
[3] РР·РјРµРЅРёС‚СЊ СЃС‚СЂР°С‚РµРіРёСЋ
[B] РќР°Р·Р°Рґ

SUBMENU

    printf "Р’С‹Р±РµСЂРёС‚Рµ РѕРїС†РёСЋ [1-3,B]: "
    read_input sub_choice

    case "$sub_choice" in
        1)
            # Р’РєР»СЋС‡РёС‚СЊ СЂРµР¶РёРј
            print_info "Р’С‹Р±РѕСЂ СЃС‚СЂР°С‚РµРіРёРё РґР»СЏ СЂРµР¶РёРјР° ALL TCP-443..."
            print_separator

            # РџРѕРєР°Р·Р°С‚СЊ С‚РѕРї СЃС‚СЂР°С‚РµРіРёР№
            print_info "Р РµРєРѕРјРµРЅРґСѓРµРјС‹Рµ СЃС‚СЂР°С‚РµРіРёРё РґР»СЏ СЂРµР¶РёРјР° ALL TCP-443:"
            printf "  #1  - multidisorder (Р±Р°Р·РѕРІР°СЏ)\n"
            printf "  #7  - multidisorder:pos=1\n"
            printf "  #13 - multidisorder:pos=sniext+1\n"
            printf "  #67 - fakedsplit СЃ ip_autottl (РїСЂРѕРґРІРёРЅСѓС‚Р°СЏ)\n"
            print_separator

            printf "Р’РІРµРґРёС‚Рµ РЅРѕРјРµСЂ СЃС‚СЂР°С‚РµРіРёРё [1-199] РёР»Рё Enter РґР»СЏ #1: "
            read_input strategy_num

            # Р’Р°Р»РёРґР°С†РёСЏ
            if [ -z "$strategy_num" ]; then
                strategy_num=1
            fi

            if ! echo "$strategy_num" | grep -qE '^[0-9]+$' || [ "$strategy_num" -lt 1 ] || [ "$strategy_num" -gt 199 ]; then
                print_error "РќРµРІРµСЂРЅС‹Р№ РЅРѕРјРµСЂ СЃС‚СЂР°С‚РµРіРёРё: $strategy_num"
                pause
                return 1
            fi

            # РћР±РЅРѕРІРёС‚СЊ РєРѕРЅС„РёРі
            sed -i "s/^ENABLED=.*/ENABLED=1/" "$conf_file"
            sed -i "s/^STRATEGY=.*/STRATEGY=$strategy_num/" "$conf_file"

            print_success "Р РµР¶РёРј ALL TCP-443 РІРєР»СЋС‡РµРЅ СЃ СЃС‚СЂР°С‚РµРіРёРµР№ #$strategy_num"
            print_separator

            # РџРµСЂРµР·Р°РїСѓСЃРє СЃРµСЂРІРёСЃР°
            if is_zapret2_running; then
                print_info "РџРµСЂРµР·Р°РїСѓСЃРє СЃРµСЂРІРёСЃР° РґР»СЏ РїСЂРёРјРµРЅРµРЅРёСЏ РёР·РјРµРЅРµРЅРёР№..."
                "$INIT_SCRIPT" restart
                print_success "РЎРµСЂРІРёСЃ РїРµСЂРµР·Р°РїСѓС‰РµРЅ"
            else
                print_warning "РЎРµСЂРІРёСЃ РЅРµ Р·Р°РїСѓС‰РµРЅ. Р—Р°РїСѓСЃС‚РёС‚Рµ С‡РµСЂРµР· [4] РЈРїСЂР°РІР»РµРЅРёРµ СЃРµСЂРІРёСЃРѕРј"
            fi

            pause
            ;;

        2)
            # Р’С‹РєР»СЋС‡РёС‚СЊ СЂРµР¶РёРј
            if [ "$current_enabled" != "1" ]; then
                print_info "Р РµР¶РёРј ALL TCP-443 СѓР¶Рµ РІС‹РєР»СЋС‡РµРЅ"
                pause
                return 0
            fi

            sed -i "s/^ENABLED=.*/ENABLED=0/" "$conf_file"
            print_success "Р РµР¶РёРј ALL TCP-443 РІС‹РєР»СЋС‡РµРЅ"
            print_separator

            # РџРµСЂРµР·Р°РїСѓСЃРє СЃРµСЂРІРёСЃР°
            if is_zapret2_running; then
                print_info "РџРµСЂРµР·Р°РїСѓСЃРє СЃРµСЂРІРёСЃР° РґР»СЏ РїСЂРёРјРµРЅРµРЅРёСЏ РёР·РјРµРЅРµРЅРёР№..."
                "$INIT_SCRIPT" restart
                print_success "РЎРµСЂРІРёСЃ РїРµСЂРµР·Р°РїСѓС‰РµРЅ"
            fi

            pause
            ;;

        3)
            # РР·РјРµРЅРёС‚СЊ СЃС‚СЂР°С‚РµРіРёСЋ
            if [ "$current_enabled" != "1" ]; then
                print_warning "Р РµР¶РёРј ALL TCP-443 РІС‹РєР»СЋС‡РµРЅ"
                print_info "РЎРЅР°С‡Р°Р»Р° РІРєР»СЋС‡РёС‚Рµ СЂРµР¶РёРј С‡РµСЂРµР· [1]"
                pause
                return 0
            fi

            printf "РўРµРєСѓС‰Р°СЏ СЃС‚СЂР°С‚РµРіРёСЏ: #%s\n" "$current_strategy"
            print_separator
            printf "Р’РІРµРґРёС‚Рµ РЅРѕРІС‹Р№ РЅРѕРјРµСЂ СЃС‚СЂР°С‚РµРіРёРё [1-199]: "
            read_input new_strategy

            # Р’Р°Р»РёРґР°С†РёСЏ
            if ! echo "$new_strategy" | grep -qE '^[0-9]+$' || [ "$new_strategy" -lt 1 ] || [ "$new_strategy" -gt 199 ]; then
                print_error "РќРµРІРµСЂРЅС‹Р№ РЅРѕРјРµСЂ СЃС‚СЂР°С‚РµРіРёРё: $new_strategy"
                pause
                return 1
            fi

            sed -i "s/^STRATEGY=.*/STRATEGY=$new_strategy/" "$conf_file"
            print_success "РЎС‚СЂР°С‚РµРіРёСЏ РёР·РјРµРЅРµРЅР° РЅР° #$new_strategy"
            print_separator

            # РџРµСЂРµР·Р°РїСѓСЃРє СЃРµСЂРІРёСЃР°
            if is_zapret2_running; then
                print_info "РџРµСЂРµР·Р°РїСѓСЃРє СЃРµСЂРІРёСЃР° РґР»СЏ РїСЂРёРјРµРЅРµРЅРёСЏ РёР·РјРµРЅРµРЅРёР№..."
                "$INIT_SCRIPT" restart
                print_success "РЎРµСЂРІРёСЃ РїРµСЂРµР·Р°РїСѓС‰РµРЅ"
            fi

            pause
            ;;

        b|B)
            return 0
            ;;

        *)
            print_error "РќРµРІРµСЂРЅС‹Р№ РІС‹Р±РѕСЂ: $sub_choice"
            pause
            ;;
    esac
}

# ==============================================================================
# РџРћР”РњР•РќР®: WHITELIST (РРЎРљР›Р®Р§Р•РќРРЇ)
# ==============================================================================

menu_whitelist() {
    clear_screen
    print_header "Whitelist - РСЃРєР»СЋС‡РµРЅРёСЏ РёР· РѕР±СЂР°Р±РѕС‚РєРё"

    local whitelist_file="${LISTS_DIR}/whitelist.txt"

    # РџСЂРѕРІРµСЂРёС‚СЊ СЃСѓС‰РµСЃС‚РІРѕРІР°РЅРёРµ С„Р°Р№Р»Р°
    if [ ! -f "$whitelist_file" ]; then
        print_warning "Р¤Р°Р№Р» whitelist РЅРµ РЅР°Р№РґРµРЅ: $whitelist_file"
        print_info "РЎРѕР·РґР°СЋ С„Р°Р№Р»..."

        # РЎРѕР·РґР°С‚СЊ РґРёСЂРµРєС‚РѕСЂРёСЋ РµСЃР»Рё РЅРµ СЃСѓС‰РµСЃС‚РІСѓРµС‚
        if ! mkdir -p "$LISTS_DIR" 2>/dev/null; then
            print_error "РќРµ СѓРґР°Р»РѕСЃСЊ СЃРѕР·РґР°С‚СЊ РґРёСЂРµРєС‚РѕСЂРёСЋ: $LISTS_DIR"
            print_info "РџСЂРѕРІРµСЂСЊС‚Рµ РїСЂР°РІР° РґРѕСЃС‚СѓРїР°"
            pause
            return 1
        fi

        # РЎРѕР·РґР°С‚СЊ Р±Р°Р·РѕРІС‹Р№ whitelist
        cat > "$whitelist_file" <<'EOF'
# Whitelist - РґРѕРјРµРЅС‹ РёСЃРєР»СЋС‡РµРЅРЅС‹Рµ РёР· РѕР±СЂР°Р±РѕС‚РєРё zapret2
# РљСЂРёС‚РёС‡РЅС‹Рµ РіРѕСЃСѓРґР°СЂСЃС‚РІРµРЅРЅС‹Рµ СЃРµСЂРІРёСЃС‹ Р Р¤

# Р“РѕСЃСѓСЃР»СѓРіРё (Р•РЎРРђ)
gosuslugi.ru
esia.gosuslugi.ru
lk.gosuslugi.ru

# РќР°Р»РѕРіРѕРІР°СЏ СЃР»СѓР¶Р±Р°
nalog.gov.ru
lkfl2.nalog.ru

# РџРµРЅСЃРёРѕРЅРЅС‹Р№ С„РѕРЅРґ
pfr.gov.ru
es.pfr.gov.ru

# Р”СЂСѓРіРёРµ РІР°Р¶РЅС‹Рµ РіРѕСЃСЃРµСЂРІРёСЃС‹
mos.ru
pgu.mos.ru
EOF

        if [ ! -f "$whitelist_file" ]; then
            print_error "РќРµ СѓРґР°Р»РѕСЃСЊ СЃРѕР·РґР°С‚СЊ С„Р°Р№Р» whitelist"
            print_info "РџСЂРѕРІРµСЂСЊС‚Рµ РїСЂР°РІР° РґРѕСЃС‚СѓРїР°"
            pause
            return 1
        fi

        print_success "Р¤Р°Р№Р» whitelist СЃРѕР·РґР°РЅ: $whitelist_file"
    fi

    print_separator

    cat <<'INFO'

Whitelist СЃРѕРґРµСЂР¶РёС‚ РґРѕРјРµРЅС‹, РєРѕС‚РѕСЂС‹Рµ РРЎРљР›Р®Р§Р•РќР« РёР· РѕР±СЂР°Р±РѕС‚РєРё zapret2.
Р­С‚Рѕ РїРѕР»РµР·РЅРѕ РґР»СЏ РєСЂРёС‚РёС‡РЅС‹С… СЃРµСЂРІРёСЃРѕРІ, РєРѕС‚РѕСЂС‹Рµ РјРѕРіСѓС‚ СЃР»РѕРјР°С‚СЊСЃСЏ
РїСЂРё РїСЂРёРјРµРЅРµРЅРёРё DPI-РѕР±С…РѕРґР° (РіРѕСЃСѓСЃР»СѓРіРё, Р±Р°РЅРєРё, Рё С‚.Рґ.)

РџРѕ СѓРјРѕР»С‡Р°РЅРёСЋ РІ whitelist РІРєР»СЋС‡РµРЅС‹:
  - gosuslugi.ru (Р“РѕСЃСѓСЃР»СѓРіРё, Р•РЎРРђ)
  - nalog.gov.ru (РќР°Р»РѕРіРѕРІР°СЏ СЃР»СѓР¶Р±Р°)
  - pfr.gov.ru (РџРµРЅСЃРёРѕРЅРЅС‹Р№ С„РѕРЅРґ)
  - mos.ru (РњРѕСЃРєРІР°)

[1] РџСЂРѕСЃРјРѕС‚СЂРµС‚СЊ whitelist
[2] Р РµРґР°РєС‚РёСЂРѕРІР°С‚СЊ whitelist (vi)
[3] Р”РѕР±Р°РІРёС‚СЊ РґРѕРјРµРЅ
[4] РЈРґР°Р»РёС‚СЊ РґРѕРјРµРЅ
[B] РќР°Р·Р°Рґ

INFO

    printf "Р’С‹Р±РµСЂРёС‚Рµ РѕРїС†РёСЋ [1-4,B]: "
    read_input sub_choice

    case "$sub_choice" in
        1)
            # РџСЂРѕСЃРјРѕС‚СЂ
            clear_screen
            print_header "РўРµРєСѓС‰РёР№ whitelist"
            print_separator
            cat "$whitelist_file"
            print_separator
            pause
            ;;

        2)
            # Р РµРґР°РєС‚РёСЂРѕРІР°РЅРёРµ РІ vi
            print_info "РћС‚РєСЂС‹С‚РёРµ whitelist РІ СЂРµРґР°РєС‚РѕСЂРµ..."
            vi "$whitelist_file"

            # РџРµСЂРµР·Р°РїСѓСЃРє СЃРµСЂРІРёСЃР°
            if is_zapret2_running; then
                print_info "РџРµСЂРµР·Р°РїСѓСЃРє СЃРµСЂРІРёСЃР° РґР»СЏ РїСЂРёРјРµРЅРµРЅРёСЏ РёР·РјРµРЅРµРЅРёР№..."
                "$INIT_SCRIPT" restart
                print_success "РЎРµСЂРІРёСЃ РїРµСЂРµР·Р°РїСѓС‰РµРЅ"
            fi
            pause
            ;;

        3)
            # Р”РѕР±Р°РІРёС‚СЊ РґРѕРјРµРЅ
            printf "Р’РІРµРґРёС‚Рµ РґРѕРјРµРЅ РґР»СЏ РґРѕР±Р°РІР»РµРЅРёСЏ (РЅР°РїСЂРёРјРµСЂ: example.com): "
            read_input new_domain

            # РџСЂРѕСЃС‚Р°СЏ РІР°Р»РёРґР°С†РёСЏ РґРѕРјРµРЅР°
            if ! echo "$new_domain" | grep -qE '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
                print_error "РќРµРІРµСЂРЅС‹Р№ С„РѕСЂРјР°С‚ РґРѕРјРµРЅР°: $new_domain"
                pause
                return 1
            fi

            # РџСЂРѕРІРµСЂРёС‚СЊ РґСѓР±Р»РёРєР°С‚С‹
            if grep -qx "$new_domain" "$whitelist_file"; then
                print_warning "Р”РѕРјРµРЅ $new_domain СѓР¶Рµ РІ whitelist"
                pause
                return 0
            fi

            # Р”РѕР±Р°РІРёС‚СЊ РґРѕРјРµРЅ
            echo "$new_domain" >> "$whitelist_file"
            print_success "Р”РѕРјРµРЅ $new_domain РґРѕР±Р°РІР»РµРЅ РІ whitelist"
            print_separator

            # РџРµСЂРµР·Р°РїСѓСЃРє СЃРµСЂРІРёСЃР°
            if is_zapret2_running; then
                print_info "РџРµСЂРµР·Р°РїСѓСЃРє СЃРµСЂРІРёСЃР° РґР»СЏ РїСЂРёРјРµРЅРµРЅРёСЏ РёР·РјРµРЅРµРЅРёР№..."
                "$INIT_SCRIPT" restart
                print_success "РЎРµСЂРІРёСЃ РїРµСЂРµР·Р°РїСѓС‰РµРЅ"
            fi
            pause
            ;;

        4)
            # РЈРґР°Р»РёС‚СЊ РґРѕРјРµРЅ
            printf "Р’РІРµРґРёС‚Рµ РґРѕРјРµРЅ РґР»СЏ СѓРґР°Р»РµРЅРёСЏ: "
            read_input del_domain

            # РџСЂРѕРІРµСЂРёС‚СЊ РЅР°Р»РёС‡РёРµ
            if ! grep -qx "$del_domain" "$whitelist_file"; then
                print_error "Р”РѕРјРµРЅ $del_domain РЅРµ РЅР°Р№РґРµРЅ РІ whitelist"
                pause
                return 1
            fi

            # РЈРґР°Р»РёС‚СЊ РґРѕРјРµРЅ
            sed -i "/^${del_domain}$/d" "$whitelist_file"
            print_success "Р”РѕРјРµРЅ $del_domain СѓРґР°Р»РµРЅ РёР· whitelist"
            print_separator

            # РџРµСЂРµР·Р°РїСѓСЃРє СЃРµСЂРІРёСЃР°
            if is_zapret2_running; then
                print_info "РџРµСЂРµР·Р°РїСѓСЃРє СЃРµСЂРІРёСЃР° РґР»СЏ РїСЂРёРјРµРЅРµРЅРёСЏ РёР·РјРµРЅРµРЅРёР№..."
                "$INIT_SCRIPT" restart
                print_success "РЎРµСЂРІРёСЃ РїРµСЂРµР·Р°РїСѓС‰РµРЅ"
            fi
            pause
            ;;

        b|B)
            return 0
            ;;

        *)
            print_error "РќРµРІРµСЂРЅС‹Р№ РІС‹Р±РѕСЂ: $sub_choice"
            pause
            ;;
    esac
}

# ==============================================================================
# РџРћР”РњР•РќР®: РЈРџР РђР’Р›Р•РќРР• QUIC
# ==============================================================================

menu_quic_settings() {
    clear_screen
    print_header "РќР°СЃС‚СЂРѕР№РєРё QUIC"

    printf "\nРўРµРєСѓС‰РёРµ РЅР°СЃС‚СЂРѕР№РєРё:\n"
    printf "  YouTube QUIC: СЃС‚СЂР°С‚РµРіРёСЏ #%s\n" "$(get_current_quic_strategy)"

    cat <<'MENU'

[1] YouTube QUIC - РІС‹Р±СЂР°С‚СЊ СЃС‚СЂР°С‚РµРіРёСЋ
[B] РќР°Р·Р°Рґ

MENU

    printf "Р’С‹Р±РµСЂРёС‚Рµ РѕРїС†РёСЋ: "
    read_input choice

    case "$choice" in
        1)
            menu_select_quic_strategy_youtube
            ;;
        b|B)
            return 0
            ;;
        *)
            print_error "РќРµРІРµСЂРЅС‹Р№ РІС‹Р±РѕСЂ: $choice"
            pause
            ;;
    esac
}

# Р’С‹Р±РѕСЂ QUIC СЃС‚СЂР°С‚РµРіРёРё РґР»СЏ YouTube
menu_select_quic_strategy_youtube() {
    clear_screen
    print_header "YouTube QUIC - РІС‹Р±РѕСЂ СЃС‚СЂР°С‚РµРіРёРё"

    local total_quic
    total_quic=$(get_quic_strategies_count)

    if [ "$total_quic" -eq 0 ]; then
        print_error "QUIC СЃС‚СЂР°С‚РµРіРёРё РЅРµ РЅР°Р№РґРµРЅС‹"
        pause
        return 1
    fi

    local current_quic
    current_quic=$(get_current_quic_strategy)

    printf "\nР’СЃРµРіРѕ QUIC СЃС‚СЂР°С‚РµРіРёР№: %s\n" "$total_quic"
    printf "РўРµРєСѓС‰Р°СЏ СЃС‚СЂР°С‚РµРіРёСЏ: #%s\n\n" "$current_quic"

    printf "Р’РІРµРґРёС‚Рµ РЅРѕРјРµСЂ СЃС‚СЂР°С‚РµРіРёРё [1-%s] РёР»Рё Enter РґР»СЏ РѕС‚РјРµРЅС‹: " "$total_quic"
    read_input new_strategy

    if [ -z "$new_strategy" ]; then
        print_info "РћС‚РјРµРЅРµРЅРѕ"
        pause
        return 0
    fi

    if ! echo "$new_strategy" | grep -qE '^[0-9]+$'; then
        print_error "РќРµРІРµСЂРЅС‹Р№ С„РѕСЂРјР°С‚"
        pause
        return 1
    fi

    if [ "$new_strategy" -lt 1 ] || [ "$new_strategy" -gt "$total_quic" ]; then
        print_error "РќРѕРјРµСЂ РІРЅРµ РґРёР°РїР°Р·РѕРЅР°"
        pause
        return 1
    fi

    if ! quic_strategy_exists "$new_strategy"; then
        print_error "QUIC СЃС‚СЂР°С‚РµРіРёСЏ #$new_strategy РЅРµ РЅР°Р№РґРµРЅР°"
        pause
        return 1
    fi

    set_current_quic_strategy "$new_strategy"

    # РџРѕР»СѓС‡РёС‚СЊ С‚РµРєСѓС‰РёРµ СЃС‚СЂР°С‚РµРіРёРё
    local config_file="${CONFIG_DIR}/category_strategies.conf"
    local current_yt_tcp=1
    local current_yt_gv=1
    local current_rkn=1

    if [ -f "$config_file" ]; then
        current_yt_tcp=$(grep "^youtube_tcp:" "$config_file" 2>/dev/null | cut -d':' -f2)
        current_yt_gv=$(grep "^youtube_gv:" "$config_file" 2>/dev/null | cut -d':' -f2)
        current_rkn=$(grep "^rkn:" "$config_file" 2>/dev/null | cut -d':' -f2)
        [ -z "$current_yt_tcp" ] && current_yt_tcp=1
        [ -z "$current_yt_gv" ] && current_yt_gv=1
        [ -z "$current_rkn" ] && current_rkn=1
    fi

    apply_category_strategies_v2 "$current_yt_tcp" "$current_yt_gv" "$current_rkn"
    print_success "YouTube QUIC СЃС‚СЂР°С‚РµРіРёСЏ #$new_strategy РїСЂРёРјРµРЅРµРЅР°"
    pause
}

# ==============================================================================
# РџРћР”РњР•РќР®: Р­РљРЎРџР•Р РРњР•РќРўРђР›Р¬РќР«Р• РќРђРЎРўР РћР™РљР
# ==============================================================================

menu_experimental_settings() {
    clear_screen
    print_header "Р­РєСЃРїРµСЂРёРјРµРЅС‚Р°Р»СЊРЅС‹Рµ С„СѓРЅРєС†РёРё"

    local config_file="/opt/zapret2/config"
    local current_wssize="0"
    if [ -f "$config_file" ]; then
        # Р§С‚РµРЅРёРµ С‚РµРєСѓС‰РµРіРѕ СЃРѕСЃС‚РѕСЏРЅРёСЏ РёР· РєРѕРЅС„РёРіР°
        current_wssize=$(grep -E "^ENABLE_WSSIZE=" "$config_file" | cut -d'=' -f2 | tr -d '"')
        [ -z "$current_wssize" ] && current_wssize="0"
    fi

    printf "\nРўРµРєСѓС‰РёРµ РЅР°СЃС‚СЂРѕР№РєРё:\n"
    if [ "$current_wssize" = "1" ]; then
        printf "  TCP Window Size Spoofing (--wssize 1:6): [Р’РљР›Р®Р§Р•РќРћ]\n"
    else
        printf "  TCP Window Size Spoofing (--wssize 1:6): [РћРўРљР›Р®Р§Р•РќРћ]\n"
    fi

    cat <<'MENU'

[1] Р’РєР»СЋС‡РёС‚СЊ/РћС‚РєР»СЋС‡РёС‚СЊ TCP Window Size Spoofing
[B] РќР°Р·Р°Рґ

MENU

    printf "Р’С‹Р±РµСЂРёС‚Рµ РѕРїС†РёСЋ: "
    read_input choice

    case "$choice" in
        1)
            local new_val="1"
            [ "$current_wssize" = "1" ] && new_val="0"
            
            # РЎРѕС…СЂР°РЅСЏРµРј РѕСЃС‚Р°Р»СЊРЅС‹Рµ РЅР°СЃС‚СЂРѕР№РєРё С‡РµСЂРµР· export
            [ -f "$config_file" ] && . "$config_file"
            export ENABLE_WSSIZE="$new_val"
            
            print_info "Р РµРіРµРЅРµСЂР°С†РёСЏ РєРѕРЅС„РёРіСѓСЂР°С†РёРё nfqws2..."
            if command -v create_official_config >/dev/null; then
                create_official_config "$config_file"
            fi
            
            if is_zapret2_running; then
                "$INIT_SCRIPT" restart
                print_success "РЎРµСЂРІРёСЃ РїРµСЂРµР·Р°РїСѓС‰РµРЅ СЃ РЅРѕРІС‹РјРё РїР°СЂР°РјРµС‚СЂР°РјРё"
            else
                print_success "РќР°СЃС‚СЂРѕР№РєРё СЃРѕС…СЂР°РЅРµРЅС‹"
            fi
            pause
            ;;
        b|B)
            return 0
            ;;
        *)
            print_error "РќРµРІРµСЂРЅС‹Р№ РІС‹Р±РѕСЂ: $choice"
            pause
            ;;
    esac
}

# ==============================================================================
# Р­РљРЎРџРћР Рў Р¤РЈРќРљР¦РР™
# ==============================================================================

# Р’СЃРµ С„СѓРЅРєС†РёРё РґРѕСЃС‚СѓРїРЅС‹ РїРѕСЃР»Рµ source СЌС‚РѕРіРѕ С„Р°Р№Р»Р°

