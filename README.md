# Database Toolkit v1.0

Docker containers pré-configurados para bancos de dados. Um único script pra tudo.

Multi-language: English 🇺🇸 | Português 🇧🇷

## Bancos disponíveis

### Persistentes (disco)

| Banco | Porta | Repo |
|-------|-------|------|
| PostgreSQL 16 | 5432 | [db-postgres](https://github.com/Brazwed/db-postgres) |
| MySQL 8 | 3306 | [db-mysql](https://github.com/Brazwed/db-mysql) |
| MariaDB 11 | 3307 | [db-mariadb](https://github.com/Brazwed/db-mariadb) |
| MongoDB 7 | 27017 | [db-mongodb](https://github.com/Brazwed/db-mongodb) |

### Cache em memória (RAM)

| Banco | Porta | Repo |
|-------|-------|------|
| DragonflyDB | 6379 | [db-dragonfly](https://github.com/Brazwed/db-dragonfly) |
| Valkey 8 | 6380 | [db-valkey](https://github.com/Brazwed/db-valkey) |

## Instalação rápida

```bash
git clone --recurse-submodules https://github.com/Brazwed/Database.git
cd Database
sudo ./setup.sh
```

## Comandos

### Menu interativo

```bash
sudo ./setup.sh
```

### Args diretos

```bash
# Instalar
sudo ./setup.sh install docker              # instalar Docker
sudo ./setup.sh install postgres            # instalar PostgreSQL
sudo ./setup.sh install postgres mysql      # instalar vários
sudo ./setup.sh install postgres --yes      # sem confirmações

# Gerenciar
sudo ./setup.sh up postgres                 # iniciar
sudo ./setup.sh down postgres               # parar
sudo ./setup.sh restart postgres            # reiniciar
sudo ./setup.sh update postgres             # git pull + up/restart
sudo ./setup.sh status                      # status de todos
sudo ./setup.sh status postgres             # status de 1
sudo ./setup.sh logs postgres               # logs em tempo real
sudo ./setup.sh shell postgres              # shell no container
sudo ./setup.sh psql                        # atalho: psql postgres
sudo ./setup.sh mysql                       # atalho: mysql
sudo ./setup.sh mariadb                     # atalho: mariadb
sudo ./setup.sh mongo                       # atalho: mongosh
sudo ./setup.sh valkey                      # atalho: valkey-cli
sudo ./setup.sh remove postgres             # remover banco

# Backups
sudo ./setup.sh backup                      # backup de tudo
sudo ./setup.sh backup postgres             # backup de 1
sudo ./setup.sh backups                     # listar backups
sudo ./setup.sh rollback postgres           # restaurar mais recente
sudo ./setup.sh rollback postgres 2026-03-31_15-00-00  # restaurar específico

# Utilidades
sudo ./setup.sh detect                      # detectar estado da VPS
sudo ./setup.sh lang pt                     # trocar idioma (pt/en)
sudo ./setup.sh --version                   # mostrar versão
sudo ./setup.sh --help                      # mostrar ajuda
```

## Conexão padrão

### PostgreSQL 16

```
Host:     localhost
Porta:    5432
Usuário:  postgres
Senha:    postgres_dev_2026
Banco:    devdb

psql -h localhost -p 5432 -U postgres -d devdb
```

### MySQL 8

```
Host:     localhost
Porta:    3306
Usuário:  mysql_user
Senha:    mysql_dev_2026
Banco:    devdb

mysql -h localhost -P 3306 -u mysql_user -pmysql_dev_2026 devdb
```

### MariaDB 11

```
Host:     localhost
Porta:    3307
Usuário:  mariadb_user
Senha:    mariadb_dev_2026
Banco:    devdb

mysql -h localhost -P 3307 -u mariadb_user -pmariadb_dev_2026 devdb
```

### MongoDB 7

```
Host:     localhost
Porta:    27017
Usuário:  mongodb_user
Senha:    mongodb_dev_2026

mongosh mongodb://mongodb_user:mongodb_dev_2026@localhost:27017/devdb
```

### DragonflyDB

```
Host:     localhost
Porta:    6379
Senha:    dragonfly_dev_2026

redis-cli -h localhost -p 6379 -a dragonfly_dev_2026
```

### Valkey 8

```
Host:     localhost
Porta:    6380
Senha:    valkey_dev_2026

redis-cli -h localhost -p 6380 -a valkey_dev_2026
```

## Estrutura

```
Database/
├── setup.sh               ← ÚNICO ponto de entrada
├── README.md
│
├── lib/
│   ├── utils.sh           ← helpers, cores, logging, spinner
│   ├── menu.sh            ← menu interativo
│   ├── database.sh        ← operações de banco
│   ├── detection.sh       ← detecção de VPS
│   ├── backup.sh          ← sistema de backup
│   ├── firewall.sh        ← gerenciamento de firewall
│   ├── docker.sh          ← instalação do Docker
│   └── lang/
│       ├── en_US.sh       ← inglês (default)
│       └── pt_BR.sh       ← português
│
└── dbs/
    ├── db-postgres/       ← PostgreSQL 16
    ├── db-mysql/          ← MySQL 8
    ├── db-mariadb/        ← MariaDB 11
    ├── db-mongodb/        ← MongoDB 7
    ├── db-dragonfly/      ← DragonflyDB
    └── db-valkey/         ← Valkey 8
```

## Adicionar novo banco

1. Criar repo no GitHub (ex: `db-redis`)
2. Criar subpasta: `dbs/db-redis/`
3. Criar: `docker-compose.yml`, `.env.example`, `README.md`
4. Adicionar na variável `DATABASES` do `setup.sh`
5. Adicionar case no `show_info` em `lib/database.sh`
6. Adicionar strings de tradução em `lib/lang/en_US.sh` e `lib/lang/pt_BR.sh`

## Idioma

O idioma é detectado automaticamente do sistema. Para trocar:

```bash
sudo ./setup.sh lang pt     # português
sudo ./setup.sh lang en     # inglês
```

Salva em `~/.db-toolkit/lang`. O idioma muda no próximo uso do menu.

## Recursos

- Spinner animado durante ações
- Status com cores (● verde rodando, ● vermelho parado, ● amarelo não instalado)
- Sistema de backup automático antes de cada ação destrutiva
- Detecção de VPS (Docker, portas, firewall)
- Flush de stdin (Enter/tecla antes do menu não causa bugs)
- Modo não-interativo (`--yes`) pra scripts e CI
- Multi-language (English + Português)

## Por Brazwed

https://github.com/Brazwed/Database
