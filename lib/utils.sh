# lib/utils.sh - Cores, logging, helpers

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'
C='\033[0;36m'; BD='\033[1m'; NC='\033[0m'

log()  { echo -e "${G}[✔]${NC} $1"; }
warn() { echo -e "${Y}[!]${NC} $1"; }
err()  { echo -e "${R}[✘]${NC} $1"; exit 1; }
info() { echo -e "${B}[●]${NC} $1"; }

spinner() {
    local msg="$1" chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    for i in $(seq 1 8); do
        printf "\r  ${B}[●]${NC} ${chars:$((i % ${#chars})):1} ${msg}..."
        sleep 0.08
    done
    printf "\r  ${G}[✔]${NC} ${msg}... OK!          \n"
}

confirm() { read -rp "${1:-Confirmar?} [Y/n] " c; [[ -z "$c" || "$c" =~ ^[yY]$ ]]; }
pause()   { read -rp "  Pressione Enter..." _; }

has_docker() { command -v docker &>/dev/null && docker info &>/dev/null; }

get_container_status() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "$1" && echo "running" || echo "stopped"
}

parse_db() {
    local db="$1" field="$2"
    [ -z "$db" ] && return 1
    local _cat _name _display _port _repo _container _dir
    while IFS='|' read -r _cat _name _display _port _repo _container _dir; do
        [ -z "$_name" ] && continue
        if [ "$_name" = "$db" ]; then
            case "$field" in
                1) echo "$_name" ;;
                2) echo "$_display" ;;
                3) echo "$_port" ;;
                4) echo "$_repo" ;;
                5) echo "$_container" ;;
                6) echo "$_dir" ;;
                cat) echo "$_cat" ;;
            esac
            return 0
        fi
    done <<< "$DATABASES"
    return 1
}

db_info_valid() {
    local dir
    dir=$(parse_db "$1" 6)
    [ -n "$dir" ]
}

db_exists() {
    local dir
    dir=$(parse_db "$1" 6)
    [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]
}

get_installed_list() {
    local result=""
    while IFS='|' read -r cat name display port repo container dir; do
        [ -z "$name" ] && continue
        if [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]; then
            local st
            st=$(get_container_status "$container")
            result="${result}${name}|${display}|${port}|${st}|${dir}\n"
        fi
    done <<< "$DATABASES"
    printf '%b' "$result"
}
