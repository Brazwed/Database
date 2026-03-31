#!/usr/bin/env bash

# ============================================================
# Database Toolkit - Setup
# Único ponto de entrada pra tudo
# ============================================================

GITHUB_BASE="${GITHUB_BASE:-https://github.com/Brazwed}"
BACKUP_DIR="${HOME}/.db-toolkit/backups"

DATABASES="postgres|PostgreSQL 16|5432|db-postgres|postgres|/opt/db-postgres
dragonfly|DragonflyDB|6379|db-dragonfly|dragonfly|/opt/db-dragonfly"

FW_TYPE="none"
FW_ACTIVE=false

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

get_compose_file() {
    local db="$1"
    local dir
    dir=$(parse_db "$db" 6)
    echo "$dir/docker-compose.yml"
}

# ============================================================
# DETECÇÃO
# ============================================================

detect_firewall() {
    FW_TYPE="none"
    FW_ACTIVE=false

    if command -v ufw &>/dev/null; then
        if ufw status 2>/dev/null | head -1 | grep -q "active"; then
            FW_TYPE="ufw"
            FW_ACTIVE=true
            echo -e "    Firewall:       ${G}UFW ativo${NC}"
            return
        fi
    fi

    if command -v iptables &>/dev/null; then
        local ipt_rules
        ipt_rules=$(iptables -L INPUT -n 2>/dev/null | grep -c "^[A-Z]" || echo "0")
        if [ "$ipt_rules" -gt 2 ]; then
            FW_TYPE="iptables"
            FW_ACTIVE=true
            echo -e "    Firewall:       ${G}iptables${NC} (${ipt_rules} regras)"
            return
        fi
    fi

    echo -e "    Firewall:       ${Y}nenhum detectado${NC}"
}

ask_firewall_choice() {
    echo ""

    if [ "$FW_ACTIVE" = "false" ]; then
        echo "  Nenhum firewall ativo."
        echo ""
        echo "    [1] Instalar UFW"
        echo "    [2] Usar iptables"
        echo "    [3] Não alterar firewall"
        echo ""
        read -rp "  Escolha: " fw_ch

        case "$fw_ch" in
            1)
                apt-get install -y ufw >/dev/null 2>&1
                ufw default deny incoming >/dev/null 2>&1
                ufw default allow outgoing >/dev/null 2>&1
                ufw allow 22/tcp comment "SSH" >/dev/null 2>&1
                ufw --force enable >/dev/null 2>&1
                FW_TYPE="ufw"; FW_ACTIVE=true
                log "UFW instalado e ativado"
                ;;
            2)
                FW_TYPE="iptables"; FW_ACTIVE=true
                iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
                iptables -A INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null
                log "iptables configurado"
                ;;
            *)
                info "Firewall não alterado"
                return 1
                ;;
        esac
    fi

    read -rp "  Liberar porta no firewall? [Y/n] " fw_go
    [[ "$fw_go" =~ ^[nN]$ ]] && return 1

    if [ "$FW_ACTIVE" = "true" ] && command -v ufw &>/dev/null && command -v iptables &>/dev/null; then
        echo ""
        echo "    [1] ${FW_TYPE}"
        local alt="iptables"; [ "$FW_TYPE" = "iptables" ] && alt="ufw"
        echo "    [2] ${alt}"
        echo ""
        read -rp "  Qual usar? [1/2]: " fw_pick
        if [ "$fw_pick" = "2" ]; then
            FW_TYPE="$alt"
        fi
    fi

    return 0
}

open_port() {
    local port="$1" comment="${2:-Database}"

    if [ "$FW_TYPE" = "ufw" ]; then
        ufw allow "$port/tcp" comment "$comment" >/dev/null 2>&1
    elif [ "$FW_TYPE" = "iptables" ]; then
        iptables -A INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
    fi
}

detect_vps_state() {
    echo ""
    echo -e "  ${BD}${C}=== Detecção VPS ===${NC}"
    echo ""

    local conflicts=false

    # Docker
    if has_docker; then
        local dver
        dver=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
        echo -e "    Docker:         ${G}● instalado${NC} (v${dver})"
    else
        echo -e "    Docker:         ${R}● não instalado${NC}"
    fi

    # Containers
    if has_docker; then
        local containers
        containers=$(docker ps -a --format '{{.Names}}' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
        echo "    Containers:     ${containers:-nenhum}"
    fi

    # Portas
    for db_line in $DATABASES; do
        local name port
        name=$(echo "$db_line" | cut -d'|' -f1)
        port=$(echo "$db_line" | cut -d'|' -f3)

        local pid
        pid=$(ss -tlnp 2>/dev/null | grep ":${port} " | grep -oP 'pid=\K[0-9]+' | head -1)

        if [ -n "$pid" ]; then
            local pname
            pname=$(ps -p "$pid" -o comm= 2>/dev/null || echo "?")
            echo -e "    Porta ${port}:     ${Y}● USADA${NC} (${pname}, PID ${pid})"
            conflicts=true
        else
            echo -e "    Porta ${port}:     ${G}● livre${NC}"
        fi
    done

    # Diretórios
    while IFS='|' read -r name display _ _ _ dir; do
        [ -z "$name" ] && continue
        if [ -d "$dir" ]; then
            if [ -f "$dir/docker-compose.yml" ]; then
                echo -e "    ${dir}:  ${Y}● EXISTE${NC} (instalado)"
            else
                echo -e "    ${dir}:  ${Y}● EXISTE${NC} (vazio)"
                conflicts=true
            fi
        else
            echo -e "    ${dir}:  ${G}● livre${NC}"
        fi
    done <<< "$DATABASES"

    # Serviços nativos
    if systemctl is-active postgresql &>/dev/null 2>&1; then
        echo -e "    PostgreSQL nativo: ${Y}● rodando${NC} (pode conflitar)"
        conflicts=true
    fi
    if systemctl is-active redis &>/dev/null 2>&1; then
        echo -e "    Redis nativo:      ${Y}● rodando${NC} (pode conflitar)"
        conflicts=true
    fi

    # Firewall
    detect_firewall

    echo ""

    if [ "$conflicts" = "true" ]; then
        return 1
    fi
    return 0
}

# ============================================================
# BACKUP
# ============================================================

create_backup() {
    local target="$1"
    local reason="${2:-manual}"
    local timestamp
    timestamp=$(date +%Y-%m-%d_%H-%M-%S)

    mkdir -p "$BACKUP_DIR"

    if [ "$target" = "vps" ]; then
        local bk_dir="${BACKUP_DIR}/vps/${timestamp}"
        mkdir -p "$bk_dir"

        info "Backup do estado da VPS..."

        if [ "$FW_TYPE" = "ufw" ]; then
            ufw status numbered > "$bk_dir/ufw.rules" 2>/dev/null || true
        fi
        if command -v iptables &>/dev/null; then
            iptables-save > "$bk_dir/iptables.rules" 2>/dev/null || true
        fi
        if has_docker; then
            docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' > "$bk_dir/docker-containers.txt" 2>/dev/null || true
            docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' > "$bk_dir/docker-images.txt" 2>/dev/null || true
        fi

        cat > "$bk_dir/meta.json" << EOF
{
  "timestamp": "${timestamp}",
  "target": "vps",
  "reason": "${reason}",
  "hostname": "$(hostname)",
  "date": "$(date -Iseconds)"
}
EOF

        ln -sfn "$bk_dir" "${BACKUP_DIR}/vps/latest"
        log "Backup VPS salvo: ${timestamp}"

    else
        local dir display
        dir=$(parse_db "$target" 6)
        display=$(parse_db "$target" 2)

        local bk_dir="${BACKUP_DIR}/${target}/${timestamp}"
        mkdir -p "$bk_dir"

        info "Backup de $display..."

        [ -f "$dir/.env" ] && cp "$dir/.env" "$bk_dir/"
        [ -f "$dir/docker-compose.yml" ] && cp "$dir/docker-compose.yml" "$bk_dir/"
        [ -d "$dir/data" ] && cp -a "$dir/data" "$bk_dir/data" 2>/dev/null || true

        if [ "$FW_TYPE" = "ufw" ]; then
            ufw status numbered > "$bk_dir/ufw.rules" 2>/dev/null || true
        fi
        if command -v iptables &>/dev/null; then
            iptables-save > "$bk_dir/iptables.rules" 2>/dev/null || true
        fi

        local bk_size
        bk_size=$(du -sh "$bk_dir" 2>/dev/null | cut -f1)

        cat > "$bk_dir/meta.json" << EOF
{
  "timestamp": "${timestamp}",
  "target": "${target}",
  "display": "${display}",
  "reason": "${reason}",
  "port": $(parse_db "$target" 3),
  "dir": "${dir}",
  "size": "${bk_size}"
}
EOF

        ln -sfn "$bk_dir" "${BACKUP_DIR}/${target}/latest"
        log "Backup $display salvo: ${timestamp}"
    fi
}

list_backups() {
    local target="${1:-all}"

    echo ""

    if [ "$target" != "all" ]; then
        echo -e "  ${BD}${C}Backups de ${target}:${NC}"
        echo ""

        local bk_path="${BACKUP_DIR}/${target}"
        if [ ! -d "$bk_path" ]; then
            echo "  Nenhum backup encontrado."
            echo ""; return
        fi

        local idx=1
        for bk in $(ls -1r "$bk_path" 2>/dev/null | grep -v "^latest$"); do
            local reason="" bk_size=""
            if [ -f "$bk_path/$bk/meta.json" ]; then
                reason=$(grep '"reason"' "$bk_path/$bk/meta.json" | cut -d'"' -f4)
            fi
            bk_size=$(du -sh "$bk_path/$bk" 2>/dev/null | cut -f1)
            echo "    [$idx] $bk  ($reason, $bk_size)"
            idx=$((idx + 1))
        done

        if [ "$idx" -eq 1 ]; then
            echo "  Nenhum backup encontrado."
        fi
    else
        echo -e "  ${BD}${C}Todos os backups:${NC}"
        echo ""

        local any=false
        for target_dir in "$BACKUP_DIR"/*/; do
            [ ! -d "$target_dir" ] && continue
            local tname
            tname=$(basename "$target_dir")
            local count
            count=$(ls -1 "$target_dir" 2>/dev/null | grep -v "^latest$" | wc -l)
            if [ "$count" -gt 0 ]; then
                echo "    ${BD}${tname}${NC} ($count backup(s))"
                any=true
            fi
        done

        if [ "$any" = "false" ]; then
            echo "  Nenhum backup encontrado."
        fi
    fi

    echo ""
}

restore_backup() {
    local target="$1"
    local timestamp="${2:-}"

    local bk_path="${BACKUP_DIR}/${target}"

    if [ -z "$timestamp" ]; then
        if [ ! -L "$bk_path/latest" ]; then
            warn "Nenhum backup encontrado para $target"
            return 1
        fi
        bk_path=$(readlink -f "$bk_path/latest")
        timestamp=$(basename "$bk_path")
    else
        bk_path="${BACKUP_DIR}/${target}/${timestamp}"
    fi

    if [ ! -d "$bk_path" ]; then
        warn "Backup não encontrado: $timestamp"
        return 1
    fi

    local display
    display=$(parse_db "$target" 2)

    warn "Restaurar $display do backup $timestamp?"
    confirm "Certeza?" || return 0

    if [ "$target" != "vps" ]; then
        # Backup do estado atual antes de restaurar
        create_backup "$target" "before-restore"

        local dir
        dir=$(parse_db "$target" 6)

        # Para container
        local container
        container=$(parse_db "$target" 5)
        local st
        st=$(get_container_status "$container")
        [ "$st" = "running" ] && (cd "$dir" && docker compose down --timeout 10 2>&1)

        # Restaura arquivos
        [ -f "$bk_path/.env" ] && cp "$bk_path/.env" "$dir/"
        [ -f "$bk_path/docker-compose.yml" ] && cp "$bk_path/docker-compose.yml" "$dir/"
        if [ -d "$bk_path/data" ]; then
            rm -rf "$dir/data"
            cp -a "$bk_path/data" "$dir/data"
        fi

        # Restaura firewall
        if [ -f "$bk_path/iptables.rules" ] && command -v iptables-restore &>/dev/null; then
            iptables-restore < "$bk_path/iptables.rules" 2>/dev/null
            log "Regras iptables restauradas"
        fi

        # Reinicia
        (cd "$dir" && docker compose up -d 2>&1)
        sleep 2

        log "$display restaurado do backup $timestamp"
        show_info "$target"
    else
        info "Backup VPS: $bk_path"
        echo ""
        echo "  Arquivos no backup:"
        ls -la "$bk_path" 2>/dev/null | grep -v "^total" | grep -v "^\."
        echo ""
        info "Para restaurar regras iptables: iptables-restore < $bk_path/iptables.rules"
        info "Para restaurar UFW: verifique manualmente com 'ufw status'"
    fi
}

# ============================================================
# INSTALAR DOCKER
# ============================================================

install_docker() {
    echo ""
    echo -e "${BD}${C}=== Instalar Docker ===${NC}"
    echo ""
    echo "  Será instalado:"
    echo "    - Docker Engine + Compose v2"
    echo "    - Repositório oficial Docker"
    echo ""

    if has_docker; then
        info "Docker já instalado"
        return 0
    fi

    confirm "Instalar?" || return 0

    create_backup "vps" "before-docker-install"

    echo ""
    info "Adicionando repositório Docker..."
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

    info "Instalando Docker Engine + Compose..."
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable docker && systemctl start docker

    log "Docker instalado!"
}

# ============================================================
# INSTALAR BANCO
# ============================================================

install_db() {
    local db="$1"
    local display default_port repo container dir="/opt/db-${db}" port

    display=$(parse_db "$db" 2)
    default_port=$(parse_db "$db" 3)
    repo=$(parse_db "$db" 4)
    container=$(parse_db "$db" 5)
    port="$default_port"

    # Detecção prévia
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

    # Backup e firewall
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
        warn "$display pode não ter iniciado. Verifique: $0 logs $db"
    fi

    show_info "$db"
}

# ============================================================
# BANCO: UP / DOWN / RESTART / UPDATE
# ============================================================

start_db() {
    local db="$1"
    local dir display container
    dir=$(parse_db "$db" 6); display=$(parse_db "$db" 2); container=$(parse_db "$db" 5)

    if ! db_exists "$db"; then
        warn "$display não instalado. Instale primeiro: $0 install $db"
        return 1
    fi

    info "Iniciando $display..."
    (cd "$dir" && docker compose up -d 2>&1)
    sleep 2

    local st
    st=$(get_container_status "$container")
    if [ "$st" = "running" ]; then
        log "$display rodando"
    else
        warn "$display pode não ter iniciado"
    fi
}

stop_db() {
    local db="$1"
    local dir display
    dir=$(parse_db "$db" 6); display=$(parse_db "$db" 2)

    if ! db_exists "$db"; then
        warn "$display não instalado"
        return 1
    fi

    info "Parando $display..."
    (cd "$dir" && docker compose down --timeout 10 2>&1)
    log "$display parado!"
}

restart_db() {
    stop_db "$1"
    start_db "$1"
}

update_db() {
    local db="$1"
    local dir display container st
    dir=$(parse_db "$db" 6); display=$(parse_db "$db" 2); container=$(parse_db "$db" 5)

    if ! db_exists "$db"; then
        warn "$display não instalado"
        return 1
    fi

    create_backup "$db" "before-update"

    info "Atualizando $display..."
    (cd "$dir" && git pull --quiet)

    st=$(get_container_status "$container")
    if [ "$st" = "running" ]; then
        (cd "$dir" && docker compose restart 2>&1)
    else
        (cd "$dir" && docker compose up -d 2>&1)
    fi

    log "$display atualizado!"
}

# ============================================================
# BANCO: STATUS / INFO / LOGS / SHELL
# ============================================================

status_db() {
    local db="$1"
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
    local dir display port
    dir=$(parse_db "$db" 6); display=$(parse_db "$db" 2); port=$(parse_db "$db" 3)

    echo ""
    if [ "$db" = "postgres" ]; then
        local user="postgres" pass="postgres_dev_2026" dbname="devdb"
        [ -f "$dir/.env" ] && {
            user=$(grep "^PG_USER=" "$dir/.env" | cut -d= -f2)
            pass=$(grep "^PG_PASS=" "$dir/.env" | cut -d= -f2)
            dbname=$(grep "^PG_DB=" "$dir/.env" | cut -d= -f2)
        }
        echo "  Host:     localhost"
        echo "  Port:     $port"
        echo "  Database: $dbname"
        echo "  User:     $user"
        echo "  Pass:     $pass"
        echo ""
        echo "  Connect:"
        echo "    psql -h localhost -p $port -U $user -d $dbname"
    elif [ "$db" = "dragonfly" ]; then
        local pass="dragonfly_dev_2026"
        [ -f "$dir/.env" ] && pass=$(grep "^DF_PASS=" "$dir/.env" | cut -d= -f2)
        echo "  Host: localhost"
        echo "  Port: $port"
        echo "  Pass: $pass"
        echo ""
        echo "  Connect:"
        echo "    redis-cli -h localhost -p $port -a $pass"
    fi
}

logs_db() {
    local db="$1"
    local dir display
    dir=$(parse_db "$db" 6); display=$(parse_db "$db" 2)

    if ! db_exists "$db"; then
        warn "$display não instalado"
        return 1
    fi

    echo ""
    info "Logs de $display (Ctrl+C pra sair)..."
    echo ""
    docker compose -f "$dir/docker-compose.yml" logs -f
}

shell_db() {
    local db="$1"
    local dir display container
    dir=$(parse_db "$db" 6); display=$(parse_db "$db" 2); container=$(parse_db "$db" 5)

    if ! db_exists "$db"; then
        warn "$display não instalado"
        return 1
    fi

    local st
    st=$(get_container_status "$container")
    if [ "$st" != "running" ]; then
        warn "$display não está rodando. Use: $0 up $db"
        return 1
    fi

    docker compose -f "$dir/docker-compose.yml" exec -it "$container" sh
}

# ============================================================
# REMOVER BANCO
# ============================================================

remove_db() {
    local db="$1"
    local dir display container
    dir=$(parse_db "$db" 6); display=$(parse_db "$db" 2); container=$(parse_db "$db" 5)

    if ! db_exists "$db"; then
        warn "$display não instalado"
        return 1
    fi

    warn "PARAR e REMOVER $display completamente"
    confirm "Certeza?" || return 0

    create_backup "$db" "before-remove"

    (cd "$dir" && docker compose down -v --timeout 10 2>&1)
    rm -rf "$dir"
    log "$display removido!"
}

# ============================================================
# SUBMENU: INSTALAR
# ============================================================

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

# ============================================================
# SUBMENU: GERENCIAR
# ============================================================

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

# ============================================================
# SUBMENU: BACKUPS
# ============================================================

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
                    2)
                        create_backup "vps" "manual"; pause
                        ;;
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

# ============================================================
# MENU PRINCIPAL
# ============================================================

show_main_menu() {
    local installed_raw has_installed=false has_running=false
    installed_raw=$(get_installed_list)
    [ -n "$(echo "$installed_raw" | tr -d '[:space:]')" ] && has_installed=true
    echo "$installed_raw" | grep -q "running" && has_running=true

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

# ============================================================
# MODO DIRETO (ARGS)
# ============================================================

parse_args() {
    local action="${1:-}"
    shift 2>/dev/null || true
    local args="$*"

    case "$action" in
        install)
            if [ -z "$args" ]; then
                err "Uso: $0 install <docker|postgres|dragonfly>"
            fi
            for arg in $args; do
                case "$arg" in
                    docker) install_docker ;;
                    postgres|dragonfly) install_db "$arg" ;;
                    *) warn "Banco desconhecido: $arg" ;;
                esac
            done
            ;;
        up)
            [ -z "$args" ] && err "Uso: $0 up <postgres|dragonfly>"
            for db in $args; do start_db "$db"; done
            ;;
        down)
            [ -z "$args" ] && err "Uso: $0 down <postgres|dragonfly>"
            for db in $args; do stop_db "$db"; done
            ;;
        restart)
            [ -z "$args" ] && err "Uso: $0 restart <postgres|dragonfly>"
            for db in $args; do restart_db "$db"; done
            ;;
        update)
            [ -z "$args" ] && err "Uso: $0 update <postgres|dragonfly>"
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
            [ -z "$args" ] && err "Uso: $0 logs <postgres|dragonfly>"
            logs_db "$args"
            ;;
        shell)
            [ -z "$args" ] && err "Uso: $0 shell <postgres|dragonfly>"
            shell_db "$args"
            ;;
        psql)
            shell_db "postgres"
            ;;
        remove)
            [ -z "$args" ] && err "Uso: $0 remove <postgres|dragonfly>"
            for db in $args; do remove_db "$db"; done
            ;;
        detect)
            detect_vps_state
            ;;
        backup)
            if [ -z "$args" ] || [ "$args" = "all" ]; then
                create_backup "vps" "manual"
                for db_line in $DATABASES; do
                    local bn
                    bn=$(echo "$db_line" | cut -d'|' -f1)
                    db_exists "$bn" && create_backup "$bn" "manual"
                done
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
  $0 update <db>               atualizar banco (git pull + up)
  $0 status [db]               ver status
  $0 logs <db>                 acompanhar logs
  $0 shell <db>                shell no container
  $0 psql                      shell psql (atalho)
  $0 remove <db>               remover banco
  $0 detect                    detectar estado da VPS
  $0 backup [db|vps|all]       criar backup
  $0 backups [db]              listar backups
  $0 rollback <db> [timestamp] restaurar backup

Bancos: postgres, dragonfly"
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
