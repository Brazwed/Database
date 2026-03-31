# lib/menu.sh - Menus interativos

select_installed_db() {
    local prompt="$1"
    local installed_raw
    installed_raw=$(get_installed_list)

    if [ -z "$(echo "$installed_raw" | tr -d '[:space:]')" ]; then
        warn "Nenhum banco instalado" >&2; return 1
    fi

    echo "" >&2
    local idx=1 names=()
    while IFS='|' read -r name display _; do
        [ -z "$name" ] && continue
        echo "  [$idx] $display" >&2
        names+=("$name"); idx=$((idx + 1))
    done <<< "$installed_raw"
    echo "  [0] Voltar" >&2
    echo "" >&2

    read -rp "  $prompt: " ch >&2
    [ "$ch" = "0" ] && return 1

    if [ "$ch" -ge 1 ] 2>/dev/null && [ "$ch" -le "${#names[@]}" ] 2>/dev/null; then
        echo "${names[$((ch - 1))]}"; return 0
    fi
    warn "Inválido" >&2; return 1
}

submenu_install() {
    while true; do
        clear
        echo ""
        echo -e "  ${BD}${C}← Instalar${NC}"
        echo ""
        echo "  O que você quer instalar?"
        echo ""

        local idx=1 docker_idx="" docker_opt=false

        if ! has_docker; then
            echo "    [1] Docker Engine + Compose"
            echo ""
            echo "  Necessário pra rodar os bancos."
            echo ""
            docker_idx=1; docker_opt=true; idx=$((idx + 1))
        fi

        echo -e "  ${BD}Bancos:${NC}"
        local db_names=()
        while IFS='|' read -r name display port _; do
            [ -z "$name" ] && continue
            if db_exists "$name"; then
                echo -e "    [$idx] $display (porta $port) ${G}já instalado${NC}"
            else
                echo "    [$idx] $display (porta $port)"
            fi
            db_names+=("$name"); idx=$((idx + 1))
        done <<< "$DATABASES"

        echo ""
        echo "    [0] ← Voltar ao menu principal"
        echo ""

        read -rp "  Escolha: " choice
        [ "$choice" = "0" ] && return

        if [ "$docker_opt" = "true" ] && [ "$choice" = "$docker_idx" ]; then
            install_docker; pause; continue
        fi

        local adj=$choice
        [ "$docker_opt" = "true" ] && adj=$((choice - 1))

        if [ "$adj" -ge 1 ] 2>/dev/null && [ "$adj" -le "${#db_names[@]}" ] 2>/dev/null; then
            install_db "${db_names[$((adj - 1))]}"; pause; continue
        fi

        warn "Opção inválida"
    done
}

submenu_manage() {
    while true; do
        clear
        echo ""
        echo -e "  ${BD}${C}← Gerenciar bancos${NC}"
        echo ""

        local installed_raw
        installed_raw=$(get_installed_list)

        if [ -z "$(echo "$installed_raw" | tr -d '[:space:]')" ]; then
            echo "  Nenhum banco instalado."
            echo ""; pause; return
        fi

        echo -e "  ${BD}Bancos instalados:${NC}"
        echo ""
        local names=()
        while IFS='|' read -r name display port status dir; do
            [ -z "$name" ] && continue
            if [ "$status" = "running" ]; then
                echo -e "    ${G}●${NC} $display (porta $port) rodando"
            else
                echo -e "    ${R}●${NC} $display (porta $port) parado"
            fi
            names+=("$name")
        done <<< "$installed_raw"

        echo ""
        echo -e "  ${BD}O que fazer?${NC}"
        echo ""
        echo "    [U] Atualizar (git pull + restart/up)"
        echo "    [D] Parar (docker compose down)"
        echo "    [S] Status (detalhes + conexão)"
        echo "    [L] Logs (acompanhar em tempo real)"
        echo "    [B] Backup (criar backup manual)"
        echo "    [R] Rollback (restaurar backup)"
        echo "    [X] Remover (deletar tudo)"
        echo "    [0] ← Voltar ao menu principal"
        echo ""

        read -rp "  Escolha: " action
        [ "$action" = "0" ] && return
        action=$(echo "$action" | tr '[:upper:]' '[:lower:]')

        local db_name
        case "$action" in
            u) db_name=$(select_installed_db "Qual banco atualizar?") || continue
               update_db "$db_name"; pause ;;
            d) db_name=$(select_installed_db "Qual banco parar?") || continue
               stop_db "$db_name"; pause ;;
            s)
                for name in "${names[@]}"; do status_db "$name"; done
                pause ;;
            l) db_name=$(select_installed_db "Qual banco ver logs?") || continue
               logs_db "$db_name" ;;
            b) db_name=$(select_installed_db "Qual banco fazer backup?") || continue
               create_backup "$db_name" "manual"; pause ;;
            r) db_name=$(select_installed_db "Qual banco restaurar?") || continue
               restore_backup "$db_name"; pause ;;
            x) db_name=$(select_installed_db "Qual banco remover?") || continue
               remove_db "$db_name"; pause ;;
            *) warn "Opção inválida" ;;
        esac
    done
}

submenu_backups() {
    while true; do
        clear
        echo ""
        echo -e "  ${BD}${C}← Backups${NC}"
        echo ""

        echo "    [1] Listar todos os backups"
        echo "    [2] Listar backups por banco"
        echo "    [3] Criar backup manual"
        echo "    [4] Restaurar backup"
        echo "    [0] ← Voltar ao menu principal"
        echo ""

        read -rp "  Escolha: " choice

        case "$choice" in
            1) list_backups "all"; pause ;;
            2)
                echo ""
                echo "  Qual banco?"
                local idx=1 db_names=()
                while IFS='|' read -r name display _; do
                    [ -z "$name" ] && continue
                    echo "    [$idx] $display"
                    db_names+=("$name"); idx=$((idx + 1))
                done <<< "$DATABASES"
                echo "    [0] Voltar"
                echo ""
                read -rp "  Escolha: " ch
                [ "$ch" = "0" ] && continue
                if [ "$ch" -ge 1 ] 2>/dev/null && [ "$ch" -le "${#db_names[@]}" ] 2>/dev/null; then
                    list_backups "${db_names[$((ch - 1))]}"
                fi
                pause
                ;;
            3)
                echo ""
                echo "  O que fazer backup?"
                echo "    [1] Banco específico"
                echo "    [2] Estado da VPS"
                echo "    [0] Voltar"
                echo ""
                read -rp "  Escolha: " bk_ch
                case "$bk_ch" in
                    1)
                        local db_name
                        db_name=$(select_installed_db "Qual banco?") || continue
                        create_backup "$db_name" "manual"; pause
                        ;;
                    2) create_backup "vps" "manual"; pause ;;
                esac
                ;;
            4)
                local db_name
                db_name=$(select_installed_db "Qual banco restaurar?") || continue

                local bk_path="${BACKUP_DIR}/${db_name}"
                if [ ! -d "$bk_path" ]; then
                    warn "Nenhum backup para $db_name"; pause; continue
                fi

                echo ""
                local bk_idx=1 bk_timestamps=()
                for bk in $(ls -1r "$bk_path" 2>/dev/null | grep -v "^latest$"); do
                    local reason=""
                    [ -f "$bk_path/$bk/meta.json" ] && reason=$(grep '"reason"' "$bk_path/$bk/meta.json" | cut -d'"' -f4)
                    local bk_size
                    bk_size=$(du -sh "$bk_path/$bk" 2>/dev/null | cut -f1)
                    echo "    [$bk_idx] $bk  ($reason, $bk_size)"
                    bk_timestamps+=("$bk")
                    bk_idx=$((bk_idx + 1))
                done

                if [ "$bk_idx" -eq 1 ]; then
                    warn "Nenhum backup encontrado"; pause; continue
                fi

                echo "    [0] Voltar"
                echo ""
                read -rp "  Escolha: " bk_ch
                [ "$bk_ch" = "0" ] && continue

                if [ "$bk_ch" -ge 1 ] 2>/dev/null && [ "$bk_ch" -lt "$bk_idx" ] 2>/dev/null; then
                    restore_backup "$db_name" "${bk_timestamps[$((bk_ch - 1))]}"
                fi
                pause
                ;;
            0) return ;;
            *) warn "Opção inválida" ;;
        esac
    done
}

show_main_menu() {
    local installed_raw has_installed=false
    installed_raw=$(get_installed_list)
    [ -n "$(echo "$installed_raw" | tr -d '[:space:]')" ] && has_installed=true

    clear
    echo ""
    echo -e "  ${BD}${C}╔═══════════════════════════════════════════╗${NC}"
    echo -e "  ${BD}${C}║         Database Toolkit                  ║${NC}"
    echo -e "  ${BD}${C}╚═══════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "  ${BD}Sistema${NC}"
    if has_docker; then
        echo -e "    Docker:     ${G}● instalado${NC}"
    else
        echo -e "    Docker:     ${R}● não instalado${NC}"
    fi
    echo ""

    echo -e "  ${BD}Bancos${NC}"
    echo ""

    local any=false
    while IFS='|' read -r name display port repo container dir; do
        [ -z "$name" ] && continue
        local st="" color="${Y}" tag="não instalado"
        if echo "$installed_raw" | grep -q "^${name}|"; then
            st=$(echo "$installed_raw" | grep "^${name}|" | cut -d'|' -f4)
            if [ "$st" = "running" ]; then
                color="${G}"; tag="rodando"
            else
                color="${R}"; tag="parado"
            fi
            any=true
        fi
        echo -e "    ${C}${display}${NC}  porta ${port}  ${color}${tag}${NC}"
        if [ "$st" = "running" ]; then
            if [ "$name" = "postgres" ]; then
                echo "      → psql -h localhost -p $port -U postgres -d devdb"
            elif [ "$name" = "dragonfly" ]; then
                echo "      → redis-cli -h localhost -p $port"
            fi
        fi
    done <<< "$DATABASES"

    echo ""
    echo -e "  ${BD}Menu${NC}"
    echo ""
    echo "    [1] Instalar        preparar ambiente ou banco(s)"
    if [ "$any" = "true" ]; then
        echo "    [2] Gerenciar       atualizar, parar, status, remover"
    fi
    echo "    [3] Backups         criar, listar, restaurar"
    echo "    [0] Sair"
    echo ""
}

interactive_menu() {
    while true; do
        show_main_menu
        read -rp "  Escolha: " choice

        case "$choice" in
            1) submenu_install ;;
            2)
                local installed_raw
                installed_raw=$(get_installed_list)
                if [ -n "$(echo "$installed_raw" | tr -d '[:space:]')" ]; then
                    submenu_manage
                else
                    warn "Nenhum banco instalado. Use [1] primeiro."
                    pause
                fi
                ;;
            3) submenu_backups ;;
            0) echo ""; log "Até mais!"; exit 0 ;;
            *) warn "Opção inválida: $choice" ;;
        esac
    done
}
