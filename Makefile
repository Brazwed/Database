.PHONY: help up down status logs clean info

DATABASES := db-postgres db-dragonfly

# --- Root commands ---

help: ## Show available commands
	@echo ""
	@echo "Per database:"
	@for db in $(DATABASES); do \
		echo "  make $$db/up       Start $$db"; \
		echo "  make $$db/down     Stop $$db"; \
		echo "  make $$db/restart  Restart $$db"; \
		echo "  make $$db/logs     Follow $$db logs"; \
		echo "  make $$db/status   $$db container status"; \
		echo "  make $$db/shell    Shell in $$db container"; \
		echo "  make $$db/clean    Remove $$db data (DATA LOSS)"; \
		echo "  make $$db/info     Show $$db connection info"; \
	done
	@echo "PostgreSQL extra:"
	@echo "  make db-postgres/psql      Open psql shell"
	@echo ""
	@echo "Global:"
	@echo "  make up              Start all databases"
	@echo "  make down            Stop all databases"
	@echo "  make status          Status of all databases"
	@echo "  make logs            Logs from all databases"
	@echo "  make info            Connection info for all"
	@echo "  make clean           Remove all data (DATA LOSS)"
	@echo ""

up: ## Start all databases
	@for db in $(DATABASES); do [ -f ./$$db/start.sh ] && ./$$db/start.sh up || echo "[skip] $$db not found"; done

down: ## Stop all databases
	@for db in $(DATABASES); do [ -f ./$$db/start.sh ] && ./$$db/start.sh down || true; done

status: ## Status of all databases
	@for db in $(DATABASES); do [ -f ./$$db/start.sh ] && { echo ""; echo "=== $$db ==="; ./$$db/start.sh status; }; done

logs: ## Logs from all databases (tail last 20 lines)
	@for db in $(DATABASES); do [ -f ./$$db/docker-compose.yml ] && { echo ""; echo "=== $$db ==="; docker compose -f ./$$db/docker-compose.yml logs --tail=20; }; done

info: ## Connection info for all databases
	@for db in $(DATABASES); do [ -f ./$$db/info.sh ] && ./$$db/info.sh 2>/dev/null || echo "[skip] $$db not configured"; done

clean: ## Remove all data (DATA LOSS)
	@for db in $(DATABASES); do \
		if [ -f ./$$db/start.sh ]; then \
			echo ""; \
			echo "=== $$db ==="; \
			./$$db/start.sh clean; \
		fi; \
	done

# --- Dynamic per-database targets ---

define DB_RULE
.PHONY: $(1)/up $(1)/down $(1)/restart $(1)/logs $(1)/status $(1)/shell $(1)/clean $(1)/info

$(1)/up:       ; ./$1/start.sh up
$(1)/down:     ; ./$1/start.sh down
$(1)/restart:  ; ./$1/start.sh restart
$(1)/logs:     ; ./$1/start.sh logs
$(1)/status:   ; ./$1/start.sh status
$(1)/shell:    ; ./$1/start.sh shell
$(1)/clean:    ; ./$1/start.sh clean
$(1)/info:     ; ./$1/info.sh
endef

$(foreach db,$(DATABASES),$(eval $(call DB_RULE,$(db))))

# --- PostgreSQL extra ---

db-postgres/psql: ## Open psql shell
	./db-postgres/start.sh psql
