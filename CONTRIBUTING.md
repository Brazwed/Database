# Contributing to Database Toolkit

Thank you for your interest! Here's how to contribute:

## Adding a New Database

1. Create a GitHub repo named `db-<name>`
2. Add to `dbs/db-<name>/` with:
   - `docker-compose.yml`
   - `.env.example`
   - `README.md`
3. Add entry to `DATABASES` in `setup.sh`
4. Add case in `show_info` in `lib/database.sh`
5. Add translation strings in `lib/lang/en_US.sh` and `lib/lang/pt_BR.sh`

## Reporting Bugs

Open an issue with:
- What you were trying to do
- What happened
- What you expected
- Your OS and Docker version

## Pull Requests

- Keep commits focused and descriptive
- Test on Ubuntu/Debian before submitting
- Follow existing code style
