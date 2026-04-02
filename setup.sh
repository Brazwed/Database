#!/usr/bin/env bash

# ============================================================
# Database Toolkit v1.0 - por Brazwed
# https://github.com/Brazwed/Database
# ============================================================

VERSION="1.0"
AUTHOR="Brazwed"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Flags
AUTO_YES=false

# Language detection
CONFIG_DIR="${HOME}/.db-toolkit"
DT_LANG="en_US"
if [ -f "${CONFIG_DIR}/lang" ]; then
    DT_LANG=$(cat "${CONFIG_DIR}/lang")
else
    case "${LANG:-en_US}" in
        pt_*|br_*) DT_LANG="pt_BR" ;;
    esac
fi
source "${SCRIPT_DIR}/lib/lang/${DT_LANG}.sh" 2>/dev/null || source "${SCRIPT_DIR}/lib/lang/en_US.sh"

# Configuração
GITHUB_BASE="${GITHUB_BASE:-https://github.com/Brazwed}"
BACKUP_DIR="${HOME}/.db-toolkit/backups"

DATABASES="persistent|postgres|PostgreSQL 16|5432|db-postgres|postgres|/opt/db-postgres
persistent|mysql|MySQL 8|3306|db-mysql|mysql|/opt/db-mysql
persistent|mariadb|MariaDB 11|3307|db-mariadb|mariadb|/opt/db-mariadb
persistent|mongodb|MongoDB 7|27017|db-mongodb|mongodb|/opt/db-mongodb
memory|dragonfly|DragonflyDB|6379|db-dragonfly|dragonfly|/opt/db-dragonfly
memory|valkey|Valkey 8|6380|db-valkey|valkey|/opt/db-valkey"

FW_TYPE="none"
FW_ACTIVE=false

ALL_BANCOS="postgres, dragonfly, mysql, mariadb, mongodb, valkey"

# Load modules (order matters: utils first)
for lib in "$SCRIPT_DIR"/lib/*.sh; do
    source "$lib"
done

# ============================================================
# ARGS
# ============================================================

parse_args() {
    local action="${1:-}"
    shift 2>/dev/null || true
    local args="$*"

    case "$action" in
        install)
            if [ -z "$args" ]; then
                err "Uso: $0 install <docker|$ALL_BANCOS>"
            fi
            for arg in $args; do
                case "$arg" in
                    docker) install_docker ;;
                    postgres|dragonfly|mysql|mariadb|mongodb|valkey) install_db "$arg" ;;
                    *) warn "${ERR_UNKNOWN_DB_SHORT}" ;;
                esac
            done
            ;;
        up)
            [ -z "$args" ] && err "Uso: $0 up <$ALL_BANCOS>"
            for db in $args; do start_db "$db"; done
            ;;
        down)
            [ -z "$args" ] && err "Uso: $0 down <$ALL_BANCOS>"
            for db in $args; do stop_db "$db"; done
            ;;
        restart)
            [ -z "$args" ] && err "Uso: $0 restart <$ALL_BANCOS>"
            for db in $args; do restart_db "$db"; done
            ;;
        update)
            [ -z "$args" ] && err "Uso: $0 update <$ALL_BANCOS>"
            for db in $args; do update_db "$db"; done
            ;;
        status)
            if [ -z "$args" ]; then
                while IFS='|' read -r _ name _; do
                    [ -n "$name" ] && db_exists "$name" && status_db "$name"
                done <<< "$DATABASES"
            else
                for db in $args; do status_db "$db"; done
            fi
            ;;
        logs)
            [ -z "$args" ] && err "Uso: $0 logs <$ALL_BANCOS>"
            logs_db "$args"
            ;;
        shell)
            [ -z "$args" ] && err "Uso: $0 shell <$ALL_BANCOS>"
            shell_db "$args"
            ;;
        psql)
            shell_db "postgres"
            ;;
        mysql)
            shell_db "mysql"
            ;;
        mariadb)
            shell_db "mariadb"
            ;;
        mongo)
            shell_db "mongodb"
            ;;
        valkey)
            shell_db "valkey"
            ;;
        remove)
            [ -z "$args" ] && err "Uso: $0 remove <$ALL_BANCOS>"
            for db in $args; do remove_db "$db"; done
            ;;
        detect)
            detect_vps_state
            ;;
        lang)
            mkdir -p "$CONFIG_DIR"
            case "${args:-}" in
                pt|pt_BR) echo "pt_BR" > "${CONFIG_DIR}/lang"; log "$LOG_LANG_CHANGED" ;;
                en|en_US) echo "en_US" > "${CONFIG_DIR}/lang"; log "$LOG_LANG_CHANGED" ;;
                *) err "Uso: $0 lang <pt|en>" ;;
            esac
            ;;
        backup)
            if [ -z "$args" ] || [ "$args" = "all" ]; then
                create_backup "vps" "manual"
                while IFS='|' read -r _ bn _; do
                    [ -n "$bn" ] && db_exists "$bn" && create_backup "$bn" "manual"
                done <<< "$DATABASES"
            elif [ "$args" = "vps" ]; then
                create_backup "vps" "manual"
            else
                for db in $args; do
                    db_exists "$db" && create_backup "$db" "manual" || warn "${ERR_NOT_INSTALLED}"
                done
            fi
            ;;
        backups)
            list_backups "${args:-all}"
            ;;
        rollback)
            local rt="${args%% *}"
            local rts="${args#* }"
            [ "$rts" = "$rt" ] && rts=""
            [ -z "$rt" ] && err "Uso: $0 rollback <db|vps> [timestamp]"
            restore_backup "$rt" "$rts"
            ;;
        *)
            err "${MSG_HELP_USAGE}
  \$0                           ${MSG_HELP_INSTALL}
  \$0 install docker            ${MSG_HELP_INSTALL_DOCKER}
  \$0 up <db>                   ${MSG_HELP_UP}
  \$0 down <db>                 ${MSG_HELP_DOWN}
  \$0 restart <db>              ${MSG_HELP_RESTART}
  \$0 update <db>               ${MSG_HELP_UPDATE}
  \$0 status [db]               ${MSG_HELP_STATUS}
  \$0 logs <db>                 ${MSG_HELP_LOGS}
  \$0 shell <db>                ${MSG_HELP_SHELL}
  \$0 psql                      ${MSG_HELP_SHELL} postgres
  \$0 mysql                     ${MSG_HELP_SHELL} mysql
  \$0 mariadb                   ${MSG_HELP_SHELL} mariadb
  \$0 mongo                     ${MSG_HELP_SHELL} mongodb
  \$0 valkey                    ${MSG_HELP_SHELL} valkey
  \$0 remove <db>               ${MSG_HELP_REMOVE}
  \$0 detect                    ${MSG_HELP_DETECT}
  \$0 backup [db|vps|all]       ${MSG_HELP_BACKUP}
  \$0 backups [db]              ${MSG_HELP_BACKUPS}
  \$0 rollback <db> [timestamp] ${MSG_HELP_ROLLBACK}

${MSG_HELP_DATABASES}: \$ALL_BANCOS"
            ;;
    esac
}

# ============================================================
# MAIN
# ============================================================

main() {
    # Handle flags before root check
    case "${1:-}" in
        -v|--version)
            echo "Database Toolkit v${VERSION} por ${AUTHOR}"
            echo "https://github.com/Brazwed/Database"
            exit 0
            ;;
        -h|--help)
            echo "${MSG_HELP_USAGE}"
            echo ""
            echo "${MSG_HELP_ACTIONS}"
            echo "  install <db>              ${MSG_HELP_INSTALL}"
            echo "  install docker            ${MSG_HELP_INSTALL_DOCKER}"
            echo "  up <db>                   ${MSG_HELP_UP}"
            echo "  down <db>                 ${MSG_HELP_DOWN}"
            echo "  restart <db>              ${MSG_HELP_RESTART}"
            echo "  update <db>               ${MSG_HELP_UPDATE}"
            echo "  status [db]               ${MSG_HELP_STATUS}"
            echo "  logs <db>                 ${MSG_HELP_LOGS}"
            echo "  shell <db>                ${MSG_HELP_SHELL}"
            echo "  remove <db>               ${MSG_HELP_REMOVE}"
            echo "  detect                    ${MSG_HELP_DETECT}"
            echo "  backup [db|vps|all]       ${MSG_HELP_BACKUP}"
            echo "  backups [db]              ${MSG_HELP_BACKUPS}"
            echo "  rollback <db> [timestamp] ${MSG_HELP_ROLLBACK}"
            echo ""
            echo "${MSG_HELP_DATABASES}: $ALL_BANCOS"
            echo ""
            echo "${MSG_HELP_OPTIONS}"
            echo "  -v, --version             ${MSG_HELP_SHOW_VERSION}"
            echo "  -h, --help                ${MSG_HELP_SHOW_HELP}"
            echo "  -y, --yes                 ${MSG_HELP_NON_INTERACTIVE}"
            echo "  lang <pt|en>              ${MSG_HELP_LANG}"
            exit 0
            ;;
    esac

    [ "$(id -u)" -ne 0 ] && err "${ERR_MUST_BE_ROOT}"
    mkdir -p "$BACKUP_DIR"

    # Parse --yes flag
    local clean_args=()
    for arg in "$@"; do
        if [ "$arg" = "-y" ] || [ "$arg" = "--yes" ]; then
            AUTO_YES=true
        else
            clean_args+=("$arg")
        fi
    done

    if [ ${#clean_args[@]} -gt 0 ]; then
        parse_args "${clean_args[@]}"
        exit 0
    fi

    interactive_menu
}

main "$@"
