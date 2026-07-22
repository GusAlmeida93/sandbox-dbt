# ============================================================================
# Workbench image: Python 3.12 + uv + dbt + JupyterLab
#
# Layering strategy: DEPENDENCIES ARE BAKED, CODE IS MOUNTED.
#   * uv installs the locked environment into /opt/venv at build time.
#     /opt/venv lives OUTSIDE /workspace so the runtime bind mount of the repo
#     cannot shadow it.
#   * The repo itself is bind-mounted at /workspace by docker-compose, so code,
#     notebooks and the dbt project are live-editable without rebuilds.
#
# Bonus: because UV_PROJECT_ENVIRONMENT is set globally, you can re-sync
# dependencies into the running container without a rebuild:
#     docker compose exec workbench uv sync --frozen
# ============================================================================

FROM python:3.12-slim

# git: required for dbt packages installed from git repos. make: so the repo's
# Makefile also works from inside the container. Everything else ships as wheels.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git make \
    && rm -rf /var/lib/apt/lists/*

# uv static binary from the official multi-arch image. Pin the minor to match
# the uv that generates uv.lock on the host (lockfile format compatibility).
COPY --from=ghcr.io/astral-sh/uv:0.11 /uv /uvx /bin/

ENV UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    PATH="/opt/venv/bin:$PATH" \
    DBT_PROFILES_DIR=/workspace/jaffle_shop

WORKDIR /workspace

# Install dependencies from the lockfile only -- this layer IS the image.
# --frozen fails loudly if uv.lock is missing or stale (generate it on the
# host with `uv lock`); it never silently re-resolves.
COPY pyproject.toml uv.lock .python-version ./
RUN --mount=type=cache,target=/root/.cache/uv uv sync --frozen --no-dev

# Non-root user (uid 1000). Docker Desktop on macOS maps bind-mount ownership
# transparently; on a Linux host add `user: "${UID}:${GID}"` to the compose
# service instead.
RUN useradd -m -u 1000 dbt && chown -R dbt:dbt /opt/venv
USER dbt

EXPOSE 8888 8081

CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--ServerApp.root_dir=/workspace"]
