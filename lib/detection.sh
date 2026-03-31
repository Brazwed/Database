# lib/detection.sh - Detecção de VPS e firewall

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

detect_vps_state() {
    echo ""
    echo -e "  ${BD}${C}=== Detecção VPS ===${NC}"
    echo ""

    local conflicts=false

    # Docker
    if has_docker; then
        local dver
        dver=$(docker --version 2>/dev/null | sed -n 's/.*\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p' | head -1)
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

    # Portas e diretórios
    while IFS='|' read -r db_name _ db_port _ _ db_dir; do
        [ -z "$db_name" ] && continue

        local pid
        pid=$(ss -tlnp 2>/dev/null | grep ":${db_port} " | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | head -1)

        if [ -n "$pid" ]; then
            local pname
            pname=$(ps -p "$pid" -o comm= 2>/dev/null || echo "?")
            echo -e "    Porta ${db_port}:     ${Y}● USADA${NC} (${pname}, PID ${pid})"
            conflicts=true
        else
            echo -e "    Porta ${db_port}:     ${G}● livre${NC}"
        fi

        if [ -d "$db_dir" ]; then
            if [ -f "$db_dir/docker-compose.yml" ]; then
                echo -e "    ${db_dir}:  ${Y}● EXISTE${NC} (instalado)"
            else
                echo -e "    ${db_dir}:  ${Y}● EXISTE${NC} (vazio)"
                conflicts=true
            fi
        else
            echo -e "    ${db_dir}:  ${G}● livre${NC}"
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
