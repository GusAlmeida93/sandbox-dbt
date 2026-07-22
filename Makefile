# ============================================================================
# sandbox-dbt -- convenience commands
#
# Default execution mode is INSIDE DOCKER (the workbench container).
# Append LOCAL=1 to run dbt / python on the host instead (hybrid mode:
# postgres in Docker, everything else via uv on the host):
#
#     make dbt-build          # dbt build inside the workbench container
#     make dbt-build LOCAL=1  # dbt build on the host via `uv run`
# ============================================================================

-include .env
export

COMPOSE := docker compose

ifdef LOCAL
DBT := cd jaffle_shop && uv run dbt
PY  := uv run python
else
DBT := $(COMPOSE) exec -w /workspace/jaffle_shop workbench dbt
PY  := $(COMPOSE) exec workbench python
endif

.DEFAULT_GOAL := help

.PHONY: help init up down nuke build-image logs ps \
        data data-day data-reset reset-all \
        dbt-deps dbt-debug dbt-seed dbt-run dbt-test dbt-build dbt-snapshot dbt-clean \
        docs docs-static db-shell notebook nb-exec nb-clean verify lint

help: ## Show this help
	@grep -hE '^[a-zA-Z_%-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

# --- lifecycle --------------------------------------------------------------

init: ## One-shot bootstrap: .env, lock, build, up, deps, data, dbt build
	@test -f .env || cp .env.example .env
	@test -f uv.lock || uv lock
	$(COMPOSE) build
	$(COMPOSE) up -d --wait
	$(MAKE) dbt-deps
	$(MAKE) data
	$(MAKE) dbt-build
	@echo ""
	@echo "  JupyterLab -> http://localhost:$${JUPYTER_PORT:-8888}/?token=$${JUPYTER_TOKEN:-dbt}"
	@echo "  Adminer    -> http://localhost:$${ADMINER_PORT:-8080}   (server: postgres, user/pass/db from .env)"
	@echo "  dbt docs   -> make docs, then http://localhost:$${DBT_DOCS_PORT:-8081}"

up: ## Start all services (waits for health)
	$(COMPOSE) up -d --wait

down: ## Stop all services (database volume is preserved)
	$(COMPOSE) down

nuke: ## Stop everything and DELETE the database volume
	$(COMPOSE) down -v

build-image: ## Rebuild the workbench image (after changing pyproject/uv.lock)
	$(COMPOSE) build workbench

logs: ## Tail service logs
	$(COMPOSE) logs -f --tail=100

ps: ## Show service status
	$(COMPOSE) ps

# --- synthetic raw data -----------------------------------------------------

data: ## Load synthetic raw data, days 1-2 (skips already-loaded days)
	$(PY) scripts/generate_data.py --days 2

data-day: ## (Re)load one specific day: make data-day DAY=3
	$(PY) scripts/generate_data.py --day $(DAY)

data-reset: ## Drop and recreate the raw schema (empty)
	$(PY) scripts/generate_data.py --reset

reset-all: ## Fresh start: drop raw AND all dbt-built dev schemas (keeps the volume)
	$(MAKE) data-reset
	$(COMPOSE) exec postgres psql -U $${POSTGRES_USER:-dbt} -d $${POSTGRES_DB:-jaffle_shop} \
		-c "drop schema if exists dev, dev_staging, dev_marts, dev_seeds, dev_snapshots, dev_dbt_test__audit, audit cascade"

# --- dbt --------------------------------------------------------------------

dbt-deps: ## Install dbt packages (dbt_utils, dbt_expectations, codegen)
	$(DBT) deps

dbt-debug: ## Validate project setup + warehouse connection
	$(DBT) debug

dbt-seed: ## Load seed CSVs
	$(DBT) seed

dbt-run: ## Run all models
	$(DBT) run

dbt-test: ## Run all tests
	$(DBT) test

dbt-build: ## Seed + run + test + snapshot, in DAG order
	$(DBT) build

dbt-snapshot: ## Run snapshots
	$(DBT) snapshot

dbt-clean: ## Remove target/, dbt_packages/, logs/
	$(DBT) clean

dbt-%: ## Passthrough: make dbt-compile, dbt-parse, dbt-ls ...
	$(DBT) $*

# --- dbt docs ---------------------------------------------------------------

docs: ## Generate + serve dbt docs at http://localhost:8081 (Ctrl+C to stop)
	$(DBT) docs generate
	$(DBT) docs serve --host 0.0.0.0 --port 8081 --no-browser

docs-static: ## Generate a single self-contained docs file (target/static_index.html)
	$(DBT) docs generate --static
	@echo "open jaffle_shop/target/static_index.html"

# --- warehouse access -------------------------------------------------------

db-shell: ## psql shell into the warehouse
	$(COMPOSE) exec postgres psql -U $${POSTGRES_USER:-dbt} -d $${POSTGRES_DB:-jaffle_shop}

# --- notebooks --------------------------------------------------------------

notebook: ## Print the JupyterLab URL
	@echo "http://localhost:$${JUPYTER_PORT:-8888}/?token=$${JUPYTER_TOKEN:-dbt}"

nb-exec: ## Execute all notebooks headlessly inside the container (CI-style check)
	$(COMPOSE) exec workbench bash -c '\
		mkdir -p notebooks/executed && \
		for nb in notebooks/0*.ipynb; do \
			echo "=== executing $$nb"; \
			jupyter nbconvert --to notebook --execute \
				--output-dir notebooks/executed \
				--ExecutePreprocessor.timeout=600 "$$nb" || exit 1; \
		done'

nb-clean: ## Strip notebook outputs (run before committing)
	$(COMPOSE) exec workbench jupyter nbconvert --clear-output --inplace notebooks/0*.ipynb

# --- meta -------------------------------------------------------------------

verify: ## Full end-to-end check: clean slate, dbt build, day 3, rebuild, notebooks
	$(MAKE) up
	$(MAKE) dbt-deps
	$(MAKE) reset-all
	$(MAKE) data
	$(MAKE) dbt-build
	$(MAKE) data-day DAY=3
	$(MAKE) dbt-build
	$(MAKE) nb-exec
	@echo ""
	@echo "verify: ALL GREEN"

lint: ## Ruff-check the python scripts
	uv run ruff check scripts
