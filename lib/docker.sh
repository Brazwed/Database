# lib/docker.sh - Instalação do Docker

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
    if ! apt-get update -y; then
        err "Falha ao atualizar pacotes. Verifique sua conexão."
    fi
    if ! apt-get install -y ca-certificates curl gnupg; then
        err "Falha ao instalar dependências (ca-certificates, curl, gnupg)."
    fi
    install -m 0755 -d /etc/apt/keyrings
    if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        err "Falha ao baixar chave GPG do Docker."
    fi
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

    info "Instalando Docker Engine + Compose..."
    if ! apt-get update -y; then
        err "Falha ao atualizar com repositório Docker. Verifique o repo."
    fi
    if ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        err "Falha ao instalar Docker. Verifique: apt-cache policy docker-ce"
    fi
    systemctl enable docker && systemctl start docker

    log "Docker instalado!"
}
