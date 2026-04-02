# lib/docker.sh - Instalação do Docker

install_docker() {
    echo ""
    echo -e "${BD}${C}=== Instalar Docker ===${NC}"
    echo ""
    echo "  ${MSG_MENU_DOCKER_WILL_INSTALL}"
    echo "    ${MSG_MENU_DOCKER_ENGINE}"
    echo "    ${MSG_MENU_DOCKER_REPO}"
    echo ""

    if has_docker; then
        info "${MSG_DOCK_ALREADY}"
        return 0
    fi

    confirm "${PROMPT_CONFIRM}" || return 0

    create_backup "vps" "before-docker-install"

    echo ""
    spinner "${MSG_DOCK_ADDING_REPO}"
    if ! apt-get update -y; then
        err "${ERR_DOCKER_NOT_INSTALLED}. Verifique sua conexão."
    fi
    if ! apt-get install -y ca-certificates curl gnupg; then
        err "${ERR_DOCKER_NOT_INSTALLED} (ca-certificates, curl, gnupg)."
    fi
    install -m 0755 -d /etc/apt/keyrings
    if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        err "${ERR_DOCKER_NOT_INSTALLED} do Docker."
    fi
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

    spinner "${MSG_DOCK_INSTALLING}"
    if ! apt-get update -y; then
        err "${ERR_DOCKER_NOT_INSTALLED} Docker. Verifique o repo."
    fi
    if ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        err "${ERR_DOCKER_NOT_INSTALLED}. Verifique: apt-cache policy docker-ce"
    fi
    systemctl enable docker && systemctl start docker

    log "${MSG_DOCK_INSTALLED}"
}
