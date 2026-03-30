#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Database Toolkit - Setup
# Bridge: provisiona VPS e gerencia bancos individuais
# ============================================================

# --- Configuração (edite aqui se fizer fork) ---
GITHUB_BASE="${GITHUB_BASE:-https://github.com/Brazwed}"

# Formato: name|display|port|repo|container|dir
DATABASES="
postgres|PostgreSQL 16|5432|db-postgres|postgres|/opt/db-postgres
dragonfly|DragonflyDB|6379|db-dragonfly|dragonfly|/opt/db-dragonfly
"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✔]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[✘]${NC} $1"; exit 1; }
info()  { echo -e "${BLUE}[●]${NC} $1"; }
header(){ echo -e "\n${BOLD}${CYAN}$1${NC}"; }

confirm() {
    local prompt="${1:-Confirmar?}"
    read -p "$prompt [Y/n] " c
    [[ -z "$c" || "$c" =~ ^[yY]$ ]]
}

has_docker() {
    command -v docker &>/dev/null && docker info &>/dev/null
}

get_container_status() {
    local container="$1"
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "$container" && echo "running" || echo "stopped"
}

parse_db() {
    local db="$1"
    local field="$2"
    echo "$DATABASES" | grep "^$db|" | cut -d'|' -f"$field"
}

db_exists() {
    local db="$1"
    local dir
    dir=$(parse_db "$db" 6)
    [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]
}

get_installed_dbs() {
    local installed=""
    while IFS='|' read -r name display port repo container dir; do
        [ -z "$name" ] && continue
        if [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]; then
            local status
            status=$(get_container_status "$container")
            installed="${installed}${name}|${display}|${port}|${status}|${dir}\n"
        fi
    done <<< "$DATABASES"
    echo -e "$installed"
}

resolve_db_list() {
    local input="$1"
    local dbs=""

    case "$input" in
        all)
            while IFS='|' read -r name _; do
                [ -n "$name" ] && dbs="$dbs $name"
            done <<< "$DATABASES"
            echo "$dbs"
            return
            ;;
    esac

    IFS=',' read -ra choices <<< "$input"
    local idx=1
    while IFS='|' read -r name display port _; do
        [ -z "$name" ] && continue
        for ch in "${choices[@]}"; do
            ch=$(echo "$ch" | tr -d ' ')
            if [ "$ch" = "$idx" ] || [ "$ch" = "$name" ]; then
                dbs="$dbs $name"
            fi
        done
        idx=$((idx + 1))
    done <<< "$DATABASES"

    echo "$dbs"
}

# --- Instalação de Infraestrutura ---

install_infra() {
    header "=== Instalar Infraestrutura ==="
    echo ""
    echo "  Docker Engine + Compose v2"
    echo "  Firewall (UFW)"
    echo "  Swap 1GB"
    echo "  Atualizações automáticas de segurança"
    echo ""

    confirm "Instalar infraestrutura?" || return 0

    echo ""
    echo "--- Atualizando sistema ---"
    apt-get update -y
    apt-get upgrade -y
    apt-get install -y curl git ca-certificates gnupg lsb-release apt-transport-https software-properties-common
    log "Sistema atualizado"

    echo ""
    echo "--- Swap ---"
    if [ ! -f /swapfile ]; then
        fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        log "Swap 1GB criado"
    else
        info "Swap já existe"
    fi

    echo ""
    echo "--- Docker ---"
    if has_docker; then
        info "Docker já instalado e rodando"
    else
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        systemctl enable docker
        systemctl start docker
        log "Docker instalado"
    fi

    echo ""
    echo "--- Firewall ---"
    if command -v ufw &>/dev/null; then
        info "UFW já instalado"
    else
        apt-get install -y ufw
    fi

    if confirm "Liberar portas no firewall? (22 SSH, 5432 PG, 6379 Dragonfly)"; then
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow 22/tcp comment "SSH"
        ufw allow 5432/tcp comment "PostgreSQL"
        ufw allow 6379/tcp comment "DragonflyDB"
        ufw --force enable
        log "Firewall configurado"
    fi

    echo ""
    echo "--- Atualizações automáticas ---"
    apt-get install -y unattended-upgrades
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'UPEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
UPEOF
    log "Unattended-upgrades configurado"

    log "Infraestrutura pronta!"
}

# --- Instalação de Banco ---

install_db() {
    local db="$1"
    local advanced="${2:-false}"
    local display default_port repo container

    display=$(parse_db "$db" 2)
    default_port=$(parse_db "$db" 3)
    repo=$(parse_db "$db" 4)
    container=$(parse_db "$db" 5)

    local dir="/opt/db-${db}"
    local port="$default_port"

    if [ "$advanced" = "true" ]; then
        echo ""
        header "--- $display ---"
        read -p "  Pasta [$dir]: " custom_dir
        [ -n "$custom_dir" ] && dir="$custom_dir"
        read -p "  Porta [$default_port]: " custom_port
        [ -n "$custom_port" ] && port="$custom_port"
    fi

    mkdir -p "$dir"

    if [ -d "$dir/.git" ]; then
        info "Repo existe, atualizando..."
        (cd "$dir" && git pull --quiet)
    else
        info "Baixando $display..."
        git clone --quiet "${GITHUB_BASE}/${repo}.git" "$dir"
    fi

    # Copia .env e configura
    if [ -f "$dir/.env.example" ] && [ ! -f "$dir/.env" ]; then
        cp "$dir/.env.example" "$dir/.env"

        if [ "$db" = "postgres" ]; then
            [ "$port" != "$default_port" ] && sed -i "s/^PG_PORT=.*/PG_PORT=$port/" "$dir/.env"
        elif [ "$db" = "dragonfly" ]; then
            [ "$port" != "$default_port" ] && sed -i "s/^DF_PORT=.*/DF_PORT=$port/" "$dir/.env"
        fi
    fi

    chmod +x "$dir"/*.sh 2>/dev/null || true

    info "Subindo $display..."
    (cd "$dir" && docker compose -f docker-compose.yml up -d 2>&1)

    sleep 3

    local status
    status=$(get_container_status "$container")
    if [ "$status" = "running" ]; then
        log "$display rodando na porta $port"
    else
        warn "$display pode não ter iniciado. Verifique: cd $dir && docker compose logs"
    fi

    if [ -f "$dir/info.sh" ]; then
        bash "$dir/info.sh"
    fi
}

# --- Gerenciamento ---

update_db() {
    local db="$1"
    local dir display
    dir=$(parse_db "$db" 6)
    display=$(parse_db "$db" 2)

    [ -d "$dir/.git" ] || err "Repo não encontrado em $dir"

    info "Atualizando $display..."
    (cd "$dir" && git pull --quiet && docker compose -f docker-compose.yml restart 2>&1)
    log "$display atualizado!"
}

down_db() {
    local db="$1"
    local dir display
    dir=$(parse_db "$db" 6)
    display=$(parse_db "$db" 2)

    (cd "$dir" && docker compose -f docker-compose.yml down --timeout 10 2>&1)
    log "$display parado!"
}

status_db() {
    local db="$1"
    local dir display port container
    dir=$(parse_db "$db" 6)
    display=$(parse_db "$db" 2)
    port=$(parse_db "$db" 3)
    container=$(parse_db "$db" 5)

    echo ""
    header "=== $display ==="
    echo "  Pasta:  $dir"
    echo "  Porta:  $port"

    local st
    st=$(get_container_status "$container")
    if [ "$st" = "running" ]; then
        echo -e "  Status: ${GREEN}running${NC}"
    else
        echo -e "  Status: ${RED}stopped${NC}"
    fi

    if [ "$st" = "running" ] && [ -f "$dir/info.sh" ]; then
        echo ""
        bash "$dir/info.sh"
    fi
}

remove_db() {
    local db="$1"
    local dir display
    dir=$(parse_db "$db" 6)
    display=$(parse_db "$db" 2)

    warn "Isso vai PARAR e REMOVER $display completamente"
    confirm "Tem certeza?" || return 0

    (cd "$dir" && docker compose -f docker-compose.yml down -v --timeout 10 2>&1)
    rm -rf "$dir"
    log "$display removido!"
}

# --- Seleção múltipla ---

ask_select_dbs() {
    header "Selecione banco(s) para instalar:"
    echo ""

    local idx=1
    while IFS='|' read -r name display port _; do
        [ -z "$name" ] && continue
        if db_exists "$name"; then
            echo -e "  [$idx] $display (porta $port) ${GREEN}já instalado${NC}"
        else
            echo "  [$idx] $display (porta $port)"
        fi
        idx=$((idx + 1))
    done <<< "$DATABASES"

    local total=$((idx - 1))
    if [ "$total" -gt 1 ]; then
        echo "  [$((total + 1))] Todos"
        echo ""
        read -p "Escolha (ex: 1 ou 1,$((total + 1)) ou $((total + 1))): " choices
        if [ "$choices" = "$((total + 1))" ]; then
            choices="all"
        fi
    else
        echo ""
        read -p "Escolha (1 para $display): " choices
        choices="1"
    fi

    local selected
    selected=$(resolve_db_list "$choices")

    if [ -z "$(echo "$selected" | tr -d ' ')" ]; then
        warn "Nenhum banco selecionado"
        return 1
    fi

    echo "$selected"
}

show_summary() {
    local dbs="$1"

    header "=== Resumo ==="
    echo ""

    for db in $dbs; do
        local display port dir
        display=$(parse_db "$db" 2)
        port=$(parse_db "$db" 3)
        dir="/opt/db-${db}"
        printf "  %-16s → %-25s (porta %s)\n" "$display" "$dir" "$port"
    done

    echo ""
}

install_multiple() {
    local dbs="$1"
    local advanced="${2:-false}"

    for db in $dbs; do
        echo ""
        install_db "$db" "$advanced"
    done
}

ask_action() {
    local installed
    installed=$(get_installed_dbs)
    local has_installed=false
    [ -n "$(echo "$installed" | tr -d '[:space:]')" ] && has_installed=true

    header "=== Database Toolkit ==="
    echo ""

    # Mostra bancos instalados
    if [ "$has_installed" = "true" ]; then
        echo "  Bancos instalados:"
        while IFS='|' read -r name display port status dir; do
            [ -z "$name" ] && continue
            if [ "$status" = "running" ]; then
                echo -e "    ${GREEN}●${NC} $display (porta $port) — rodando"
            else
                echo -e "    ${RED}●${NC} $display (porta $port) — parado"
            fi
        done <<< "$installed"
        echo ""
    fi

    echo "  Ações:"
    echo "    [1] Adicionar banco(s)"

    if has_docker; then
        echo "    [2] Atualizar banco"
        echo "    [3] Parar banco"
        echo "    [4] Status"
        echo "    [5] Remover banco"
    else
        echo -e "    [2-5] ${YELLOW}(Docker não instalado — instale primeiro com [1])${NC}"
    fi

    echo "    [0] Sair"
    echo ""
    read -p "  Escolha: " action

    echo "$action"
}

# --- Modo direto (args) ---

parse_args() {
    local action="${1:-}"
    shift 2>/dev/null || true
    local args="$*"
    local advanced=false

    # Detecta --advanced
    for arg in $args; do
        if [ "$arg" = "--advanced" ]; then
            advanced=true
            args=$(echo "$args" | sed 's/--advanced//g' | xargs)
        fi
    done

    case "$action" in
        add)
            if [ -z "$args" ]; then
                local selected
                selected=$(ask_select_dbs) || exit 0
                show_summary "$selected"
                confirm || exit 0
                install_multiple "$selected" "$advanced"
                log "Pronto!"
            else
                local dbs=""
                for arg in $args; do
                    if [ "$arg" = "all" ]; then
                        dbs=$(resolve_db_list "all")
                    else
                        local resolved
                        resolved=$(resolve_db_list "$arg")
                        dbs="$dbs $resolved"
                    fi
                done
                dbs=$(echo "$dbs" | xargs)
                show_summary "$dbs"
                confirm || exit 0
                install_multiple "$dbs" "$advanced"
                log "Pronto!"
            fi
            ;;
        update)
            [ -z "$args" ] && err "Uso: $0 update <postgres|dragonfly>"
            for db in $args; do
                update_db "$db"
            done
            ;;
        down)
            [ -z "$args" ] && err "Uso: $0 down <postgres|dragonfly>"
            for db in $args; do
                down_db "$db"
            done
            ;;
        status)
            if [ -z "$args" ]; then
                while IFS='|' read -r name _; do
                    [ -n "$name" ] && db_exists "$name" && status_db "$name"
                done <<< "$DATABASES"
            else
                for db in $args; do
                    status_db "$db"
                done
            fi
            ;;
        remove)
            [ -z "$args" ] && err "Uso: $0 remove <postgres|dragonfly>"
            for db in $args; do
                remove_db "$db"
            done
            ;;
        infra)
            install_infra
            ;;
        *)
            err "Uso:
  $0                         (menu interativo)
  $0 add [db] [--advanced]   adicionar banco(s)
  $0 update <db>             atualizar banco
  $0 down <db>               parar banco
  $0 status [db]             ver status
  $0 remove <db>             remover banco
  $0 infra                   instalar só infraestrutura

Bancos: postgres, dragonfly, all"
            ;;
    esac
}

# --- Menu interativo ---

interactive_menu() {
    while true; do
        local action
        action=$(ask_action)

        case "$action" in
            1)
                local advanced=false
                if has_docker; then
                    echo ""
                    read -p "  Modo avançado? (customizar local/porta) [y/N] " adv
                    [[ "$adv" =~ ^[yY]$ ]] && advanced=true
                fi

                if ! has_docker; then
                    echo ""
                    if confirm "Docker não encontrado. Instalar infraestrutura primeiro?"; then
                        install_infra
                    else
                        warn "Docker é necessário para instalar bancos"
                        continue
                    fi
                fi

                local selected
                selected=$(ask_select_dbs) || continue
                show_summary "$selected"

                if [ "$advanced" = "true" ]; then
                    echo ""
                    for db in $selected; do
                        local display default_port dir="/opt/db-${db}" port="$default_port"
                        display=$(parse_db "$db" 2)
                        default_port=$(parse_db "$db" 3)
                        header "--- $display ---"
                        read -p "  Pasta [$dir]: " custom_dir
                        [ -n "$custom_dir" ] && dir="$custom_dir"
                        read -p "  Porta [$default_port]: " custom_port
                        [ -n "$custom_port" ] && port="$custom_port"
                    done
                fi

                confirm || continue
                install_multiple "$selected" "$advanced"
                log "Pronto!"
                echo ""
                read -p "  Pressione Enter para continuar..."
                ;;
            2)
                local installed
                installed=$(get_installed_dbs)
                if [ -z "$(echo "$installed" | tr -d '[:space:]')" ]; then
                    warn "Nenhum banco instalado"
                    continue
                fi
                echo ""
                local idx=1
                while IFS='|' read -r name display _; do
                    [ -z "$name" ] && continue
                    echo "  [$idx] $display"
                    idx=$((idx + 1))
                done <<< "$installed"
                echo ""
                read -p "  Qual banco? (número): " ch
                local selected_db=""
                idx=1
                while IFS='|' read -r name _; do
                    [ -z "$name" ] && continue
                    [ "$ch" = "$idx" ] && selected_db="$name"
                    idx=$((idx + 1))
                done <<< "$installed"
                [ -n "$selected_db" ] && update_db "$selected_db" || warn "Seleção inválida"
                echo ""
                read -p "  Pressione Enter para continuar..."
                ;;
            3)
                local installed
                installed=$(get_installed_dbs)
                if [ -z "$(echo "$installed" | tr -d '[:space:]')" ]; then
                    warn "Nenhum banco instalado"
                    continue
                fi
                echo ""
                local idx=1
                while IFS='|' read -r name display status _; do
                    [ -z "$name" ] && continue
                    local icon="●"
                    [ "$status" = "running" ] && icon="●"
                    echo "  [$idx] $display ($status)"
                    idx=$((idx + 1))
                done <<< "$installed"
                echo ""
                read -p "  Qual banco parar? (número): " ch
                local selected_db=""
                idx=1
                while IFS='|' read -r name _; do
                    [ -z "$name" ] && continue
                    [ "$ch" = "$idx" ] && selected_db="$name"
                    idx=$((idx + 1))
                done <<< "$installed"
                [ -n "$selected_db" ] && down_db "$selected_db" || warn "Seleção inválida"
                echo ""
                read -p "  Pressione Enter para continuar..."
                ;;
            4)
                while IFS='|' read -r name _; do
                    [ -n "$name" ] && db_exists "$name" && status_db "$name"
                done <<< "$DATABASES"
                echo ""
                read -p "  Pressione Enter para continuar..."
                ;;
            5)
                local installed
                installed=$(get_installed_dbs)
                if [ -z "$(echo "$installed" | tr -d '[:space:]')" ]; then
                    warn "Nenhum banco instalado"
                    continue
                fi
                echo ""
                local idx=1
                while IFS='|' read -r name display _; do
                    [ -z "$name" ] && continue
                    echo "  [$idx] $display"
                    idx=$((idx + 1))
                done <<< "$installed"
                echo ""
                read -p "  Qual banco remover? (número): " ch
                local selected_db=""
                idx=1
                while IFS='|' read -r name _; do
                    [ -z "$name" ] && continue
                    [ "$ch" = "$idx" ] && selected_db="$name"
                    idx=$((idx + 1))
                done <<< "$installed"
                [ -n "$selected_db" ] && remove_db "$selected_db" || warn "Seleção inválida"
                echo ""
                read -p "  Pressione Enter para continuar..."
                ;;
            0)
                echo ""
                log "Até mais!"
                exit 0
                ;;
            *)
                warn "Opção inválida"
                ;;
        esac
    done
}

# --- Main ---

main() {
    if [ "$(id -u)" -ne 0 ]; then
        err "Execute como root: sudo $0"
    fi

    if [ -n "${1:-}" ]; then
        parse_args "$@"
        exit 0
    fi

    interactive_menu
}

main "$@"
