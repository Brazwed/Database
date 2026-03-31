# lib/firewall.sh - Gerenciamento de firewall (UFW/iptables)

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

    local alt_tool="iptables"; [ "$FW_TYPE" = "iptables" ] && alt_tool="ufw"
    if [ "$FW_ACTIVE" = "true" ] && command -v "$alt_tool" &>/dev/null; then
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
