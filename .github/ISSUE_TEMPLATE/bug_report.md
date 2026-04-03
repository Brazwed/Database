name: Bug Report
description: Report a bug or unexpected behavior
body:
  - type: markdown
    attributes:
      value: |
        Thanks for reporting a bug! Please fill out the fields below.
  - type: input
    id: os
    attributes:
      label: Operating System
      description: What OS are you running? (e.g. Ubuntu 24.04, Debian 12)
      placeholder: Ubuntu 24.04
    validations:
      required: true
  - type: input
    id: docker-version
    attributes:
      label: Docker Version
      description: Run `docker --version` and paste the output
      placeholder: Docker version 27.0.0, build abc123
    validations:
      required: true
  - type: dropdown
    id: database
    attributes:
      label: Database
      description: Which database is affected?
      multiple: true
      options:
        - PostgreSQL
        - MySQL
        - MariaDB
        - MongoDB
        - DragonflyDB
        - Valkey
        - Docker Installation
        - Backup/Restore
        - General/Menu
    validations:
      required: true
  - type: textarea
    id: what-happened
    attributes:
      label: What happened?
      description: Describe the bug and steps to reproduce
      placeholder: |
        1. Run `sudo ./setup.sh install postgres`
        2. See error...
    validations:
      required: true
  - type: textarea
    id: expected
    attributes:
      label: What did you expect?
      description: What should have happened instead?
    validations:
      required: true
  - type: textarea
    id: logs
    attributes:
      label: Relevant logs
      description: Paste output from `sudo ./setup.sh logs <db>` if applicable
      render: bash
