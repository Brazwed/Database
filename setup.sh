#!/usr/bin/env bash

# ============================================================
# Database Toolkit - Setup
# ============================================================

GITHUB_BASE="${GITHUB_BASE:-https://github.com/Brazwed}"

DATABASES="postgres|PostgreSQL 16|5432|db-postgres|postgres|/opt/db-postgres
dragonfly|DragonflyDB|6379|db-dragonfly|dragonfly|/opt/db-dragonfly"

# Cores
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'
C='\033[0;36m'; BD='\033[1m'; NC='\033[0m'

log()  { echo -e "${G}[✔]${NC} $1"; }
warn() { echo -e "${Y}[!]${NC} $1"; }
err()  { echo -e "${R}[✘]${NC} $1"; exit 1; }
info() { echo -e "${B}[●]${NC} $1"; }

confirm() {
    read -rp "${1:-Confirmar?} [Y/n] " c
    [[ -z "$c" || "$c" =~ ^[yY]$ ]]
}

pause() {
    read -rp "  Pressione Enter..." _
}

has_docker() {
    command -v docker &>/dev/null && docker info &>/dev/null 2>&1
}

get_container_status() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "$1" && echo "running" || echo "stopped"
}

parse_db() {
    echo "$DATABASES" | grep "^${1}|" | cut -d'|' -f"$2"
}

db_exists() {
    local dir
    dir=$(parse_db "$1" 6)
    [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]
}

get_installed_list() {
    local result=""
    while IFS='|' read -r name display port repo container dir; do
        [ -z "$name" ] && continue
        if [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]; then
            local st
            st=$(get_container_status "$container")
            result="${result}${name}|${display}|${port}|${st}|${dir}\n"
        fi
    done <<< "$DATABASES"
    printf '%b' "$result"
}

# ============================================================
# INSTALAÇÃO DE INFRA
# ============================================================

install_infra() {
    echo ""
    echo -e "${BD}${C}=== Instalar Infraestrutura ===${NC}"
    echo ""
    echo "  - Docker Engine + Compose v2"
    echo "  - Firewall (UFW)"
    echo "  - Swap 1GB"
    echo "  - Updates automáticos de segurança"
    echo ""
    confirm "Instalar?" || return 0

    echo ""
    echo -e "${BD}--- Atualizando sistema ---${NC}"
    apt-get update -y && apt-get upgrade -y
    apt-get install -y curl git ca-certificates gnupg lsb-release apt-transport-https software-properties-common
    log "Sistema atualizado"

    echo ""
    echo -e "${BD}--- Swap ---${NC}"
    if [ ! -f /swapfile ]; then
        fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024
        chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        log "Swap 1GB criado"
    else
        info "Swap já existe"
    fi

    echo ""
    echo -e "${BD}--- Docker ---${NC}"
    if has_docker; then
        info "Docker já instalado"
    else
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        systemctl enable docker && systemctl start docker
        log "Docker instalado"
    fi

    echo ""
    echo -e "${BD}--- Firewall ---${NC}"
    command -v ufw &>/dev/null || apt-get install -y ufw

    if confirm "Liberar portas? (22 SSH, 5432 PG, 6379 Dragonfly)"; then
        ufw default deny incoming && ufw default allow outgoing
        ufw allow 22/tcp comment "SSH"
        ufw allow 5432/tcp comment "PostgreSQL"
        ufw allow 6379/tcp comment "DragonflyDB"
        ufw --force enable
        log "Firewall configurado"
    fi

    echo ""
    echo -e "${BD}--- Updates automáticos ---${NC}"
    apt-get install -y unattended-upgrades
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
    log "Infraestrutura pronta!"
}

# ============================================================
# INSTALAÇÃO DE BANCO
# ============================================================

install_db() {
    local db="$1" advanced="${2:-false}"
    local display default_port repo container

    display=$(parse_db "$db" 2)
    default_port=$(parse_db "$db" 3)
    repo=$(parse_db "$db" 4)
    container=$(parse_db "$db" 5)

    local dir="/opt/db-${db}" port="$default_port"

    if [ "$advanced" = "true" ]; then
        echo ""
        echo -e "${BD}${C}--- $display ---${NC}"
        read -rp "  Pasta [$dir]: " x; [ -n "$x" ] && dir="$x"
        read -rp "  Porta [$default_port]: " x; [ -n "$x" ] && port="$x"
    fi

    mkdir -p "$dir"

    if [ -d "$dir/.git" ]; then
        info "Atualizando repo..."
        (cd "$dir" && git pull --quiet) || true
    else
        info "Baixando $display..."
        git clone --quiet "${GITHUB_BASE}/${repo}.git" "$dir"
    fi

    if [ -f "$dir/.env.example" ] && [ ! -f "$dir/.env" ]; then
        cp "$dir/.env.example" "$dir/.env"
        [ "$db" = "postgres" ] && [ "$port" != "$default_port" ] && sed -i "s/^PG_PORT=.*/PG_PORT=$port/" "$dir/.env"
        [ "$db" = "dragonfly" ] && [ "$port" != "$default_port" ] && sed -i "s/^DF_PORT=.*/DF_PORT=$port/" "$dir/.env"
    fi

    chmod +x "$dir"/*.sh 2>/dev/null || true

    info "Subindo $display..."
    (cd "$dir" && docker compose up -d 2>&1)

    sleep 3

    local st
    st=$(get_container_status "$container")
    if [ "$st" = "running" ]; then
        log "$display rodando na porta $port"
    else
        warn "$display pode não ter iniciado"
    fi

    [ -f "$dir/info.sh" ] && bash "$dir/info.sh"
}

# ============================================================
# GERENCIAMENTO
# ============================================================

update_db() {
    local dir display
    dir=$(parse_db "$1" 6); display=$(parse_db "$1" 2)
    [ -d "$dir/.git" ] || err "Repo não encontrado em $dir"
    info "Atualizando $display..."
    (cd "$dir" && git pull --quiet && docker compose restart 2>&1)
    log "$display atualizado!"
}

down_db() {
    local dir display
    dir=$(parse_db "$1" 6); display=$(parse_db "$1" 2)
    (cd "$dir" && docker compose down --timeout 10 2>&1)
    log "$display parado!"
}

status_db() {
    local dir display port container
    dir=$(parse_db "$1" 6); display=$(parse_db "$1" 2)
    port=$(parse_db "$1" 3); container=$(parse_db "$1" 5)

    echo ""
    echo -e "${BD}${C}=== $display ===${NC}"
    echo "  Pasta:  $dir"
    echo "  Porta:  $port"

    local st
    st=$(get_container_status "$container")
    if [ "$st" = "running" ]; then
        echo -e "  Status: ${G}running${NC}"
        [ -f "$dir/info.sh" ] && echo "" && bash "$dir/info.sh"
    else
        echo -e "  Status: ${R}stopped${NC}"
    fi
}

remove_db() {
    local dir display
    dir=$(parse_db "$1" 6); display=$(parse_db "$1" 2)
    warn "Isso vai PARAR e REMOVER $display"
    confirm "Tem certeza?" || return 0
    (cd "$dir" && docker compose down -v --timeout 10 2>&1)
    rm -rf "$dir"
    log "$display removido!"
}

# ============================================================
# SELEÇÃO (stdout = dados, stderr = display)
# ============================================================

resolve_db_list() {
    local input="$1" dbs=""

    if [ "$input" = "all" ]; then
        while IFS='|' read -r name _; do
            [ -n "$name" ] && dbs="$dbs $name"
        done <<< "$DATABASES"
        echo "$dbs"
        return 0
    fi

    IFS=',' read -ra choices <<< "$input"
    local idx=1
    while IFS='|' read -r name _; do
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

select_db_to_install() {
    # Menu → stderr (usuário vê)
    echo "" >&2
    echo -e "${BD}${C}Selecione banco(s):${NC}" >&2
    echo "" >&2

    local idx=1
    while IFS='|' read -r name display port _; do
        [ -z "$name" ] && continue
        if db_exists "$name"; then
            echo -e "  [$idx] $display (porta $port) ${G}já instalado${NC}" >&2
        else
            echo "  [$idx] $display (porta $port)" >&2
        fi
        idx=$((idx + 1))
    done <<< "$DATABASES"

    local total=$((idx - 1))
    local prompt

    if [ "$total" -gt 1 ]; then
        echo "  [$((total + 1))] Todos" >&2
        echo "" >&2
        prompt="Escolha (ex: 1,2 ou 3)"
    else
        echo "" >&2
        prompt="Escolha (1 para instalar)"
    fi

    read -rp "$prompt: " choices >&2

    if [ "$total" -gt 1 ] && [ "$choices" = "$((total + 1))" ]; then
        choices="all"
    fi
    [ -z "$choices" ] && choices="1"

    # Seleção → stdout (capturado)
    resolve_db_list "$choices"
}

select_installed_db() {
    local prompt="$1"
    local installed_raw
    installed_raw=$(get_installed_list)

    if [ -z "$(echo "$installed_raw" | tr -d '[:space:]')" ]; then
        warn "Nenhum banco instalado" >&2
        return 1
    fi

    echo "" >&2
    local idx=1
    local names=()
    while IFS='|' read -r name display _; do
        [ -z "$name" ] && continue
        echo "  [$idx] $display" >&2
        names+=("$name")
        idx=$((idx + 1))
    done <<< "$installed_raw"

    echo "" >&2
    read -rp "  $prompt (número): " ch >&2

    if [ "$ch" -ge 1 ] 2>/dev/null && [ "$ch" -le "${#names[@]}" ] 2>/dev/null; then
        echo "${names[$((ch - 1))]}"  # stdout
        return 0
    fi

    warn "Seleção inválida" >&2
    return 1
}

show_summary() {
    local dbs="$1"

    echo ""
    echo -e "${BD}${C}=== Resumo ===${NC}"
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

# ============================================================
# MENU PRINCIPAL
# ============================================================

show_main_menu() {
    local installed_raw has_installed=false
    installed_raw=$(get_installed_list)
    [ -n "$(echo "$installed_raw" | tr -d '[:space:]')" ] && has_installed=true

    clear
    echo ""
    echo -e "${BD}${C}╔══════════════════════════════════════╗${NC}"
    echo -e "${BD}${C}║       Database Toolkit               ║${NC}"
    echo -e "${BD}${C}╚══════════════════════════════════════╝${NC}"
    echo ""

    if [ "$has_installed" = "true" ]; then
        echo -e "  ${BD}Bancos instalados:${NC}"
        while IFS='|' read -r name display port status dir; do
            [ -z "$name" ] && continue
            if [ "$status" = "running" ]; then
                echo -e "    ${G}●${NC} $display (porta $port) — rodando"
            else
                echo -e "    ${R}●${NC} $display (porta $port) — parado"
            fi
        done <<< "$installed_raw"
        echo ""
    fi

    echo -e "  ${BD}Ações:${NC}"
    echo "    [1] Adicionar banco(s)"

    if has_docker; then
        echo "    [2] Atualizar banco"
        echo "    [3] Parar banco"
        echo "    [4] Status"
        echo "    [5] Remover banco"
    else
        echo -e "    [2-5] ${Y}(Docker não instalado — use [1])${NC}"
    fi

    echo "    [0] Sair"
    echo ""
}

# ============================================================
# MODO DIRETO (ARGS)
# ============================================================

parse_args() {
    local action="${1:-}"
    shift 2>/dev/null || true
    local args="$*"
    local advanced=false

    for arg in $args; do
        if [ "$arg" = "--advanced" ]; then
            advanced=true
            args=$(echo "$args" | sed 's/--advanced//g' | xargs)
        fi
    done

    case "$action" in
        add)
            local selected
            if [ -z "$args" ]; then
                selected=$(select_db_to_install) || exit 0
            else
                local dbs=""
                for arg in $args; do
                    [ "$arg" = "all" ] && dbs=$(resolve_db_list "all") && break
                    local resolved; resolved=$(resolve_db_list "$arg")
                    dbs="$dbs $resolved"
                done
                selected=$(echo "$dbs" | xargs)
            fi
            show_summary "$selected"
            confirm || exit 0
            for db in $selected; do install_db "$db" "$advanced"; done
            log "Pronto!"
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
                while IFS='|' read -r name _; do
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
  $0                         menu interativo
  $0 add [db] [--advanced]   adicionar banco(s)
  $0 update <db>             atualizar banco
  $0 down <db>               parar banco
  $0 status [db]             ver status
  $0 remove <db>             remover banco
  $0 infra                   instalar infraestrutura

Bancos: postgres, dragonfly, all"
            ;;
    esac
}

# ============================================================
# LOOP INTERATIVO
# ============================================================

interactive_menu() {
    while true; do
        show_main_menu
        read -rp "  Escolha: " choice

        case "$choice" in
            1)
                local advanced=false
                if has_docker; then
                    read -rp "  Avançado? (customizar local/porta) [y/N] " adv
                    [[ "$adv" =~ ^[yY]$ ]] && advanced=true
                else
                    echo ""
                    if confirm "Docker não encontrado. Instalar infraestrutura?"; then
                        install_infra
                    else
                        warn "Docker é necessário"
                        pause; continue
                    fi
                fi

                local selected
                selected=$(select_db_to_install) || { pause; continue; }
                show_summary "$selected"
                confirm || { pause; continue; }

                for db in $selected; do
                    install_db "$db" "$advanced"
                done
                log "Pronto!"
                pause
                ;;
            2)
                local db_name
                db_name=$(select_installed_db "Qual banco atualizar?") || { pause; continue; }
                update_db "$db_name"
                pause
                ;;
            3)
                local db_name
                db_name=$(select_installed_db "Qual banco parar?") || { pause; continue; }
                down_db "$db_name"
                pause
                ;;
            4)
                while IFS='|' read -r name _; do
                    [ -n "$name" ] && db_exists "$name" && status_db "$name"
                done <<< "$DATABASES"
                pause
                ;;
            5)
                local db_name
                db_name=$(select_installed_db "Qual banco remover?") || { pause; continue; }
                remove_db "$db_name"
                pause
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

# ============================================================
# MAIN
# ============================================================

main() {
    [ "$(id -u)" -ne 0 ] && err "Execute como root: sudo $0"

    if [ -n "${1:-}" ]; then
        parse_args "$@"
        exit 0
    fi

    interactive_menu
}

main "$@"
