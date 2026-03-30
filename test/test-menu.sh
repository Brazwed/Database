#!/usr/bin/env bash

# ============================================================
# Database Toolkit - Menu Mock (TESTE)
# ============================================================

# --- Cenários ---
MOCK_DOCKER=false
MOCK_INSTALLED=""

# MOCK_DOCKER=true; MOCK_INSTALLED=""  # Docker sem bancos
# MOCK_DOCKER=true; MOCK_INSTALLED="postgres|PostgreSQL 16|5432|running|/opt/db-postgres"  # PG rodando
# MOCK_DOCKER=true; MOCK_INSTALLED="postgres|PostgreSQL 16|5432|running|/opt/db-postgres\ndragonfly|DragonflyDB|6379|stopped|/opt/db-dragonfly"  # PG + DF

# ============================================================

DATABASES="postgres|PostgreSQL 16|5432|db-postgres|postgres|/opt/db-postgres
dragonfly|DragonflyDB|6379|db-dragonfly|dragonfly|/opt/db-dragonfly"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'
C='\033[0;36m'; BD='\033[1m'; NC='\033[0m'

log()  { echo -e "${G}[✔]${NC} $1"; }
warn() { echo -e "${Y}[!]${NC} $1"; }
info() { echo -e "${B}[●]${NC} $1"; }
mock() { echo -e "${Y}[MOCK]${NC} $1"; }

confirm() {
    read -rp "${1:-Confirmar?} [Y/n] " c
    [[ -z "$c" || "$c" =~ ^[yY]$ ]]
}

pause() {
    read -rp "  Enter para continuar..." _
}

has_docker() { [ "$MOCK_DOCKER" = "true" ]; }

get_container_status() {
    echo "$MOCK_INSTALLED" | grep "^${1}|" | cut -d'|' -f4 2>/dev/null || echo "stopped"
}

parse_db() {
    echo "$DATABASES" | grep "^${1}|" | cut -d'|' -f"$2"
}

db_exists() {
    echo "$MOCK_INSTALLED" | grep -q "^${1}|" 2>/dev/null
}

get_installed_list() {
    printf '%b' "$MOCK_INSTALLED"
}

# --- Mocks ---

mock_install_docker() {
    echo ""
    mock "Adicionando repositório Docker..."; sleep 0.3
    mock "Instalando Docker Engine + Compose v2..."; sleep 0.5
    MOCK_DOCKER=true
    mock "Habilitando serviço Docker..."; sleep 0.2
    log "Docker instalado!"
}

mock_install_db() {
    local db="$1" advanced="${2:-false}"
    local display default_port dir="/opt/db-${db}" port

    display=$(parse_db "$db" 2)
    default_port=$(parse_db "$db" 3)
    port="$default_port"

    if [ "$advanced" = "true" ]; then
        echo ""
        echo -e "${BD}${C}--- $display ---${NC}"
        read -rp "  Pasta [$dir]: " x; [ -n "$x" ] && dir="$x"
        read -rp "  Porta [$default_port]: " x; [ -n "$x" ] && port="$x"
    fi

    echo ""
    mock "git clone ... → $dir"; sleep 0.5
    mock "docker compose up -d (porta $port)"; sleep 0.5
    log "$display rodando na porta $port"

    echo ""
    echo "  Host: localhost  Port: $port  DB: devdb"
}

mock_update_db() {
    local display; display=$(parse_db "$1" 2)
    mock "git pull + restart"; sleep 0.5
    log "$display atualizado!"
}

mock_down_db() {
    local display; display=$(parse_db "$1" 2)
    mock "docker compose down"; sleep 0.5
    log "$display parado!"
}

mock_status_db() {
    local display port dir st
    display=$(parse_db "$1" 2); port=$(parse_db "$1" 3); dir="/opt/db-${1}"
    st=$(get_container_status "$1")

    echo ""
    echo -e "${BD}${C}=== $display ===${NC}"
    echo "  Pasta:  $dir"
    echo "  Porta:  $port"

    if [ "$st" = "running" ]; then
        echo -e "  Status: ${G}running${NC}"
        echo "  Host: localhost  Port: $port"
    else
        echo -e "  Status: ${R}stopped${NC}"
    fi
}

mock_remove_db() {
    local display; display=$(parse_db "$1" 2)
    warn "PARAR e REMOVER $display"
    confirm "Certeza?" || return 0
    mock "docker compose down -v + rm -rf"; sleep 0.5
    log "$display removido!"
}

# ============================================================
# SELEÇÃO
# ============================================================

resolve_db_list() {
    local input="$1" dbs=""
    if [ "$input" = "all" ]; then
        while IFS='|' read -r name _; do [ -n "$name" ] && dbs="$dbs $name"; done <<< "$DATABASES"
        echo "$dbs"; return 0
    fi
    IFS=',' read -ra choices <<< "$input"
    local idx=1
    while IFS='|' read -r name _; do
        [ -z "$name" ] && continue
        for ch in "${choices[@]}"; do
            ch=$(echo "$ch" | tr -d ' ')
            [ "$ch" = "$idx" ] && dbs="$dbs $name"
        done
        idx=$((idx + 1))
    done <<< "$DATABASES"
    echo "$dbs"
}

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
        names+=("$name")
        idx=$((idx + 1))
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

        # Docker (se não tem)
        if ! has_docker; then
            echo "    [1] Docker Engine + Compose"
            echo ""
            echo "  Necessário pra rodar os bancos."
            echo ""
            local docker_idx=1
            docker_opt=true
            idx=$((idx + 1))
        fi

        # Bancos
        echo -e "  ${BD}Bancos:${NC}"
        local db_start=$idx
        local db_names=()
        while IFS='|' read -r name display port _; do
            [ -z "$name" ] && continue
            if db_exists "$name"; then
                echo -e "    [$idx] $display (porta $port) ${G}já instalado${NC}"
            else
                echo "    [$idx] $display (porta $port)"
            fi
            db_names+=("$name")
            idx=$((idx + 1))
        done <<< "$DATABASES"

        # Opções
        echo ""
        echo "    [0] ← Voltar ao menu principal"
        echo ""

        read -rp "  Escolha: " choice
        [ "$choice" = "0" ] && return

        # Docker
        if [ "$docker_opt" = "true" ] && [ "$choice" = "$docker_idx" ]; then
            echo ""
            echo "  Será instalado:"
            echo "    - Docker Engine + Compose v2"
            echo "    - Repositório oficial Docker"
            echo ""
            confirm "Instalar?" && mock_install_docker
            pause; continue
        fi

        # Ajusta índice se tem Docker
        local adj=$choice
        if [ "$docker_opt" = "true" ]; then
            adj=$((choice - 1))
        fi

        # Banco individual
        if [ "$adj" -ge 1 ] 2>/dev/null && [ "$adj" -le "${#db_names[@]}" ] 2>/dev/null; then
            local selected="${db_names[$((adj - 1))]}"
            local display default_port repo dir="/opt/db-${selected}" port

            display=$(parse_db "$selected" 2)
            default_port=$(parse_db "$selected" 3)
            repo=$(parse_db "$selected" 4)
            port="$default_port"

            # Mostra resumo
            echo ""
            echo -e "  ${BD}${C}=== $display ===${NC}"
            echo ""
            echo "    Imagem:     ${display}"
            echo "    Porta:      $default_port"
            echo "    Pasta:      $dir"
            echo "    Repo:       ${GITHUB_BASE:-https://github.com/Brazwed}/${repo}"
            echo ""

            # Pergunta customização
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

            confirm "Confirmar instalar?" && mock_install_db "$selected"
            pause; continue
        fi

        warn "Opção inválida"
    done
}

# ============================================================
# SUBMENU: GERENCIAR
# ============================================================

submenu_manage() {
    while true; do
        clear
        echo ""
        echo -e "  ${BD}${C}← Gerenciar bancos${NC}"
        echo ""

        # Lista bancos instalados
        local installed_raw
        installed_raw=$(get_installed_list)

        if [ -z "$(echo "$installed_raw" | tr -d '[:space:]')" ]; then
            echo "  Nenhum banco instalado."
            echo ""
            pause; return
        fi

        echo -e "  ${BD}Bancos instalados:${NC}"
        echo ""
        local idx=1 names=()
        while IFS='|' read -r name display port status dir; do
            [ -z "$name" ] && continue
            if [ "$status" = "running" ]; then
                echo -e "    [$idx] ${G}●${NC} $display (porta $port) rodando"
            else
                echo -e "    [$idx] ${R}●${NC} $display (porta $port) parado"
            fi
            names+=("$name")
            idx=$((idx + 1))
        done <<< "$installed_raw"

        echo ""
        echo -e "  ${BD}O que fazer?${NC}"
        echo ""
        echo "    [U] Atualizar (git pull + restart)"
        echo "    [D] Parar (docker compose down)"
        echo "    [S] Status (detalhes + conexão)"
        echo "    [X] Remover (deletar tudo)"
        echo "    [0] ← Voltar ao menu principal"
        echo ""

        read -rp "  Escolha: " action
        [ "$action" = "0" ] && return

        action=$(echo "$action" | tr '[:upper:]' '[:lower:]')

        local db_name
        case "$action" in
            u) db_name=$(select_installed_db "Qual banco atualizar?") || continue
               mock_update_db "$db_name"; pause ;;
            d) db_name=$(select_installed_db "Qual banco parar?") || continue
               mock_down_db "$db_name"; pause ;;
            s)
                for name in "${names[@]}"; do mock_status_db "$name"; done
                pause ;;
            x) db_name=$(select_installed_db "Qual banco remover?") || continue
               mock_remove_db "$db_name"; pause ;;
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

    # --- Sistema ---
    echo -e "  ${BD}Sistema${NC}"
    if has_docker; then
        echo -e "    Docker:     ${G}● instalado${NC}"
    else
        echo -e "    Docker:     ${R}● não instalado${NC}"
    fi
    echo ""

    # --- Bancos ---
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

    # --- Menu ---
    echo -e "  ${BD}Menu${NC}"
    echo ""
    echo "    [1] Instalar        preparar ambiente ou banco(s)"
    if [ "$any" = "true" ]; then
        echo "    [2] Gerenciar       atualizar, parar, status, remover"
    fi
    echo "    [0] Sair"
    echo ""
}

# ============================================================
# LOOP
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
            0) echo ""; log "Até mais!"; exit 0 ;;
            *) warn "Opção inválida: $choice" ;;
        esac
    done
}

# ============================================================
# MAIN
# ============================================================

echo ""
echo -e "${BD}${Y}=== TEST MODE ===${NC}"
echo -e "  Docker:    $MOCK_DOCKER"
echo -e "  Installed: ${MOCK_INSTALLED:-nenhum}"
echo ""
read -rp "Iniciar? [Y/n] " go
[[ "$go" =~ ^[nN]$ ]] && exit 0

interactive_menu
