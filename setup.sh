#!/usr/bin/env bash

# ============================================================
# Database Toolkit - Setup
# Bridge: provisiona VPS e gerencia bancos individuais
# ============================================================

# --- Configuração (edite aqui se fizer fork) ---
GITHUB_BASE="${GITHUB_BASE:-https://github.com/Brazwed}"

# Formato: name|display|port|repo|container|dir
DATABASES="postgres|PostgreSQL 16|5432|db-postgres|postgres|/opt/db-postgres
dragonfly|DragonflyDB|6379|db-dragonfly|dragonfly|/opt/db-dragonfly"

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

confirm() {
    local prompt="${1:-Confirmar?}"
    read -rp "$prompt [Y/n] " c
    [[ -z "$c" || "$c" =~ ^[yY]$ ]]
}

has_docker() {
    command -v docker &>/dev/null && docker info &>/dev/null 2>&1
}

get_container_status() {
    local container="$1"
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "$container" && echo "running" || echo "stopped"
}

parse_db() {
    local db="$1"
    local field="$2"
    echo "$DATABASES" | grep "^${db}|" | cut -d'|' -f"$field"
}

db_exists() {
    local db="$1"
    local dir
    dir=$(parse_db "$db" 6)
    [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]
}

get_installed_list() {
    local result=""
    while IFS='|' read -r name display port repo container dir; do
        [ -z "$name" ] && continue
        [ -z "$dir" ] && continue
        if [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]; then
            local st
            st=$(get_container_status "$container")
            result="${result}${name}|${display}|${port}|${st}|${dir}
"
        fi
    done <<< "$DATABASES"
    printf '%s' "$result"
}

# --- Instalação de Infraestrutura ---

install_infra() {
    echo ""
    echo -e "${BOLD}${CYAN}=== Instalar Infraestrutura ===${NC}"
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
        echo -e "${BOLD}${CYAN}--- $display ---${NC}"
        read -rp "  Pasta [$dir]: " custom_dir
        [ -n "$custom_dir" ] && dir="$custom_dir"
        read -rp "  Porta [$default_port]: " custom_port
        [ -n "$custom_port" ] && port="$custom_port"
    fi

    mkdir -p "$dir"

    if [ -d "$dir/.git" ]; then
        info "Repo existe, atualizando..."
        (cd "$dir" && git pull --quiet) || true
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
    echo -e "${BOLD}${CYAN}=== $display ===${NC}"
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

resolve_db_list() {
    local input="$1"
    local dbs=""

    if [ "$input" = "all" ]; then
        while IFS='|' read -r name _rest; do
            [ -n "$name" ] && dbs="$dbs $name"
        done <<< "$DATABASES"
        echo "$dbs"
        return 0
    fi

    local OLDIFS="$IFS"
    IFS=',' read -ra choices <<< "$input"
    IFS="$OLDIFS"

    local idx=1
    while IFS='|' read -r name _rest; do
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

show_summary() {
    local dbs="$1"

    echo ""
    echo -e "${BOLD}${CYAN}=== Resumo ===${NC}"
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

# --- Menu principal ---

show_main_menu() {
    local installed_raw
    installed_raw=$(get_installed_list)
    local has_installed=false
    if [ -n "$(echo "$installed_raw" | tr -d '[:space:]')" ]; then
        has_installed=true
    fi

    echo ""
    echo -e "${BOLD}${CYAN}=== Database Toolkit ===${NC}"
    echo ""

    # Mostra bancos instalados
    if [ "$has_installed" = "true" ]; then
        echo "  Bancos instalados:"
        while IFS='|' read -r name display port status dir; do
            [ -z "$name" ] && continue
            [ -z "$display" ] && continue
            if [ "$status" = "running" ]; then
                echo -e "    ${GREEN}●${NC} $display (porta $port) — rodando"
            else
                echo -e "    ${RED}●${NC} $display (porta $port) — parado"
            fi
        done <<< "$installed_raw"
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
        echo -e "    [2-5] ${YELLOW}(Docker não instalado — instale com [1])${NC}"
    fi

    echo "    [0] Sair"
    echo ""
}

select_installed_db() {
    local prompt="$1"
    local installed_raw
    installed_raw=$(get_installed_list)

    if [ -z "$(echo "$installed_raw" | tr -d '[:space:]')" ]; then
        warn "Nenhum banco instalado"
        return 1
    fi

    echo ""
    local idx=1
    local names=()
    while IFS='|' read -r name display _rest; do
        [ -z "$name" ] && continue
        [ -z "$display" ] && continue
        echo "  [$idx] $display"
        names+=("$name")
        idx=$((idx + 1))
    done <<< "$installed_raw"

    echo ""
    read -rp "  $prompt (número): " ch

    if [ "$ch" -ge 1 ] 2>/dev/null && [ "$ch" -le "${#names[@]}" ] 2>/dev/null; then
        echo "${names[$((ch - 1))]}"
        return 0
    fi

    warn "Seleção inválida"
    return 1
}

select_db_to_install() {
    echo ""
    echo -e "${BOLD}${CYAN}Selecione banco(s) para instalar:${NC}"
    echo ""

    local idx=1
    while IFS='|' read -r name display port _rest; do
        [ -z "$name" ] && continue
        [ -z "$display" ] && continue
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
        read -rp "Escolha (ex: 1 ou 1,2 ou 3): " choices
        if [ "$choices" = "$((total + 1))" ]; then
            choices="all"
        fi
    else
        echo ""
        read -rp "Escolha (1 para instalar): " choices
        [ -z "$choices" ] && choices="1"
    fi

    local selected
    selected=$(resolve_db_list "$choices")

    if [ -z "$(echo "$selected" | tr -d ' ')" ]; then
        warn "Nenhum banco selecionado"
        return 1
    fi

    echo "$selected"
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
                selected=$(select_db_to_install) || exit 0
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
            for db in $args; do update_db "$db"; done
            ;;
        down)
            [ -z "$args" ] && err "Uso: $0 down <postgres|dragonfly>"
            for db in $args; do down_db "$db"; done
            ;;
        status)
            if [ -z "$args" ]; then
                while IFS='|' read -r name _rest; do
                    [ -n "$name" ] && db_exists "$name" && status_db "$name"
                done <<< "$DATABASES"
            else
                for db in $args; do status_db "$db"; done
            fi
            ;;
        remove)
            [ -z "$args" ] && err "Uso: $0 remove <postgres|dragonfly>"
            for db in $args; do remove_db "$db"; done
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

# --- Loop interativo ---

interactive_menu() {
    while true; do
        show_main_menu
        read -rp "  Escolha: " choice

        case "$choice" in
            1)
                # Adicionar banco
                local advanced=false
                if has_docker; then
                    read -rp "  Modo avançado? (customizar local/porta) [y/N] " adv
                    [[ "$adv" =~ ^[yY]$ ]] && advanced=true
                else
                    echo ""
                    if confirm "Docker não encontrado. Instalar infraestrutura primeiro?"; then
                        install_infra
                    else
                        warn "Docker é necessário para instalar bancos"
                        continue
                    fi
                fi

                local selected
                selected=$(select_db_to_install) || continue
                show_summary "$selected"

                if [ "$advanced" = "true" ]; then
                    echo ""
                    for db in $selected; do
                        local display default_port dir="/opt/db-${db}" port="$default_port"
                        display=$(parse_db "$db" 2)
                        default_port=$(parse_db "$db" 3)
                        echo -e "${BOLD}${CYAN}--- $display ---${NC}"
                        read -rp "  Pasta [$dir]: " custom_dir
                        [ -n "$custom_dir" ] && dir="$custom_dir"
                        read -rp "  Porta [$default_port]: " custom_port
                        [ -n "$custom_port" ] && port="$custom_port"
                    done
                fi

                confirm || continue
                install_multiple "$selected" "$advanced"
                log "Pronto!"
                echo ""
                read -rp "  Pressione Enter para continuar..." _
                ;;
            2)
                local db_name
                db_name=$(select_installed_db "Qual banco atualizar?") || continue
                update_db "$db_name"
                echo ""
                read -rp "  Pressione Enter para continuar..." _
                ;;
            3)
                local db_name
                db_name=$(select_installed_db "Qual banco parar?") || continue
                down_db "$db_name"
                echo ""
                read -rp "  Pressione Enter para continuar..." _
                ;;
            4)
                while IFS='|' read -r name _rest; do
                    [ -n "$name" ] && db_exists "$name" && status_db "$name"
                done <<< "$DATABASES"
                echo ""
                read -rp "  Pressione Enter para continuar..." _
                ;;
            5)
                local db_name
                db_name=$(select_installed_db "Qual banco remover?") || continue
                remove_db "$db_name"
                echo ""
                read -rp "  Pressione Enter para continuar..." _
                ;;
            0)
                echo ""
                log "Até mais!"
                exit 0
                ;;
            *)
                warn "Opção inválida: $choice"
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
