#!/usr/bin/env bash
# run_end_to_end.sh - Orchestrate the full IoT pipeline locally (Docker stack + simulator + API check)
#
# This helper will:
#   1. Start or ensure the Docker stack is running
#   2. Wait for Postgres and FastAPI to become healthy
#   3. Optionally install simulator dependencies
#   4. Run the Python device simulator for a bounded duration
#   5. Fetch telemetry back from the API to prove data persisted
#   6. Print next steps for launching the Flutter app (manual)
#
# Usage examples:
#   bash scripts/run_end_to_end.sh
#   bash scripts/run_end_to_end.sh --duration 45 --install-sim-deps
#   COMPOSE_CMD="docker compose" bash scripts/run_end_to_end.sh --skip-build
#
# Available options:
#   --duration <seconds>      How long to run the simulator (default: 20)
#   --install-sim-deps        Install Python requirements for the simulator before running
#   --python <binary>         Python interpreter to use (default: python3)
#   --skip-build              Do not force Docker image rebuild on start
#   --no-simulator            Skip simulator run (still starts stack and runs API check)
#   --no-api-check            Skip login + telemetry verification (just run simulator)
#   --help                    Show this help

set -euo pipefail

usage() {
  sed -n '1,/^set -euo pipefail/p' "$0" | sed 's/^# \{0,1\}//'
}

PROJECT_ROOT=${PROJECT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
COMPOSE_CMD=${COMPOSE_CMD:-docker compose}
API_BASE=${API_BASE:-http://localhost:8000}
DB_SERVICE=${DB_SERVICE:-db}
API_SERVICE=${API_SERVICE:-api}
SIM_DURATION=20
INSTALL_SIM_DEPS=0
PYTHON_BIN=python3
SKIP_BUILD=0
RUN_SIMULATOR=1
RUN_API_CHECK=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration)
      shift || { echo "[ERROR] --duration needs a value" >&2; exit 1; }
      SIM_DURATION=$1
      ;;
    --install-sim-deps)
      INSTALL_SIM_DEPS=1
      ;;
    --python)
      shift || { echo "[ERROR] --python needs a value" >&2; exit 1; }
      PYTHON_BIN=$1
      ;;
    --skip-build)
      SKIP_BUILD=1
      ;;
    --no-simulator)
      RUN_SIMULATOR=0
      ;;
    --no-api-check)
      RUN_API_CHECK=0
      ;;
    --help|-h|help)
      usage
      exit 0
      ;;
    *)
      echo "[WARN] Unknown option: $1" >&2
      ;;
  esac
  shift || true
done

SIM_REQUIREMENTS="$PROJECT_ROOT/sim_device_requirements.txt"
SIM_SCRIPT="$PROJECT_ROOT/sim_device.py"
DEV_STACK_SCRIPT="$PROJECT_ROOT/scripts/dev_stack.sh"

if [[ ! -f "$SIM_SCRIPT" ]]; then
  echo "[ERROR] sim_device.py not found at $SIM_SCRIPT" >&2
  exit 1
fi

if ! command -v $PYTHON_BIN >/dev/null 2>&1; then
  echo "[ERROR] Python interpreter '$PYTHON_BIN' not found in PATH" >&2
  exit 1
fi

compose() {
  (cd "$PROJECT_ROOT" && $COMPOSE_CMD "$@")
}

if [[ $SKIP_BUILD -eq 1 ]]; then
  echo "[INFO] Starting Docker stack (skip build) ..."
  compose up -d
else
  echo "[INFO] Starting Docker stack with build ..."
  compose up -d --build
fi

wait_for_service() {
  local service=$1
  local cmd=$2
  local timeout=${3:-60}
  local interval=${4:-3}
  local elapsed=0
  while (( elapsed < timeout )); do
    if compose exec -T "$service" sh -c "$cmd" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done
  return 1
}

if ! wait_for_service "$DB_SERVICE" 'pg_isready -U app -d app'; then
  echo "[ERROR] Database did not become ready in time" >&2
  exit 1
fi

echo "[INFO] Database is ready. Waiting for FastAPI ..."
wait_for_http() {
  local url=$1
  local timeout=${2:-60}
  local interval=${3:-3}
  local elapsed=0
  while (( elapsed < timeout )); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done
  return 1
}

if ! wait_for_http "$API_BASE/docs"; then
  echo "[ERROR] API did not become ready in time" >&2
  exit 1
fi

echo "[INFO] FastAPI is ready."

if (( INSTALL_SIM_DEPS )); then
  if [[ ! -f "$SIM_REQUIREMENTS" ]]; then
    echo "[ERROR] Simulator requirements file missing at $SIM_REQUIREMENTS" >&2
    exit 1
  fi
  echo "[INFO] Installing simulator dependencies ..."
  "$PYTHON_BIN" -m pip install --user -r "$SIM_REQUIREMENTS"
fi

ACCESS_TOKEN=""
if (( RUN_API_CHECK )); then
  echo "[INFO] Requesting JWT from /auth/login ..."
  LOGIN_PAYLOAD='{"email":"demo@example.com","password":"x"}'
  set +e
  LOGIN_RESP=$(curl -sS -X POST "$API_BASE/auth/login" \
    -H 'Content-Type: application/json' \
    -d "$LOGIN_PAYLOAD")
  CURL_EXIT=$?
  set -e
  if [[ $CURL_EXIT -ne 0 ]]; then
    echo "[ERROR] Failed to contact API for login." >&2
    echo "$LOGIN_RESP" >&2
    exit 1
  fi
  ACCESS_TOKEN=$(printf '%s' "$LOGIN_RESP" | "$PYTHON_BIN" -c 'import sys,json
try:
    print(json.load(sys.stdin)["access_token"])
except Exception as exc:
    raise SystemExit(exc)
') || {
    echo "[ERROR] Could not parse access token from login response:" >&2
    echo "$LOGIN_RESP" >&2
    exit 1
  }
  echo "[INFO] Received JWT token."
fi

if (( RUN_SIMULATOR )); then
  if ! command -v timeout >/dev/null 2>&1; then
    echo "[ERROR] 'timeout' command is required but not found" >&2
    exit 1
  fi
  echo "[INFO] Running simulator for ${SIM_DURATION}s ..."
  set +e
  timeout --preserve-status --signal INT --kill-after=$((SIM_DURATION+5))s \
    "$SIM_DURATION"s "$PYTHON_BIN" "$SIM_SCRIPT"
  SIM_EXIT=$?
  set -e
  if [[ $SIM_EXIT -ne 0 && $SIM_EXIT -ne 124 ]]; then
    echo "[WARN] Simulator exited with status $SIM_EXIT" >&2
  else
    echo "[INFO] Simulator completed." >&2
  fi
else
  echo "[INFO] Simulator execution skipped by flag."
fi

if (( RUN_API_CHECK )); then
  echo "[INFO] Fetching telemetry for device dev-01 ..."
  TELEMETRY_JSON=$(curl -sS "$API_BASE/telemetry/dev-01" \
    -H "Authorization: Bearer $ACCESS_TOKEN")
  echo "$TELEMETRY_JSON" | "$PYTHON_BIN" - <<'PY'
import json, sys
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError as exc:
    print('[WARN] Could not decode telemetry JSON:', exc, file=sys.stderr)
    sys.exit(0)
if isinstance(data, list):
    print('[INFO] Received', len(data), 'telemetry rows. Showing up to first 3:')
    for row in data[:3]:
        print(json.dumps(row, indent=2))
else:
    print(json.dumps(data, indent=2))
PY
fi

echo
compose ps

echo "\n[INFO] Pipeline is ready. To explore data visually:" 
if command -v flutter >/dev/null 2>&1; then
  echo "  -> Launch Flutter Web UI: (cd flutter_app && flutter run -d chrome)"
else
  echo "  -> Install Flutter SDK, then run: (cd flutter_app && flutter run -d chrome)"
fi

echo "[INFO] You can connect to pgAdmin at http://localhost:5050 (admin@local.test / ChangeMe!)."

echo "[DONE] End-to-end run completed."
