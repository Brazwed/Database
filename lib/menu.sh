# lib/menu.sh - Menus interativos

SEP='━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'

select_installed_db() {
    local installed_raw names=()
    installed_raw=$(get_installed_list)
    [ -z "$(echo "$installed_raw" | tr -d '[:space:]')" ] && { echo ""; return 1; }

    local idx=1
    while IFS='|' read -r name display _; do
        [ -z "$name" ] && continue
        echo "  [$idx] $display" >&2
        names+=("$name")
        idx=$((idx + 1))
    done <<< "$installed_raw"

    echo "  [0] Voltar" >&2
    read -rp "  Escolha: " ch

    [ "$ch" = "0" ] && return 1
    [ -z "${names[$((ch - 1))]:-}" ] && { echo ""; return 1; }
    echo "${names[$((ch - 1))]}"
}

# ─── SUBMENU: INSTALAR ──────────────────────────────────────
submenu_install() {
    echo ""
    echo -e "  ${BD}${C}Instalar banco${NC}"
    echo ""

    local db_names=() idx=1

    while IFS='|' read -r cat name display port _; do
        [ -z "$name" ] && continue
        local marker=""
        db_exists "$name" && marker=" ${G}(já instalado)${NC}"
        echo -e "    [$idx] $display (:$port)$marker"
        db_names+=("$name")
        idx=$((idx + 1))
    done <<< "$DATABASES"

    echo ""
    echo "    [0] Voltar"
    echo ""
    read -rp "  Escolha: " ch
    [ "$ch" = "0" ] && return
    local n=${db_names[$((ch - 1))]:-}
    [ -z "$n" ] && return
    install_db "$n"
}

# ─── SUBMENU: GERENCIAR ─────────────────────────────────────
submenu_manage() {
    echo ""
    echo -e "  ${BD}${C}Gerenciar banco${NC}"

    local db
    db=$(select_installed_db) || return
    [ -z "$db" ] && return

    echo ""
    echo "    [1] Update        atualizar código"
    echo "    [2] Down          parar container"
    echo "    [3] Up            iniciar container"
    echo "    [4] Logs          acompanhar logs"
    echo "    [5] Remove        remover completamente"
    echo "    [0] Voltar"
    echo ""
    read -rp "  Escolha: " ch

    case "$ch" in
        1) update_db "$db" ;;
        2) stop_db "$db" ;;
        3) start_db "$db" ;;
        4) logs_db "$db" ;;
        5) remove_db "$db" ;;
    esac
}

# ─── SUBMENU: CONECTAR ──────────────────────────────────────
submenu_connect() {
    local installed_raw running_names=()
    installed_raw=$(get_installed_list)

    while IFS='|' read -r name display port status dir; do
        [ -z "$name" ] && continue
        [ "$status" = "running" ] && running_names+=("$name|$display|$port")
    done <<< "$installed_raw"

    if [ ${#running_names[@]} -eq 0 ]; then
        warn "Nenhum banco rodando"
        return 1
    fi

    echo ""
    echo -e "  ${BD}${C}Conectar${NC}"
    echo ""

    local idx=1
    for item in "${running_names[@]}"; do
        local name display port
        IFS='|' read -r name display port <<< "$item"
        echo "  [$idx] $display (:$port)"
        idx=$((idx + 1))
    done

    echo "  [0] Voltar"
    read -rp "  Escolha: " ch
    [ "$ch" = "0" ] && return

    local sel=${running_names[$((ch - 1))]:-}
    [ -z "$sel" ] && return

    local n
    n=$(echo "$sel" | cut -d'|' -f1)
    info "Conectando ao $(parse_db "$n" 2)..."
    shell_db "$n"
}

# ─── MENU PRINCIPAL ─────────────────────────────────────────
show_main_menu() {
    local installed_raw has_installed=false
    installed_raw=$(get_installed_list)
    [ -n "$(echo "$installed_raw" | tr -d '[:space:]')" ] && has_installed=true

    clear
    echo ""
    echo -e "  ${BD}${C}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${BD}${C}║                    Database Toolkit v1.0                     ║${NC}"
    echo -e "  ${BD}${C}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "  ${BD}Sistema${NC}"
    if has_docker; then
        local dver
        dver=$(docker --version 2>/dev/null | sed -n 's/.*\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p' | head -1)
        echo -e "    Docker:    ${G}● instalado${NC} (v${dver})"
    else
        echo -e "    Docker:    ${R}● não instalado${NC}"
    fi
    echo ""

    echo -e "  ${BD}${SEP}${NC}"
    echo ""

    # Separar por categoria
    local persistent_items=() memory_items=()
    while IFS='|' read -r cat name display port _; do
        [ -z "$name" ] && continue
        local st_info="${name}|${display}|${port}"
        if echo "$installed_raw" | grep -q "^${name}|"; then
            local st
            st=$(echo "$installed_raw" | grep "^${name}|" | cut -d'|' -f4)
            st_info="${st_info}|${st}"
        else
            st_info="${st_info}|not_installed"
        fi
        case "$cat" in
            persistent) persistent_items+=("$st_info") ;;
            memory) memory_items+=("$st_info") ;;
        esac
    done <<< "$DATABASES"

    echo -e "  📦 ${BD}Bancos Persistentes (disco)${NC}"
    for item in "${persistent_items[@]}"; do
        local name display port st
        IFS='|' read -r name display port st <<< "$item"
        local color="${Y}" tag="não instalado"
        case "$st" in
            running) color="${G}"; tag="rodando" ;;
            stopped) color="${R}"; tag="parado" ;;
        esac
        echo -e "    ${display}   :${port}   ${color}● ${tag}${NC}"
    done
    echo ""

    echo -e "  ⚡ ${BD}Cache em Memória (RAM)${NC}"
    for item in "${memory_items[@]}"; do
        local name display port st
        IFS='|' read -r name display port st <<< "$item"
        local color="${Y}" tag="não instalado"
        case "$st" in
            running) color="${G}"; tag="rodando" ;;
            stopped) color="${R}"; tag="parado" ;;
        esac
        echo -e "    ${display}   :${port}   ${color}● ${tag}${NC}"
    done
    echo ""

    echo -e "  ${BD}${SEP}${NC}"
    echo ""

    echo -e "  📋 ${BD}Comandos${NC}"
    echo ""
    echo -e "    [1] Instalar        preparar ambiente ou banco(s)"
    echo -e "    [2] Gerenciar       atualizar, parar, status, remover"
    echo -e "    [3] Backups         criar, listar, restaurar"
    echo -e "    [4] Conectar        psql, mysql, redis-cli, mongosh"
    echo -e "    [5] Status          ver status de todos os bancos"
    echo -e "    [0] Sair"
    echo ""
    read -rp "  Escolha: " choice

    case "$choice" in
        1) submenu_install ;;
        2) submenu_manage ;;
        3)
            echo ""
            echo -e "  ${BD}${C}Backups${NC}"
            echo ""
            echo "    [1] Criar backup completo"
            echo "    [2] Criar backup de um banco"
            echo "    [3] Listar backups"
            echo "    [4] Restaurar backup"
            echo "    [0] Voltar"
            echo ""
            read -rp "  Escolha: " bk_ch
            case "$bk_ch" in
                1)
                    create_backup "vps" "manual"
                    while IFS='|' read -r _ bn _; do
                        [ -n "$bn" ] && db_exists "$bn" && create_backup "$bn" "manual"
                    done <<< "$DATABASES"
                    ;;
                2)
                    local db
                    db=$(select_installed_db)
                    [ -n "$db" ] && create_backup "$db" "manual"
                    ;;
                3) list_backups "all" ;;
                4)
                    local db
                    db=$(select_installed_db)
                    [ -n "$db" ] && restore_backup "$db"
                    ;;
            esac
            pause
            ;;
        4) submenu_connect ;;
        5)
            while IFS='|' read -r _ name _; do
                [ -n "$name" ] && db_exists "$name" && status_db "$name"
            done <<< "$DATABASES"
            pause
            ;;
        0) echo ""; log "Até logo!"; exit 0 ;;
    esac
}

interactive_menu() {
    while true; do
        show_main_menu
    done
}
