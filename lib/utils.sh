# lib/utils.sh - Cores, logging, helpers

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'
C='\033[0;36m'; BD='\033[1m'; NC='\033[0m'

log()  { echo -e "${G}[✔]${NC} $1"; }
warn() { echo -e "${Y}[!]${NC} $1"; }
err()  { echo -e "${R}[✘]${NC} $1"; exit 1; }
info() { echo -e "${B}[●]${NC} $1"; }

confirm() { read -rp "${1:-Confirmar?} [Y/n] " c; [[ -z "$c" || "$c" =~ ^[yY]$ ]]; }
pause()   { read -rp "  Pressione Enter..." _; }

has_docker() { command -v docker &>/dev/null && docker info &>/dev/null 2>&1; }

get_container_status() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "$1" && echo "running" || echo "stopped"
}

parse_db() { echo "$DATABASES" | grep "^${1}|" | cut -d'|' -f"$2"; }

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
