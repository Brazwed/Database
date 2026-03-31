# lib/backup.sh - Sistema de backup

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

        if [ -z "$dir" ]; then
            warn "Banco desconhecido para backup: '$target'"
            return 1
        fi

        if [ ! -d "$dir" ] || [ ! -f "$dir/docker-compose.yml" ]; then
            warn "$display não instalado, nada para fazer backup"
            return 1
        fi

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
                echo -e "    ${BD}${tname}${NC} ($count backup(s))"
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
    if [ "$target" != "vps" ]; then
        display=$(parse_db "$target" 2)
        if [ -z "$display" ]; then
            warn "Banco desconhecido para restore: '$target'"
            return 1
        fi
    else
        display="VPS"
    fi

    warn "Restaurar $display do backup $timestamp?"
    confirm "Certeza?" || return 0

    if [ "$target" != "vps" ]; then
        local dir
        dir=$(parse_db "$target" 6)

        if [ -z "$dir" ]; then
            warn "Banco desconhecido para restore: '$target'"
            return 1
        fi

        if [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]; then
            create_backup "$target" "before-restore" || true
        fi

        mkdir -p "$dir"

        local container
        container=$(parse_db "$target" 5)
        local st
        st=$(get_container_status "$container")
        [ "$st" = "running" ] && (cd "$dir" && docker compose down --timeout 10 2>&1)

        [ -f "$bk_path/.env" ] && cp "$bk_path/.env" "$dir/"
        [ -f "$bk_path/docker-compose.yml" ] && cp "$bk_path/docker-compose.yml" "$dir/"
        if [ -d "$bk_path/data" ]; then
            rm -rf "$dir/data"
            cp -a "$bk_path/data" "$dir/data"
        fi

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
        info "Para restaurar iptables: iptables-restore < $bk_path/iptables.rules"
    fi
}
