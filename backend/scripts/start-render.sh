#!/bin/sh
set -eu

API_PORT="${PORT:-8080}"

echo "[Render] Running database migrations"
alembic -c migrations/alembic.ini upgrade head

echo "[Render] Starting FastAPI on 0.0.0.0:${API_PORT}"
uvicorn app.main:app --host 0.0.0.0 --port "$API_PORT"
