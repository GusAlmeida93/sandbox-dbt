# 02 · Environment setup

This repo is a self-contained dbt lab. One command brings up everything:

```bash
make init
```

## The moving parts

```
                         your machine (host)
┌──────────────────────────────────────────────────────────────────┐
│  docker compose                                                  │
│  ┌──────────────┐   ┌───────────────────────┐   ┌─────────────┐  │
│  │  postgres:17 │◀──│  workbench            │   │  adminer:5  │  │
│  │  (warehouse) │   │  JupyterLab + dbt     │   │  (DB UI)    │  │
│  │              │   │  + uv env @ /opt/venv │   │             │  │
│  └──────▲───────┘   │  repo @ /workspace    │   └──────▲──────┘  │
│         │           └───────────▲───────────┘          │         │
│   127.0.0.1:5432          127.0.0.1:8888         127.0.0.1:8080  │
│         │                 127.0.0.1:8081 (dbt docs)              │
└─────────┼────────────────────────────────────────────────────────┘
          │
   hybrid mode: dbt/psql/uv on the host talk to localhost:5432
```

| service | image | port | purpose |
|---|---|---|---|
| `postgres` | postgres:17 | 5432 | the warehouse; data in a named volume |
| `workbench` | built from [Dockerfile](../Dockerfile) | 8888, 8081 | JupyterLab, dbt CLI, python env |
| `adminer` | adminer:5 | 8080 | browse tables in a browser (server `postgres`, user/pass/db from `.env`) |

All ports bind to `127.0.0.1` only — nothing listens on your network.

## The two golden rules of this image

The [Dockerfile](../Dockerfile) encodes two decisions worth understanding
because they are the standard pattern for containerized Python dev:

1. **Dependencies are baked, code is mounted.** `uv sync --frozen` installs
   the locked environment into the image at build time; the repo is
   bind-mounted at `/workspace` at run time. Edit any model/notebook on the
   host → it's instantly live in the container. Change `pyproject.toml` →
   rebuild the image (`make build-image`), or hot-sync without a rebuild:
   `docker compose exec workbench uv sync --frozen`.

2. **The venv lives at `/opt/venv`, outside the mount.** If it lived in
   `/workspace/.venv`, the bind mount would shadow it at runtime and nothing
   would work. `UV_PROJECT_ENVIRONMENT=/opt/venv` makes uv install (and
   re-sync) there.

Related trap we dodged: the dbt project directory is `jaffle_shop/`, **not**
`dbt/` — a top-level `dbt/` directory would shadow the `dbt` Python package
the moment anything imports it with the repo root on `sys.path` (Jupyter puts
the cwd there), breaking `from dbt.cli.main import dbtRunner` mysteriously.

## uv in 60 seconds

[uv](https://docs.astral.sh/uv/) manages the Python side:

- [pyproject.toml](../pyproject.toml) declares dependencies (dbt-core 1.10.x,
  dbt-postgres, JupyterLab, jupysql, ...).
- [uv.lock](../uv.lock) pins the exact resolved versions. Generated/updated
  **on the host** with `uv lock`; the Docker build uses `--frozen` so it
  fails loudly instead of silently re-resolving.
- [.python-version](../.python-version) pins Python 3.12 — your host Python
  can be anything; uv fetches a managed 3.12 for local runs.

## Configuration flow: one `.env` to rule them all

`.env` (copied from [.env.example](../.env.example)) is read by three
consumers — this is the part worth actually understanding:

```
                 .env
                  │
   ┌──────────────┼────────────────────┐
   ▼              ▼                    ▼
docker compose   Makefile             python-dotenv
(interpolation   (-include .env       (scripts + notebooks
in compose.yml)   + export)            on the host)
```

The subtle bit is `DBT_HOST`/`DBT_PORT`:

- **Inside the container**, compose hardcodes `DBT_HOST=postgres`,
  `DBT_PORT=5432` — the warehouse's address *on the compose network*. These
  win over anything in `.env`.
- **On the host**, nothing injects those, so
  [profiles.yml](../jaffle_shop/profiles.yml) falls back to its `env_var()`
  defaults (`localhost:5432`), matching the published port.

Same profiles.yml, both worlds. One wart, documented in `.env.example`: if you
change `POSTGRES_PORT`, change `DBT_PORT` too — same port, seen from two sides.

## Hybrid mode (dbt on the host)

Docker only runs the warehouse; everything else works natively via uv:

```bash
uv sync                      # create .venv on the host (one time)
make dbt-build LOCAL=1       # dbt via `uv run`, hitting localhost:5432
cd jaffle_shop && uv run dbt run --select stg_orders   # or by hand
```

Every `make` dbt/data target accepts `LOCAL=1`.

## Daily driving

```bash
make up            # start services          make down   # stop (data kept)
make data          # load raw days 1-2       make nuke   # stop + DELETE volume
make dbt-build     # the everything command
make docs          # dbt docs at :8081       make db-shell  # psql
make notebook      # prints the Jupyter URL
make reset-all     # fresh start without touching the volume
make verify        # full end-to-end health check
make help          # everything else
```

JupyterLab: `http://localhost:8888/?token=dbt` (token from `.env`).

## Troubleshooting

| symptom | likely cause / fix |
|---|---|
| `connection refused` on 5432 | services down → `make up`; or another local Postgres owns the port → change `POSTGRES_PORT` **and** `DBT_PORT` in `.env` |
| `invalid hostPort: 5432   ` | inline comment/trailing space in `.env` — values must be bare (make and compose parse the file differently) |
| dbt says `Could not find profile named 'jaffle_shop'` | you're running dbt outside `jaffle_shop/` without `DBT_PROFILES_DIR` — use the make targets, or `cd jaffle_shop` |
| image build fails at `uv sync --frozen` | `uv.lock` missing/stale → run `uv lock` on the host, rebuild |
| notebooks can't reach the DB | kernel started before `.env` existed → restart kernel; check `DBT_HOST` (should be `postgres` in-container, `localhost` on host) |
| `dbt docs serve` unreachable | it must bind `0.0.0.0` in-container — use `make docs`, which passes `--host 0.0.0.0 --port 8081` |
| everything is weird | `make nuke && make init` — total rebuild takes ~2 minutes |

---
Next: [03 · Project structure](03_project_structure.md) — a guided tour of
every file in `jaffle_shop/`.
