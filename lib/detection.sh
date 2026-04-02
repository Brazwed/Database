# lib/detection.sh - Detecção de VPS e firewall

detect_firewall() {
    FW_TYPE="none"
    FW_ACTIVE=false

    if command -v ufw &>/dev/null; then
        if ufw status 2>/dev/null | head -1 | grep -q "active"; then
            FW_TYPE="ufw"
            FW_ACTIVE=true
            local rules
            rules=$(ufw status 2>/dev/null | grep -c "ALLOW" || echo "0")
            echo -e "    Firewall:  ${G}UFW${NC} (${rules} regras)"
            return
        fi
    fi

    if command -v iptables &>/dev/null; then
        local ipt_rules
        ipt_rules=$(iptables -L INPUT -n 2>/dev/null | grep -c "^[A-Z]" || echo "0")
        if [ "$ipt_rules" -gt 2 ]; then
            FW_TYPE="iptables"
            FW_ACTIVE=true
            echo -e "    Firewall:  ${G}iptables${NC} (${ipt_rules} regras)"
            return
        fi
    fi

    echo -e "    Firewall:  ${Y}nenhum${NC}"
}

detect_vps_state() {
    local SEP='━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'

    echo ""
    echo -e "  ${BD}${C}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${BD}${C}║                    Detecção VPS                              ║${NC}"
    echo -e "  ${BD}${C}║                    ${DIM}Database Toolkit v1.0${NC}${BD}${C}                   ║${NC}"
    echo -e "  ${BD}${C}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local conflicts=false
    local ports_in_use=()

    # ─── Sistema ──────────────────────────────────────────────
    echo -e "  ${BD}Sistema${NC}"

    if has_docker; then
        local dver
        dver=$(docker --version 2>/dev/null | sed -n 's/.*\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p' | head -1)
        echo -e "    Docker:     ${G}● instalado${NC} (v${dver})"
    else
        echo -e "    Docker:     ${R}● não instalado${NC}"
    fi

    # Containers resumidos
    local db_containers=""
    while IFS='|' read -r _ name _ _ container _ _; do
        [ -z "$name" ] && continue
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "$container"; then
            [ -n "$db_containers" ] && db_containers="${db_containers}, "
            db_containers="${db_containers}${name}"
        fi
    done <<< "$DATABASES"
    echo "    Containers: ${db_containers:-nenhum}"

    detect_firewall
    echo ""

    # ─── Bancos Persistentes ──────────────────────────────────
    echo -e "  ${BD}${SEP}${NC}"
    echo ""

    echo -e "  📦 ${BD}Bancos Persistentes (disco)${NC}"
    while IFS='|' read -r cat name display port repo container dir; do
        [ -z "$name" ] && continue
        [ "$cat" != "persistent" ] && continue

        local installed=false port_used=false port_ours=false

        if [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]; then
            installed=true
        fi

        local pid=""
        pid=$(ss -tlnp 2>/dev/null | grep ":${port} " | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | head -1)
        if [ -n "$pid" ]; then
            port_used=true
            if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "$container"; then
                port_ours=true
            fi
        fi

        if $installed; then
            if $port_used; then
                if $port_ours; then
                    printf "    %-18s :%-6s ${BD}${G}● instalado${NC}  ${G}porta em uso${NC}\n" "$display" "$port"
                else
                    printf "    %-18s :%-6s ${BD}${Y}● instalado${NC}  ${R}porta em uso por outro${NC}\n" "$display" "$port"
                    conflicts=true
                    ports_in_use+=("$port")
                fi
            else
                printf "    %-18s :%-6s ${BD}${Y}○ instalado${NC}  porta livre\n" "$display" "$port"
            fi
        else
            if $port_used; then
                printf "    %-18s :%-6s ${R}porta em uso por outro${NC}\n" "$display" "$port"
                conflicts=true
                ports_in_use+=("$port")
            else
                printf "    %-18s :%-6s ${DIM}não instalado${NC}\n" "$display" "$port"
            fi
        fi
    done <<< "$DATABASES"
    echo ""

    # ─── Cache ────────────────────────────────────────────────
    echo -e "  ⚡ ${BD}Cache em Memória (RAM)${NC}"
    while IFS='|' read -r cat name display port repo container dir; do
        [ -z "$name" ] && continue
        [ "$cat" != "memory" ] && continue

        local installed=false port_used=false port_ours=false

        if [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]; then
            installed=true
        fi

        local pid=""
        pid=$(ss -tlnp 2>/dev/null | grep ":${port} " | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | head -1)
        if [ -n "$pid" ]; then
            port_used=true
            if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "$container"; then
                port_ours=true
            fi
        fi

        if $installed; then
            if $port_used; then
                if $port_ours; then
                    printf "    %-18s :%-6s ${BD}${G}● instalado${NC}  ${G}porta em uso${NC}\n" "$display" "$port"
                else
                    printf "    %-18s :%-6s ${BD}${Y}● instalado${NC}  ${R}porta em uso por outro${NC}\n" "$display" "$port"
                    conflicts=true
                    ports_in_use+=("$port")
                fi
            else
                printf "    %-18s :%-6s ${BD}${Y}○ instalado${NC}  porta livre\n" "$display" "$port"
            fi
        else
            if $port_used; then
                printf "    %-18s :%-6s ${R}porta em uso por outro${NC}\n" "$display" "$port"
                conflicts=true
                ports_in_use+=("$port")
            else
                printf "    %-18s :%-6s ${DIM}não instalado${NC}\n" "$display" "$port"
            fi
        fi
    done <<< "$DATABASES"
    echo ""

    # ─── Conflitos ────────────────────────────────────────────
    if [ ${#ports_in_use[@]} -gt 0 ]; then
        echo -e "  ${BD}${SEP}${NC}"
        echo ""
        local port_list
        port_list=$(IFS=', '; echo "${ports_in_use[*]}")
        echo -e "  ${Y}[!] ${#ports_in_use[@]} porta(s) em uso por outro: ${port_list}${NC}"
        echo ""
    fi

    if [ "$conflicts" = "true" ]; then
        return 1
    fi
    return 0
}
