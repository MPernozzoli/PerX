#!/bin/sh
set -eu

API_PORT="${PORT:-8080}"
WA_PORT="${WA_BRIDGE_PORT:-5002}"
WA_SESSION_PATH="${SESSION_PATH:-/var/data/openwa-sessions}"

mkdir -p "$WA_SESSION_PATH"

echo "[Render] Running database migrations"
alembic -c migrations/alembic.ini upgrade head

echo "[Render] Starting WA bridge on 127.0.0.1:${WA_PORT}"
(
  cd /app/perx_wa_bridge
  PORT="$WA_PORT" \
  HUB_URL="http://127.0.0.1:${API_PORT}/api/v1/hub" \
  SESSION_PATH="$WA_SESSION_PATH" \
  CHROME_EXECUTABLE_PATH="${CHROME_EXECUTABLE_PATH:-/usr/bin/chromium}" \
  WA_BRIDGE_INTERNAL_TOKEN="${WA_BRIDGE_INTERNAL_TOKEN:-}" \
  npm start
) &
WA_PID="$!"

trap 'echo "[Render] Stopping WA bridge"; kill "$WA_PID" 2>/dev/null || true' INT TERM EXIT

echo "[Render] Starting FastAPI on 0.0.0.0:${API_PORT}"
uvicorn app.main:app --host 0.0.0.0 --port "$API_PORT"
