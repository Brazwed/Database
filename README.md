# Database Toolkit

Docker containers pré-configurados para bancos de dados. Sem conflitos, sem comandos errados, prontos pra usar.

## Bancos disponíveis

| Banco | Repo | Status | Porta |
|-------|------|--------|-------|
| PostgreSQL 16 | [db-postgres](https://github.com/brazwed/db-postgres) | ✅ Pronto | 5432 |
| DragonflyDB | [db-dragonfly](https://github.com/brazwed/db-dragonfly) | ✅ Pronto | 6379 |

## Como usar

### Standalone (só 1 banco)

```bash
git clone https://github.com/brazwed/db-postgres.git
cd db-postgres
./start.sh up
./info.sh
```

### Via repo principal (todos os bancos)

```bash
git clone https://github.com/brazwed/Database.git
cd Database
make db-postgres/up
make db-dragonfly/up
```

### VPS (provisionamento completo)

```bash
# Na VPS Ubuntu limpa:
git clone https://github.com/brazwed/Database.git
cd Database
sudo ./setup.sh
# Escolhe [N]ova VPS → seleciona banco → tudo pronto
```

## Comandos Makefile

```bash
# Por banco
make db-postgres/up       # iniciar
make db-postgres/down     # parar
make db-postgres/logs     # logs
make db-postgres/psql     # shell psql
make db-postgres/info     # dados de conexão
make db-postgres/clean    # remover dados

make db-dragonfly/up
make db-dragonfly/info

# Global
make up        # todos
make down      # todos
make status    # todos
make info      # todos
make clean     # todos (DATA LOSS)
```

## Estrutura

```
Database/                        ← Este repo (ponte)
├── setup.sh                     # Provisionamento VPS interativo
├── Makefile                     # Atalhos para gerenciar bancos
│
├── db-postgres/                 ← Repo: db-postgres
│   ├── docker-compose.yml
│   ├── .env.example
│   ├── start.sh                 # up|down|restart|logs|status|shell|psql|clean
│   ├── info.sh                  # Mostra dados de conexão
│   └── README.md
│
└── db-dragonfly/                ← Repo: db-dragonfly
    ├── docker-compose.yml
    ├── .env.example
    ├── start.sh                 # up|down|restart|logs|status|shell|clean
    ├── info.sh                  # Mostra dados de conexão
    └── README.md
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

## Adicionar novo banco

1. Criar repo no GitHub (ex: `db-mongodb`)
2. Criar pasta local: `db-mongodb/`
3. Criar: `docker-compose.yml`, `.env.example`, `start.sh`, `info.sh`, `README.md`
4. Adicionar `db-mongodb` na variável `DATABASES` do Makefile
5. Adicionar entrada no `DATABASES` do `setup.sh`

Pronto — zero conflito com os outros bancos.
