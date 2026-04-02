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
                    *) warn "Banco desconhecido: $arg" ;;
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
                    db_exists "$db" && create_backup "$db" "manual" || warn "Não instalado: $db"
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
            err "Uso:
  $0                           menu interativo
  $0 install <db>              instalar banco
  $0 install docker            instalar Docker
  $0 up <db>                   iniciar banco
  $0 down <db>                 parar banco
  $0 restart <db>              reiniciar banco
  $0 update <db>               atualizar banco
  $0 status [db]               ver status
  $0 logs <db>                 acompanhar logs
  $0 shell <db>                shell no container
  $0 psql                      shell postgres
  $0 mysql                     shell mysql
  $0 mariadb                   shell mariadb
  $0 mongo                     shell mongodb
  $0 valkey                    shell valkey
  $0 remove <db>               remover banco
  $0 detect                    detectar estado da VPS
  $0 backup [db|vps|all]       criar backup
  $0 backups [db]              listar backups
  $0 rollback <db> [timestamp] restaurar backup

Bancos: $ALL_BANCOS"
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
            echo "Uso: sudo $0 [ação] [banco] [opções]"
            echo ""
            echo "Ações:"
            echo "  install <db>              instalar banco"
            echo "  up <db>                   iniciar banco"
            echo "  down <db>                 parar banco"
            echo "  restart <db>              reiniciar banco"
            echo "  update <db>               atualizar banco"
            echo "  status [db]               ver status"
            echo "  logs <db>                 acompanhar logs"
            echo "  shell <db>                shell no container"
            echo "  remove <db>               remover banco"
            echo "  detect                    detectar estado da VPS"
            echo "  backup [db|vps|all]       criar backup"
            echo "  backups [db]              listar backups"
            echo "  rollback <db> [timestamp] restaurar backup"
            echo ""
            echo "Bancos: $ALL_BANCOS"
            echo ""
            echo "Opções:"
            echo "  -v, --version             mostrar versão"
            echo "  -h, --help                mostrar ajuda"
            echo "  -y, --yes                 modo não-interativo (pular confirms)"
            exit 0
            ;;
    esac

    [ "$(id -u)" -ne 0 ] && err "Execute como root: sudo $0"
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
