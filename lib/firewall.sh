# lib/firewall.sh - Gerenciamento de firewall (UFW/iptables)

ask_firewall_choice() {
    echo ""

    if [ "$FW_ACTIVE" = "false" ]; then
        echo "  ${MSG_FW_NO_FIREWALL}"
        echo ""
        echo "    ${MSG_FW_INSTALL_UFW}"
        echo "    ${MSG_FW_USE_IPTABLES}"
        echo "    ${MSG_FW_DONT_CHANGE}"
        echo ""
        read -rp "  ${PROMPT_CHOICE}" fw_ch

        case "$fw_ch" in
            1)
                if ! apt-get install -y ufw >/dev/null 2>&1; then
                    warn "${MSG_FW_FAIL_INSTALL}"; return 1
                fi
                if ! ufw default deny incoming >/dev/null 2>&1; then
                    warn "${MSG_FW_FAIL_CONFIG}"; return 1
                fi
                ufw default allow outgoing >/dev/null 2>&1 || true
                ufw allow 22/tcp comment "SSH" >/dev/null 2>&1 || true
                if ! ufw --force enable >/dev/null 2>&1; then
                    warn "${MSG_FW_FAIL_ENABLE}"; return 1
                fi
                FW_TYPE="ufw"; FW_ACTIVE=true
                log "${MSG_FW_UFW_INSTALLED}"
                ;;
            2)
                FW_TYPE="iptables"; FW_ACTIVE=true
                iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
                iptables -A INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
                log "${MSG_FW_IPTABLES_SET}"
                ;;
            *)
                info "${MSG_FW_CANCELLED}"
                return 1
                ;;
        esac
    fi

    read -rp "  ${MSG_FW_OPEN_PORT}" fw_go
    [[ "$fw_go" =~ ^[nN]$ ]] && return 1

    local alt_tool="iptables"; [ "$FW_TYPE" = "iptables" ] && alt_tool="ufw"
    if [ "$FW_ACTIVE" = "true" ] && command -v "$alt_tool" &>/dev/null; then
        echo ""
        echo "    [1] ${FW_TYPE}"
        echo "    [2] ${alt_tool}"
        echo ""
        read -rp "  ${MSG_FW_WHICH}" fw_pick
        if [ "$fw_pick" = "2" ]; then
            FW_TYPE="$alt_tool"
        fi
    fi

    return 0
}

open_port() {
    local port="$1" comment="${2:-Database}"

    if [ "$FW_TYPE" = "ufw" ]; then
        ufw allow "$port/tcp" comment "$comment" >/dev/null 2>&1 || warn "${MSG_FW_FAIL_OPEN_UFW}"
    elif [ "$FW_TYPE" = "iptables" ]; then
        iptables -A INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || warn "${MSG_FW_FAIL_OPEN_IPTABLES}"
    fi
}
