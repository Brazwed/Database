# Database Toolkit v1.0

Docker containers pre-configured for databases. One script for everything.

Multi-language: English 🇺🇸 | Português 🇧🇷

## Databases Available

### Persistent (disk)

| Database | Port | Repo |
|----------|------|------|
| PostgreSQL 16 | 5432 | [db-postgres](https://github.com/Brazwed/db-postgres) |
| MySQL 8 | 3306 | [db-mysql](https://github.com/Brazwed/db-mysql) |
| MariaDB 11 | 3307 | [db-mariadb](https://github.com/Brazwed/db-mariadb) |
| MongoDB 7 | 27017 | [db-mongodb](https://github.com/Brazwed/db-mongodb) |

### In-Memory Cache (RAM)

| Database | Port | Repo |
|----------|------|------|
| DragonflyDB | 6379 | [db-dragonfly](https://github.com/Brazwed/db-dragonfly) |
| Valkey 8 | 6380 | [db-valkey](https://github.com/Brazwed/db-valkey) |

## Quick Start

```bash
git clone --recurse-submodules https://github.com/Brazwed/Database.git
cd Database
sudo ./setup.sh
```

## Commands

### Interactive Menu

```bash
sudo ./setup.sh
```

### Direct Args

```bash
# Install
sudo ./setup.sh install docker              # install Docker
sudo ./setup.sh install postgres            # install PostgreSQL
sudo ./setup.sh install postgres mysql      # install multiple
sudo ./setup.sh install postgres --yes      # non-interactive (skip confirms)

# Manage
sudo ./setup.sh up postgres                 # start
sudo ./setup.sh down postgres               # stop
sudo ./setup.sh restart postgres            # restart
sudo ./setup.sh update postgres             # git pull + up/restart
sudo ./setup.sh status                      # status of all
sudo ./setup.sh status postgres             # status of 1
sudo ./setup.sh logs postgres               # live logs
sudo ./setup.sh shell postgres              # shell in container
sudo ./setup.sh psql                        # shortcut: psql postgres
sudo ./setup.sh mysql                       # shortcut: mysql
sudo ./setup.sh mariadb                     # shortcut: mariadb
sudo ./setup.sh mongo                       # shortcut: mongosh
sudo ./setup.sh valkey                      # shortcut: valkey-cli
sudo ./setup.sh remove postgres             # remove database

# Backups
sudo ./setup.sh backup                      # backup everything
sudo ./setup.sh backup postgres             # backup 1 database
sudo ./setup.sh backups                     # list all backups
sudo ./setup.sh rollback postgres           # restore latest
sudo ./setup.sh rollback postgres 2026-03-31_15-00-00  # restore specific

# Utilities
sudo ./setup.sh detect                      # detect VPS state
sudo ./setup.sh lang pt                     # change language (pt/en)
sudo ./setup.sh --version                   # show version
sudo ./setup.sh --help                      # show help
```

## Default Connection

### PostgreSQL 16

```
Host:     localhost
Port:     5432
User:     postgres
Pass:     postgres_dev_2026
Database: devdb

psql -h localhost -p 5432 -U postgres -d devdb
```

### MySQL 8

```
Host:     localhost
Port:     3306
User:     mysql_user
Pass:     mysql_dev_2026
Database: devdb

mysql -h localhost -P 3306 -u mysql_user -pmysql_dev_2026 devdb
```

### MariaDB 11

```
Host:     localhost
Port:     3307
User:     mariadb_user
Pass:     mariadb_dev_2026
Database: devdb

mysql -h localhost -P 3307 -u mariadb_user -pmariadb_dev_2026 devdb
```

### MongoDB 7

```
Host:     localhost
Port:     27017
User:     mongodb_user
Pass:     mongodb_dev_2026

mongosh mongodb://mongodb_user:mongodb_dev_2026@localhost:27017/devdb
```

### DragonflyDB

```
Host:     localhost
Port:     6379
Pass:     dragonfly_dev_2026

redis-cli -h localhost -p 6379 -a dragonfly_dev_2026
```

### Valkey 8

```
Host:     localhost
Port:     6380
Pass:     valkey_dev_2026

redis-cli -h localhost -p 6380 -a valkey_dev_2026
```

## Structure

```
Database/
├── setup.sh               ← Main entry point
├── README.md
│
├── lib/
│   ├── utils.sh           ← helpers, colors, logging, spinner
│   ├── menu.sh            ← interactive menu
│   ├── database.sh        ← database operations
│   ├── detection.sh       ← VPS detection
│   ├── backup.sh          ← backup system
│   ├── firewall.sh        ← firewall management
│   ├── docker.sh          ← Docker installation
│   └── lang/
│       ├── en_US.sh       ← English (default)
│       └── pt_BR.sh       ← Portuguese
│
└── dbs/
    ├── db-postgres/       ← PostgreSQL 16
    ├── db-mysql/          ← MySQL 8
    ├── db-mariadb/        ← MariaDB 11
    ├── db-mongodb/        ← MongoDB 7
    ├── db-dragonfly/      ← DragonflyDB
    └── db-valkey/         ← Valkey 8
```

## Add a New Database

1. Create a GitHub repo (e.g. `db-redis`)
2. Create subfolder: `dbs/db-redis/`
3. Create: `docker-compose.yml`, `.env.example`, `README.md`
4. Add to `DATABASES` variable in `setup.sh`
5. Add case in `show_info` in `lib/database.sh`
6. Add translation strings in `lib/lang/en_US.sh` and `lib/lang/pt_BR.sh`

## Language

Language is auto-detected from the system. To change:

```bash
sudo ./setup.sh lang pt     # Portuguese
sudo ./setup.sh lang en     # English
```

Saves to `~/.db-toolkit/lang`. Language changes on next menu use.

## Features

- Animated spinner during actions
- Colored status (green ● running, red ● stopped, yellow ● not installed)
- Automatic backup before every destructive action
- VPS detection (Docker, ports, firewall)
- Stdin flush (Enter/keystroke before menu doesn't cause bugs)
- Non-interactive mode (`--yes`) for scripts and CI
- Multi-language (English + Portuguese)

## By Brazwed

https://github.com/Brazwed/Database
