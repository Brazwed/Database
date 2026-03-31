# lib/database.sh - Operações de banco (install/start/stop/update/remove/status/logs/shell)

install_db() {
    local db="$1"
    local display default_port repo container dir port

    if ! db_info_valid "$db"; then
        err "Banco desconhecido: '$db'. Bancos válidos: postgres, dragonfly"
    fi

    display=$(parse_db "$db" 2)
    default_port=$(parse_db "$db" 3)
    repo=$(parse_db "$db" 4)
    container=$(parse_db "$db" 5)
    dir=$(parse_db "$db" 6)

    port="$default_port"

    detect_vps_state
    local vps_ok=$?
    if [ $vps_ok -ne 0 ]; then
        warn "Conflitos detectados"
        confirm "Continuar mesmo assim?" || return 0
    fi

    echo ""
    echo -e "  ${BD}${C}=== $display ===${NC}"
    echo ""
    echo "    Imagem:     $display"
    echo "    Porta:      $default_port"
    echo "    Pasta:      $dir"
    echo "    Repo:       ${GITHUB_BASE}/${repo}"
    echo ""

    read -rp "  Customizar? (pasta/porta) [y/N] " cust
    if [[ "$cust" =~ ^[yY]$ ]]; then
        echo ""
        read -rp "  Pasta [$dir]: " x; [ -n "$x" ] && dir="$x"
        read -rp "  Porta [$default_port]: " x; [ -n "$x" ] && port="$x"
        echo ""
        echo -e "  ${BD}=== Resumo ===${NC}"
        echo ""
        printf "    %-16s → %-30s (porta %s)\n" "$display" "$dir" "$port"
        echo ""
    fi

    confirm "Confirmar instalar?" || return 0

    create_backup "vps" "before-install-${db}"

    if ask_firewall_choice; then
        open_port "$port" "$display"
        log "Porta $port liberada"
    fi

    mkdir -p "$dir"

    if [ -d "$dir/.git" ]; then
        info "Repo existe, atualizando..."
        (cd "$dir" && git pull --quiet) || true
    else
        info "Baixando $display..."
        if ! git clone "${GITHUB_BASE}/${repo}.git" "$dir" 2>&1; then
            err "Falha ao clonar ${GITHUB_BASE}/${repo}.git"
        fi
    fi

    if [ -f "$dir/.env.example" ] && [ ! -f "$dir/.env" ]; then
        cp "$dir/.env.example" "$dir/.env"
    fi

    if [ -f "$dir/.env" ] && [ "$port" != "$default_port" ]; then
        case "$db" in
            postgres) sed -i "s/^PG_PORT=.*/PG_PORT=$port/" "$dir/.env" ;;
            dragonfly) sed -i "s/^DF_PORT=.*/DF_PORT=$port/" "$dir/.env" ;;
        esac
    fi

    chmod +x "$dir"/*.sh 2>/dev/null || true

    if ! has_docker; then
        err "Docker não instalado. Execute: $0 install docker"
    fi

    info "Subindo $display..."
    (cd "$dir" && docker compose up -d 2>&1)
    sleep 3

    local st
    st=$(get_container_status "$container")
    if [ "$st" = "running" ]; then
        log "$display rodando na porta $port"
    else
        warn "$display pode não ter iniciado. Verifique: $0 logs $db"
    fi

    show_info "$db"
}

start_db() {
    local db="$1"
    if ! db_info_valid "$db"; then
        warn "Banco desconhecido: '$db'"
        return 1
    fi
    local dir display container
    dir=$(parse_db "$db" 6); display=$(parse_db "$db" 2); container=$(parse_db "$db" 5)

    if ! db_exists "$db"; then
        warn "$display não instalado. Instale: $0 install $db"
        return 1
    fi

    info "Iniciando $display..."
    (cd "$dir" && docker compose up -d 2>&1)
    sleep 2

    local st
    st=$(get_container_status "$container")
    [ "$st" = "running" ] && log "$display rodando" || warn "$display pode não ter iniciado"
}

stop_db() {
    local db="$1"
    if ! db_info_valid "$db"; then
        warn "Banco desconhecido: '$db'"
        return 1
    fi
    local dir display
    dir=$(parse_db "$db" 6); display=$(parse_db "$db" 2)
    db_exists "$db" || { warn "$display não instalado"; return 1; }

    info "Parando $display..."
    (cd "$dir" && docker compose down --timeout 10 2>&1)
    log "$display parado!"
}

restart_db() { stop_db "$1"; start_db "$1"; }

update_db() {
    local db="$1"
    local dir display container st
    dir=$(parse_db "$db" 6); display=$(parse_db "$db" 2); container=$(parse_db "$db" 5)
    db_exists "$db" || { warn "$display não instalado"; return 1; }

    create_backup "$db" "before-update"

    info "Atualizando $display..."
    if ! (cd "$dir" && git pull --quiet 2>&1); then
        warn "Git pull falhou. Continuando com código atual..."
    fi

    st=$(get_container_status "$container")
    if [ "$st" = "running" ]; then
        (cd "$dir" && docker compose restart 2>&1)
    else
        (cd "$dir" && docker compose up -d 2>&1)
    fi

    log "$display atualizado!"
}

remove_db() {
    local db="$1"
    local dir display container
    dir=$(parse_db "$db" 6); display=$(parse_db "$db" 2); container=$(parse_db "$db" 5)
    db_exists "$db" || { warn "$display não instalado"; return 1; }

    warn "PARAR e REMOVER $display completamente"
    confirm "Certeza?" || return 0

    create_backup "$db" "before-remove"

    (cd "$dir" && docker compose down -v --timeout 10 2>&1)
    rm -rf "$dir"
    log "$display removido!"
}

status_db() {
    local db="$1"
    if ! db_info_valid "$db"; then
        warn "Banco desconhecido: '$db'"
        return 1
    fi
    local dir display port container
    dir=$(parse_db "$db" 6); display=$(parse_db "$db" 2)
    port=$(parse_db "$db" 3); container=$(parse_db "$db" 5)

    echo ""
    echo -e "${BD}${C}=== $display ===${NC}"
    echo "  Pasta:  $dir"
    echo "  Porta:  $port"

    local st
    st=$(get_container_status "$container")
    if [ "$st" = "running" ]; then
        echo -e "  Status: ${G}running${NC}"
        show_info "$db"
    else
        echo -e "  Status: ${R}stopped${NC}"
    fi
}

show_info() {
    local db="$1"
    if ! db_info_valid "$db"; then return 1; fi
    local dir display port
    dir=$(parse_db "$db" 6); display=$(parse_db "$db" 2); port=$(parse_db "$db" 3)

    echo ""
    if [ "$db" = "postgres" ]; then
        local user="postgres" pass="postgres_dev_2026" dbname="devdb"
        [ -f "$dir/.env" ] && {
            user=$(grep -m1 "^PG_USER=" "$dir/.env" | cut -d= -f2)
            pass=$(grep -m1 "^PG_PASS=" "$dir/.env" | cut -d= -f2)
            dbname=$(grep -m1 "^PG_DB=" "$dir/.env" | cut -d= -f2)
        }
        echo "  Host:     localhost"
        echo "  Port:     $port"
        echo "  Database: $dbname"
        echo "  User:     $user"
        echo "  Pass:     $pass"
        echo ""
        echo "  Connect: psql -h localhost -p $port -U $user -d $dbname"
    elif [ "$db" = "dragonfly" ]; then
        local pass="dragonfly_dev_2026"
        [ -f "$dir/.env" ] && pass=$(grep -m1 "^DF_PASS=" "$dir/.env" | cut -d= -f2)
        echo "  Host: localhost"
        echo "  Port: $port"
        echo "  Pass: $pass"
        echo ""
        echo "  Connect: redis-cli -h localhost -p $port -a $pass"
    fi
}

logs_db() {
    local db="$1" dir display
    dir=$(parse_db "$db" 6); display=$(parse_db "$db" 2)
    db_exists "$db" || { warn "$display não instalado"; return 1; }

    info "Logs de $display (Ctrl+C pra sair)..."
    (cd "$dir" && docker compose logs -f)
}

shell_db() {
    local db="$1" dir display container
    dir=$(parse_db "$db" 6); display=$(parse_db "$db" 2); container=$(parse_db "$db" 5)
    db_exists "$db" || { warn "$display não instalado"; return 1; }

    local st
    st=$(get_container_status "$container")
    [ "$st" != "running" ] && { warn "$display não rodando. Use: $0 up $db"; return 1; }

    (cd "$dir" && docker compose exec -it "$container" sh)
}
