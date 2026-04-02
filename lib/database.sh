# lib/database.sh - Operações de banco (install/start/stop/update/remove/status/logs/shell)

install_db() {
    local db="$1"
    local display default_port repo container dir port

    if ! db_info_valid "$db"; then
        err "${ERR_UNKNOWN_DB}: $db"
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
        warn "${ERR_PORT_CONFLICT}"
        confirm "${PROMPT_CONTINUE}" || return 0
    fi

    echo ""
    echo -e "  ${BD}${C}=== $display ===${NC}"
    echo ""
    echo "    ${MSG_INST_IMAGE}     $display"
    echo "    ${MSG_INFO_PORT}      $default_port"
    echo "    ${MSG_INFO_CUSTOM_PORT}      $dir"
    echo "    Repo:       ${GITHUB_BASE}/${repo}"
    echo ""

    if [ "$AUTO_YES" != "true" ]; then
        read -rp "  ${MSG_INST_CUSTOMIZE}" cust
        if [[ "$cust" =~ ^[yY]$ ]]; then
            echo ""
            read -rp "  ${PROMPT_FOLDER}" x; [ -n "$x" ] && dir="$x"
            read -rp "  ${PROMPT_PORT}" x; [ -n "$x" ] && port="$x"
            echo ""
            echo -e "  ${BD}=== Resumo ===${NC}"
            echo ""
            printf "    %-16s → %-30s (port %s)\n" "$display" "$dir" "$port"
            echo ""
        fi
    fi

    confirm "${PROMPT_CONFIRM}" || return 0

    create_backup "vps" "before-install-${db}"

    if ask_firewall_choice; then
        open_port "$port" "$display"
        log "${LOG_PORT_OPENED} $port"
    fi

    # Check disk space (need at least 500MB)
    local avail_kb
    avail_kb=$(df --output=avail "$dir" 2>/dev/null | tail -1 | tr -d ' ')
    if [ -n "$avail_kb" ] && [ "$avail_kb" -lt 512000 ] 2>/dev/null; then
        warn "${ERR_DISK_SPACE} ($(( avail_kb / 1024 ))MB livre). Recomendado: 500MB+"
        confirm "${PROMPT_CONFIRM}" || return 1
    fi

    mkdir -p "$dir"

    if [ -d "$dir/.git" ]; then
        spinner "${MSG_LOG_UPDATING} $display"
        (cd "$dir" && git pull --quiet) || true
    else
        spinner "${MSG_LOG_DOWNLOADING} $display"
        if ! git clone "${GITHUB_BASE}/${repo}.git" "$dir" 2>&1; then
            err "${ERR_CLONE_FAIL} ${GITHUB_BASE}/${repo}.git"
        fi
    fi

    if [ -f "$dir/.env.example" ] && [ ! -f "$dir/.env" ]; then
        cp "$dir/.env.example" "$dir/.env"
    fi

    if [ -f "$dir/.env" ] && [ "$port" != "$default_port" ]; then
        case "$db" in
            postgres) sed -i "s/^PG_PORT=.*/PG_PORT=$port/" "$dir/.env" ;;
            dragonfly) sed -i "s/^DF_PORT=.*/DF_PORT=$port/" "$dir/.env" ;;
            mysql) sed -i "s/^MY_PORT=.*/MY_PORT=$port/" "$dir/.env" ;;
            mariadb) sed -i "s/^MA_PORT=.*/MA_PORT=$port/" "$dir/.env" ;;
            mongodb) sed -i "s/^MO_PORT=.*/MO_PORT=$port/" "$dir/.env" ;;
            valkey) sed -i "s/^VK_PORT=.*/VK_PORT=$port/" "$dir/.env" ;;
        esac
    fi

    chmod +x "$dir"/*.sh 2>/dev/null || true

    if ! has_docker; then
        err "${ERR_DOCKER_NOT_INSTALLED}. Execute: $0 install docker"
    fi

    spinner "${MSG_LOG_STARTING} $display"
    (cd "$dir" && docker compose up -d 2>&1)
    sleep 3

    local st
    st=$(get_container_status "$container")
    if [ "$st" = "running" ]; then
        log "$display ${MSG_LOG_STARTING} $port"
    else
        warn "$display ${ERR_WONT_START}. Verifique: $0 logs $db"
    fi

    show_info "$db"
}

start_db() {
    local db="$1"
    if ! db_info_valid "$db"; then
        warn "${ERR_UNKNOWN_DB_SHORT}"
        return 1
    fi
    local dir display container
    dir=$(parse_db "$db" 6); display=$(parse_db "$db" 2); container=$(parse_db "$db" 5)

    if ! db_exists "$db"; then
        warn "$display ${ERR_NOT_INSTALLED}. Instale: $0 install $db"
        return 1
    fi

    spinner "${MSG_LOG_STARTING} $display"
    (cd "$dir" && docker compose up -d 2>&1)
    sleep 2

    local st
    st=$(get_container_status "$container")
    [ "$st" = "running" ] && log "$display ${LOG_STARTED}" || warn "$display ${ERR_WONT_START}"
}

stop_db() {
    local db="$1"
    if ! db_info_valid "$db"; then
        warn "${ERR_UNKNOWN_DB_SHORT}"
        return 1
    fi
    local dir display
    dir=$(parse_db "$db" 6); display=$(parse_db "$db" 2)
    db_exists "$db" || { warn "$display ${ERR_NOT_INSTALLED}"; return 1; }

    spinner "${MSG_LOG_STOPPING} $display"
    (cd "$dir" && docker compose down --timeout 10 2>&1)
    log "$display ${MSG_STATUS_STOPPED}"
}

restart_db() { stop_db "$1"; start_db "$1"; }

update_db() {
    local db="$1"
    local dir display container st
    dir=$(parse_db "$db" 6); display=$(parse_db "$db" 2); container=$(parse_db "$db" 5)
    db_exists "$db" || { warn "$display ${ERR_NOT_INSTALLED}"; return 1; }

    create_backup "$db" "before-update"

    spinner "${MSG_LOG_UPDATING} $display"
    if ! (cd "$dir" && git pull --quiet 2>&1); then
        warn "${ERR_GIT_PULL_FAIL}. Continuando com código atual..."
    fi

    st=$(get_container_status "$container")
    if [ "$st" = "running" ]; then
        spinner "${MSG_LOG_RESTARTING}"
        (cd "$dir" && docker compose restart 2>&1)
    else
        spinner "${MSG_LOG_STARTING} container"
        (cd "$dir" && docker compose up -d 2>&1)
    fi

    log "$display ${LOG_UPDATED}"
}

remove_db() {
    local db="$1"
    local dir display container
    dir=$(parse_db "$db" 6); display=$(parse_db "$db" 2); container=$(parse_db "$db" 5)
    db_exists "$db" || { warn "$display ${ERR_NOT_INSTALLED}"; return 1; }

    warn "${ERR_PARAR_REMOVER} $display"
    confirm "${PROMPT_ARE_YOU_SURE}" || return 0

    create_backup "$db" "before-remove"

    spinner "${MSG_LOG_REMOVING} $display"
    (cd "$dir" && docker compose down -v --timeout 10 2>&1)
    rm -rf "$dir"
    log "$display ${LOG_REMOVED}"
}

status_db() {
    local db="$1"
    if ! db_info_valid "$db"; then
        warn "${ERR_UNKNOWN_DB_SHORT}"
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
        echo -e "  Status: ${BD}${G}● ${MSG_STATUS_RUNNING}${NC}"
        show_info "$db"
    else
        echo -e "  Status: ${BD}${R}● ${MSG_STATUS_STOPPED}${NC}"
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
        echo "  ${MSG_INFO_HOST}     localhost"
        echo "  ${MSG_INFO_PORT}     $port"
        echo "  ${MSG_INFO_DATABASE} $dbname"
        echo "  ${MSG_INFO_USER}     $user"
        echo "  ${MSG_INFO_PASS}     $pass"
        echo ""
        echo "  Connect: psql -h localhost -p $port -U $user -d $dbname"
    elif [ "$db" = "dragonfly" ]; then
        local pass="dragonfly_dev_2026"
        [ -f "$dir/.env" ] && pass=$(grep -m1 "^DF_PASS=" "$dir/.env" | cut -d= -f2)
        echo "  ${MSG_INFO_HOST} localhost"
        echo "  ${MSG_INFO_PORT} $port"
        echo "  ${MSG_INFO_PASS} $pass"
        echo ""
        echo "  Connect: redis-cli -h localhost -p $port -a $pass"
    elif [ "$db" = "mysql" ]; then
        local user="mysql_user" pass="mysql_dev_2026" dbname="devdb"
        [ -f "$dir/.env" ] && {
            user=$(grep -m1 "^MY_USER=" "$dir/.env" | cut -d= -f2)
            pass=$(grep -m1 "^MY_PASS=" "$dir/.env" | cut -d= -f2)
            dbname=$(grep -m1 "^MY_DB=" "$dir/.env" | cut -d= -f2)
        }
        echo "  ${MSG_INFO_HOST}     localhost"
        echo "  ${MSG_INFO_PORT}     $port"
        echo "  ${MSG_INFO_DATABASE} $dbname"
        echo "  ${MSG_INFO_USER}     $user"
        echo "  ${MSG_INFO_PASS}     $pass"
        echo ""
        echo "  Connect: mysql -h localhost -P $port -u $user -p$pass $dbname"
    elif [ "$db" = "mariadb" ]; then
        local user="mariadb_user" pass="mariadb_dev_2026" dbname="devdb"
        [ -f "$dir/.env" ] && {
            user=$(grep -m1 "^MA_USER=" "$dir/.env" | cut -d= -f2)
            pass=$(grep -m1 "^MA_PASS=" "$dir/.env" | cut -d= -f2)
            dbname=$(grep -m1 "^MA_DB=" "$dir/.env" | cut -d= -f2)
        }
        echo "  ${MSG_INFO_HOST}     localhost"
        echo "  ${MSG_INFO_PORT}     $port"
        echo "  ${MSG_INFO_DATABASE} $dbname"
        echo "  ${MSG_INFO_USER}     $user"
        echo "  ${MSG_INFO_PASS}     $pass"
        echo ""
        echo "  Connect: mysql -h localhost -P $port -u $user -p$pass $dbname"
    elif [ "$db" = "mongodb" ]; then
        local user="mongodb_user" pass="mongodb_dev_2026" dbname="devdb"
        [ -f "$dir/.env" ] && {
            user=$(grep -m1 "^MO_USER=" "$dir/.env" | cut -d= -f2)
            pass=$(grep -m1 "^MO_PASS=" "$dir/.env" | cut -d= -f2)
            dbname=$(grep -m1 "^MO_DB=" "$dir/.env" | cut -d= -f2)
        }
        echo "  ${MSG_INFO_HOST}     localhost"
        echo "  ${MSG_INFO_PORT}     $port"
        echo "  ${MSG_INFO_DATABASE} $dbname"
        echo "  ${MSG_INFO_USER}     $user"
        echo "  ${MSG_INFO_PASS}     $pass"
        echo ""
        echo "  Connect: mongosh mongodb://$user:$pass@localhost:$port/$dbname"
    elif [ "$db" = "valkey" ]; then
        local pass="valkey_dev_2026"
        [ -f "$dir/.env" ] && pass=$(grep -m1 "^VK_PASS=" "$dir/.env" | cut -d= -f2)
        echo "  ${MSG_INFO_HOST} localhost"
        echo "  ${MSG_INFO_PORT} $port"
        echo "  ${MSG_INFO_PASS} $pass"
        echo ""
        echo "  Connect: redis-cli -h localhost -p $port -a $pass"
    fi
}

logs_db() {
    local db="$1" dir display
    dir=$(parse_db "$db" 6); display=$(parse_db "$db" 2)
    db_exists "$db" || { warn "$display ${ERR_NOT_INSTALLED}"; return 1; }

    info "${MSG_INFO_LOGS} (Ctrl+C pra sair)..."
    (cd "$dir" && docker compose logs -f --no-log-prefix)
}

shell_db() {
    local db="$1" dir display container
    dir=$(parse_db "$db" 6); display=$(parse_db "$db" 2); container=$(parse_db "$db" 5)
    db_exists "$db" || { warn "$display ${ERR_NOT_INSTALLED}"; return 1; }

    local st
    st=$(get_container_status "$container")
    [ "$st" != "running" ] && { warn "$display ${ERR_NOT_RUNNING}. Use: $0 up $db"; return 1; }

    (cd "$dir" && docker compose exec -it "$container" sh)
}
