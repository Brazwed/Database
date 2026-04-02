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
    while true; do
        echo ""
        echo -e "  ${BD}${C}Instalar banco${NC}"
        echo ""

        local persistent_names=() memory_names=() idx=1

        while IFS='|' read -r cat name display port _; do
            [ -z "$name" ] && continue
            local marker=""
            db_exists "$name" && marker=" ${G}(já instalado)${NC}"
            if [ "$cat" = "persistent" ]; then
                echo -e "    [$idx] $display (:$port)$marker"
                persistent_names+=("$name")
            else
                echo -e "    [$idx] $display (:$port)$marker"
                memory_names+=("$name")
            fi
            idx=$((idx + 1))
        done <<< "$DATABASES"

        local all_names=("${persistent_names[@]}" "${memory_names[@]}")
        echo ""
        echo "    [0] Voltar"
        echo ""
        read -rp "  Escolha: " ch
        [ "$ch" = "0" ] && return
        local n=${all_names[$((ch - 1))]:-}
        [ -z "$n" ] && continue
        install_db "$n"
    done
}

# ─── SUBMENU: GERENCIAR ─────────────────────────────────────
submenu_manage() {
    local installed_raw names=()
    installed_raw=$(get_installed_list)
    [ -z "$(echo "$installed_raw" | tr -d '[:space:]')" ] && { echo ""; return 1; }

    local idx=1
    while IFS='|' read -r name display port status dir; do
        [ -z "$name" ] && continue
        if [ "$status" = "running" ]; then
            echo -e "    ${G}●${NC} $display (:$port) rodando"
        else
            echo -e "    ${R}●${NC} $display (:$port) parado"
        fi
        names+=("$name")
    done <<< "$installed_raw"

    [ ${#names[@]} -eq 0 ] && { warn "Nenhum banco instalado"; return 1; }

    echo ""
    echo "  Ações:"
    echo "    [u] Update    [d] Down    [U] Up    [r] Remove    [l] Logs"
    echo ""
    read -rp "  Ação + nº (ex: u1, d2, r3): " input

    local act="${input:0:1}"
    local num="${input:1}"
    local n=${names[$((num - 1))]:-}

    case "$act" in
        u) [ -n "$n" ] && update_db "$n" ;;
        d) [ -n "$n" ] && stop_db "$n" ;;
        U) [ -n "$n" ] && start_db "$n" ;;
        r) [ -n "$n" ] && remove_db "$n" ;;
        l) [ -n "$n" ] && logs_db "$n" ;;
        *) warn "Opção inválida" ;;
    esac
}

# ─── SUBMENU: CONECTAR ──────────────────────────────────────
submenu_connect() {
    while true; do
        local installed_raw names=()
        installed_raw=$(get_installed_list)

        local has_running=false
        local idx=1
        local running_names=()

        while IFS='|' read -r name display port status dir; do
            [ -z "$name" ] && continue
            if [ "$status" = "running" ]; then
                echo "  [$idx] $display (:$port)"
                running_names+=("$name")
                has_running=true
                idx=$((idx + 1))
            fi
        done <<< "$installed_raw"

        if [ "$has_running" = "false" ]; then
            warn "Nenhum banco rodando. Use: [1] Instalar ou [2] Gerenciar → Up"
            return 1
        fi

        echo "  [0] Voltar"
        read -rp "  Escolha: " ch
        [ "$ch" = "0" ] && return
        local n=${running_names[$((ch - 1))]:-}
        [ -z "$n" ] && continue

        info "Conectando ao $(parse_db "$n" 2)..."
        shell_db "$n"
        return
    done
}

# ─── SUBMENU: BACKUPS ───────────────────────────────────────
submenu_backups() {
    while true; do
        echo ""
        echo -e "  ${BD}${C}Backups${NC}"
        echo ""
        echo "    [1] Criar backup manual"
        echo "    [2] Listar backups"
        echo "    [3] Restaurar backup"
        echo "    [0] Voltar"
        echo ""
        read -rp "  Escolha: " bk_ch

        case "$bk_ch" in
            1)
                echo ""
                echo "    [1] Backup completo (VPS + todos bancos)"
                echo "    [2] Backup de um banco específico"
                echo ""
                read -rp "  Escolha: " bk_type
                if [ "$bk_type" = "1" ]; then
                    create_backup "vps" "manual"
                    while IFS='|' read -r _ name _; do
                        [ -n "$name" ] && db_exists "$name" && create_backup "$name" "manual"
                    done <<< "$DATABASES"
                elif [ "$bk_type" = "2" ]; then
                    local db_names=() idx=1
                    while IFS='|' read -r _ name display _; do
                        [ -z "$name" ] && continue
                        if db_exists "$name"; then
                            echo "    [$idx] $display"
                            db_names+=("$name"); idx=$((idx + 1))
                        fi
                    done <<< "$DATABASES"
                    if [ ${#db_names[@]} -eq 0 ]; then
                        warn "Nenhum banco instalado"
                    else
                        read -rp "  Qual: " db_ch
                        local sel=${db_names[$((db_ch - 1))]:-}
                        [ -n "$sel" ] && create_backup "$sel" "manual"
                    fi
                fi
                ;;
            2)
                list_backups "all"
                ;;
            3)
                local db_names=() idx=1
                while IFS='|' read -r _ name display _; do
                    [ -z "$name" ] && continue
                    local bk_count
                    bk_count=$(ls -1 "${BACKUP_DIR}/${name}" 2>/dev/null | grep -v "^latest$" | wc -l)
                    if [ "$bk_count" -gt 0 ]; then
                        echo "    [$idx] $display ($bk_count backup(s))"
                        db_names+=("$name"); idx=$((idx + 1))
                    fi
                done <<< "$DATABASES"
                if [ ${#db_names[@]} -eq 0 ]; then
                    warn "Nenhum backup encontrado"
                else
                    read -rp "  Qual: " db_ch
                    local sel=${db_names[$((db_ch - 1))]:-}
                    [ -n "$sel" ] && restore_backup "$sel"
                fi
                ;;
            0) return ;;
        esac
    done
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

    # Imprimir persistentes
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

    # Imprimir memória
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

    # Comandos em grid
    echo -e "  📋 ${BD}Comandos${NC}"
    echo ""
    echo -e "    [1] Instalar     [2] Gerenciar    [3] Backups"
    if [ "$has_installed" = "true" ]; then
        echo -e "    [4] Conectar     [5] Status       [0] Sair"
    else
        echo -e "                       [0] Sair"
    fi
    echo ""
    read -rp "  Escolha: " choice

    case "$choice" in
        1) submenu_install ;;
        2) submenu_manage ;;
        3) submenu_backups ;;
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
