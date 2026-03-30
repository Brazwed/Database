# Database Toolkit

Docker containers pré-configurados para bancos de dados. Um único script pra tudo.

## Bancos disponíveis

| Banco | Porta | Repo |
|-------|-------|------|
| PostgreSQL 16 | 5432 | [db-postgres](https://github.com/Brazwed/db-postgres) |
| DragonflyDB | 6379 | [db-dragonfly](https://github.com/Brazwed/db-dragonfly) |

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
sudo ./setup.sh install postgres dragonfly  # instalar vários

# Gerenciar
sudo ./setup.sh up postgres                 # iniciar
sudo ./setup.sh down postgres               # parar
sudo ./setup.sh restart postgres            # reiniciar
sudo ./setup.sh update postgres             # git pull + up/restart
sudo ./setup.sh status                      # status de todos
sudo ./setup.sh status postgres             # status de 1
sudo ./setup.sh logs postgres               # logs em tempo real
sudo ./setup.sh shell postgres              # shell no container
sudo ./setup.sh psql                        # atalho pro psql
sudo ./setup.sh remove postgres             # remover banco
```

## Conexão padrão

### PostgreSQL

```
Host:     localhost
Porta:    5432
Usuário:  postgres
Senha:    postgres_dev_2026
Banco:    devdb

psql -h localhost -p 5432 -U postgres -d devdb
```

### DragonflyDB

```
Host:     localhost
Porta:    6379
Senha:    dragonfly_dev_2026

redis-cli -h localhost -p 6379 -a dragonfly_dev_2026
```

## Estrutura

```
Database/
├── setup.sh               ← ÚNICO ponto de entrada
├── test/test-menu.sh      ← Mock pra testar menu
├── README.md
│
├── db-postgres/           ← Repo: db-postgres
│   ├── docker-compose.yml
│   ├── .env.example
│   └── README.md
│
└── db-dragonfly/          ← Repo: db-dragonfly
    ├── docker-compose.yml
    ├── .env.example
    └── README.md
```

## Adicionar novo banco

1. Criar repo no GitHub (ex: `db-mongodb`)
2. Criar pasta: `db-mongodb/`
3. Criar: `docker-compose.yml`, `.env.example`, `README.md`
4. Adicionar na variável `DATABASES` do `setup.sh`

Pronto — zero conflito com os outros bancos.
