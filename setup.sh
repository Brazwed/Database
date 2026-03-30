#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Database Toolkit - Setup
# Bridge: provisiona VPS e gerencia bancos individuais
# ============================================================

# --- Configuração ---
GITHUB_BASE="https://github.com/brazwed"
INSTALL_DIR="/opt"

# Formato: name|display|port|repo|container|dir
DATABASES="
postgres|PostgreSQL|5432|db-postgres|postgres|/opt/db-postgres
dragonfly|DragonflyDB|6379|db-dragonfly|dragonfly|/opt/db-dragonfly
"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✔]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[✘]${NC} $1"; exit 1; }
info()  { echo -e "${BLUE}[●]${NC} $1"; }

confirm() {
    read -p "$1 [y/N] " c
    [[ "$c" =~ ^[yY]$ ]] || return 1
    return 0
}

get_container_status() {
    local container="$1"
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$" && echo "running" || echo "stopped"
}

is_port_free() {
    local port="$1"
    ! ss -tln 2>/dev/null | grep -q ":$port " && ! ss -uln 2>/dev/null | grep -q ":$port "
}

ask_install_location() {
    local db="$1"
    local default_dir="$2"
    local user_home="${HOME:-/root}"

    echo ""
    echo "Onde instalar $db?"
    echo "  [1] /opt/db-${db}             (padrão)"
    echo "  [2] $user_home/db-${db}       (home)"
    echo "  [3] /var/lib/db-${db}         (var/lib)"
    echo "  [4] Outro caminho..."
    echo ""
    read -p "Escolha (1-4): " loc_choice

    case "$loc_choice" in
        1) echo "/opt/db-${db}" ;;
        2) echo "$user_home/db-${db}" ;;
        3) echo "/var/lib/db-${db}" ;;
        4)
            read -p "Caminho completo: " custom_dir
            echo "$custom_dir"
            ;;
        *) echo "$default_dir" ;;
    esac
}

ask_port() {
    local db="$1"
    local default_port="$2"

    while true; do
        echo ""
        echo "Porta externa para $db? (padrão: $default_port)"
        read -p "> " port_input

        local port="${port_input:-$default_port}"

        if ! [[ "$port" =~ ^[0-9]+$ ]]; then
            warn "Porta deve ser número"
            continue
        fi

        if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
            warn "Porta deve ser entre 1 e 65535"
            continue
        fi

        if is_port_free "$port"; then
            echo "$port"
            return 0
        else
            warn "Porta $port já está em uso!"
            read -p "Tentar outra? [y/N]: " try_again
            [[ "$try_again" =~ ^[yY]$ ]] || return 1
        fi
    done
}

parse_db() {
    local db="$1"
    local field="$2"
    echo "$DATABASES" | grep "^$db|" | cut -d'|' -f"$field"
}

detect_installed() {
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

# --- Ações de Infraestrutura ---

install_infra() {
    info "=== Instalando Infraestrutura ==="
    echo ""
    echo "Isso inclui:"
    echo "  - Docker Engine + Compose v2"
    echo "  - Firewall (UFW)"
    echo "  - Swap 1GB"
    echo "  - Updates automáticos"
    echo ""

    confirm "Instalar?" || return 0

    # System update
    echo ""
    echo "--- Atualizando sistema ---"
    apt-get update -y
    apt-get upgrade -y
    apt-get install -y curl git ca-certificates gnupg lsb-release apt-transport-https software-properties-common
    log "Sistema atualizado"

    # Swap
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

    # Docker
    echo ""
    echo "--- Docker ---"
    if command -v docker &>/dev/null; then
        info "Docker já instalado"
    else
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        log "Docker instalado"
    fi

    systemctl enable docker
    systemctl start docker

    # Firewall
    echo ""
    echo "--- Firewall ---"
    if command -v ufw &>/dev/null; then
        info "UFW já instalado"
    else
        apt-get install -y ufw
    fi

    read -p "Liberar portas no firewall? (22 SSH, 5432 PG, 6379 Redis) [y/N] " fw_confirm
    if [[ "$fw_confirm" =~ ^[yY]$ ]]; then
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow 22/tcp comment "SSH"
        ufw allow 5432/tcp comment "PostgreSQL"
        ufw allow 6379/tcp comment "DragonflyDB/Redis"
        ufw --force enable
        log "Firewall configurado"
    fi

    # Unattended upgrades
    echo ""
    echo "--- Updates automáticos ---"
    apt-get install -y unattended-upgrades
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'UPEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
UPEOF
    log "Unattended-upgrades configurado"

    log "Infraestrutura pronta!"
}

# --- Ações de Banco ---

install_db() {
    local db="$1"
    local display default_port repo container

    display=$(parse_db "$db" 2)
    default_port=$(parse_db "$db" 3)
    repo=$(parse_db "$db" 4)
    container=$(parse_db "$db" 5)

    local default_dir="/opt/db-${db}"
    local dir
    dir=$(ask_install_location "$db" "$default_dir")

    local port
    port=$(ask_port "$db" "$default_port")

    info "=== Instalando $display ==="
    echo "Local: $dir"
    echo "Porta: $port"
    echo ""

    mkdir -p "$dir"

    if [ -d "$dir/.git" ]; then
        cd "$dir"
        info "Repo existe, atualizando..."
        git pull
    else
        cd "$(dirname "$dir")"
        info "Baixando repo..."
        git clone "${GITHUB_BASE}/${repo}.git" "$(basename "$dir")"
        cd "$dir"
    fi

    # Copia .env e configura porta
    if [ -f "$dir/.env.example" ] && [ ! -f "$dir/.env" ]; then
        cp "$dir/.env.example" "$dir/.env"

        if [ "$db" = "postgres" ]; then
            sed -i "s/^PG_PORT=.*/PG_PORT=$port/" "$dir/.env"
        elif [ "$db" = "dragonfly" ]; then
            sed -i "s/^DF_PORT=.*/DF_PORT=$port/" "$dir/.env"
        fi
        log "Arquivo .env configurado com porta $port"
    fi

    chmod +x "$dir"/*.sh 2>/dev/null || true

    info "Subindo container..."
    docker compose up -d

    sleep 2

    local status
    status=$(get_container_status "$container")
    if [ "$status" = "running" ]; then
        log "$display rodando na porta $port"
    else
        warn "$display pode não ter iniciado. Verifique: docker compose ps"
    fi

    if [ -f "$dir/info.sh" ]; then
        bash "$dir/info.sh"
    fi
}

update_db() {
    local db="$1"
    local dir display

    dir=$(parse_db "$db" 6)
    display=$(parse_db "$db" 2)

    [ -d "$dir/.git" ] || err "Repo não encontrado em $dir"

    cd "$dir"
    info "Atualizando $display..."
    git pull
    docker compose restart
    log "$display atualizado!"
}

redeploy_db() {
    local db="$1"
    local dir display

    dir=$(parse_db "$db" 6)
    display=$(parse_db "$db" 2)

    cd "$dir"
    info "Redeploying $display..."
    docker compose down
    docker compose up -d
    log "$display redeployado!"
}

down_db() {
    local db="$1"
    local dir display

    dir=$(parse_db "$db" 6)
    display=$(parse_db "$db" 2)

    cd "$dir"
    docker compose down
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
    echo "=== $display ==="
    echo "Pasta: $dir"
    echo "Porta: $port"

    local st
    st=$(get_container_status "$container")
    echo "Status: $st"

    if [ "$st" = "running" ] && [ -f "$dir/info.sh" ]; then
        bash "$dir/info.sh"
    fi

    docker compose -f "$dir/docker-compose.yml" ps 2>/dev/null
}

uninstall_db() {
    local db="$1"
    local dir display

    dir=$(parse_db "$db" 6)
    display=$(parse_db "$db" 2)

    warn "Isso vai PARAR e REMOVER o container do $display"
    confirm "Tem certeza?" || return 0

    cd "$dir"
    docker compose down -v
    rm -rf "$dir"
    log "$display removido!"
}

# --- Menu ---

show_menu() {
    echo ""
    echo "Qual banco instalar?"
    echo "  1) PostgreSQL"
    echo "  2) DragonflyDB"
    echo ""
    read -p "Escolha (1/2): " ch

    case "$ch" in
        1) DB_CHOICE="postgres" ;;
        2) DB_CHOICE="dragonfly" ;;
        *) err "Inválido" ;;
    esac
}

main() {
    if [ "$(id -u)" -ne 0 ]; then
        err "Execute como root: sudo $0"
    fi

    echo ""
    echo "========================================="
    echo "   Database Toolkit - Setup"
    echo "========================================="

    local detected
    detected=$(detect_installed)

    echo ""
    echo "=== Bancos Instalados ==="
    if [ -n "$detected" ]; then
        while IFS='|' read -r name display port status dir; do
            [ -z "$name" ] && continue
            local icon="❌"
            [ "$status" = "running" ] && icon="✅"
            echo "  $icon $display (porta $port) - $status"
        done <<< "$detected"
    else
        info "Nenhum banco instalado"
    fi

    echo ""
    echo "=== Ações Disponíveis ==="
    echo ""
    echo "  [N]ova VPS  - Instalar Docker + Firewall + Swap + banco"
    echo "  [I]fra      - Instalar APENAS infraestrutura"
    echo "  [A]dd       - Instalar NOVO banco (já com Docker)"

    if [ -n "$detected" ]; then
        echo "  [U]pdate    - Atualizar banco (git pull + restart)"
        echo "  [R]eploy    - Rebuild (down + up)"
        echo "  [D]own      - Parar container"
        echo "  [S]tatus    - Ver status e info"
        echo "  [X] uninstall - Remover banco"
    fi

    echo ""
    read -p "Escolha uma ação: " action

    action=$(echo "$action" | tr '[:upper:]' '[:lower:]')

    case "$action" in
        n|nova)
            show_menu
            warn "Instalar Docker + Firewall + Swap + $DB_CHOICE?"
            confirm "Confirmar?" || exit 0
            install_infra
            install_db "$DB_CHOICE"
            log "Tudo pronto!"
            ;;
        i|infra)
            install_infra
            log "Infraestrutura instalada!"
            ;;
        a|add)
            show_menu
            warn "Instalar $DB_CHOICE?"
            confirm "Confirmar?" || exit 0
            install_db "$DB_CHOICE"
            log "$DB_CHOICE instalado!"
            ;;
        u|update)
            read -p "Qual banco? (postgres/dragonfly): " db_name
            update_db "$db_name"
            ;;
        r|redeploy)
            read -p "Qual banco? (postgres/dragonfly): " db_name
            redeploy_db "$db_name"
            ;;
        d|down)
            read -p "Qual banco? (postgres/dragonfly): " db_name
            down_db "$db_name"
            ;;
        s|status)
            read -p "Qual banco? (postgres/dragonfly): " db_name
            status_db "$db_name"
            ;;
        x|uninstall)
            read -p "Qual banco? (postgres/dragonfly): " db_name
            uninstall_db "$db_name"
            ;;
        *)
            err "Ação inválida"
            ;;
    esac
}

main "$@"
