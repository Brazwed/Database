#!/usr/bin/env bash

# ============================================================
# Database Toolkit - Setup
# Entry point: source módulos e gerencia args/menu
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Configuração
GITHUB_BASE="${GITHUB_BASE:-https://github.com/Brazwed}"
BACKUP_DIR="${HOME}/.db-toolkit/backups"

DATABASES="postgres|PostgreSQL 16|5432|db-postgres|postgres|/opt/db-postgres
dragonfly|DragonflyDB|6379|db-dragonfly|dragonfly|/opt/db-dragonfly
mysql|MySQL 8|3306|db-mysql|mysql|/opt/db-mysql
mariadb|MariaDB 11|3307|db-mariadb|mariadb|/opt/db-mariadb"

FW_TYPE="none"
FW_ACTIVE=false

# Carrega módulos (ordem importa: utils primeiro)
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
                err "Uso: $0 install <docker|postgres|dragonfly|mysql|mariadb>"
            fi
            for arg in $args; do
                case "$arg" in
                    docker) install_docker ;;
                    postgres|dragonfly|mysql|mariadb) install_db "$arg" ;;
                    *) warn "Banco desconhecido: $arg" ;;
                esac
            done
            ;;
        up)
            [ -z "$args" ] && err "Uso: $0 up <postgres|dragonfly|mysql|mariadb>"
            for db in $args; do start_db "$db"; done
            ;;
        down)
            [ -z "$args" ] && err "Uso: $0 down <postgres|dragonfly|mysql|mariadb>"
            for db in $args; do stop_db "$db"; done
            ;;
        restart)
            [ -z "$args" ] && err "Uso: $0 restart <postgres|dragonfly|mysql|mariadb>"
            for db in $args; do restart_db "$db"; done
            ;;
        update)
            [ -z "$args" ] && err "Uso: $0 update <postgres|dragonfly|mysql|mariadb>"
            for db in $args; do update_db "$db"; done
            ;;
        status)
            if [ -z "$args" ]; then
                while IFS='|' read -r name _; do
                    [ -n "$name" ] && db_exists "$name" && status_db "$name"
                done <<< "$DATABASES"
            else
                for db in $args; do status_db "$db"; done
            fi
            ;;
        logs)
            [ -z "$args" ] && err "Uso: $0 logs <postgres|dragonfly|mysql|mariadb>"
            logs_db "$args"
            ;;
        shell)
            [ -z "$args" ] && err "Uso: $0 shell <postgres|dragonfly|mysql|mariadb>"
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
        remove)
            [ -z "$args" ] && err "Uso: $0 remove <postgres|dragonfly|mysql|mariadb>"
            for db in $args; do remove_db "$db"; done
            ;;
        detect)
            detect_vps_state
            ;;
        backup)
            if [ -z "$args" ] || [ "$args" = "all" ]; then
                create_backup "vps" "manual"
                while IFS='|' read -r bn _; do
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
  $0 psql                      shell psql
  $0 mysql                     shell mysql
  $0 remove <db>               remover banco
  $0 detect                    detectar estado da VPS
  $0 backup [db|vps|all]       criar backup
  $0 backups [db]              listar backups
  $0 rollback <db> [timestamp] restaurar backup

Bancos: postgres, dragonfly, mysql, mariadb"
            ;;
    esac
}

# ============================================================
# MAIN
# ============================================================

main() {
    [ "$(id -u)" -ne 0 ] && err "Execute como root: sudo $0"
    mkdir -p "$BACKUP_DIR"

    if [ -n "${1:-}" ]; then
        parse_args "$@"
        exit 0
    fi

    interactive_menu
}

main "$@"
