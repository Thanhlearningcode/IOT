#!/usr/bin/env bash
# run_simulator.sh - Helper to launch the MQTT device simulator
#
# Options:
#   --install-deps      Install Python requirements before running
#   --python <binary>   Use custom python interpreter (default: python3)
#   --                  Pass subsequent arguments directly to the simulator (future use)

set -euo pipefail

PROJECT_ROOT=${PROJECT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
PYTHON_BIN="python3"
INSTALL_DEPS=0
FORWARD_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-deps)
      INSTALL_DEPS=1
      ;;
    --python)
      shift || { echo "[ERROR] --python requires a value" >&2; exit 1; }
      PYTHON_BIN=$1
      ;;
    --)
      shift
      FORWARD_ARGS=("$@")
      break
      ;;
    -h|--help|help)
      cat <<'EOF'
Usage: run_simulator.sh [options]

Options:
  --install-deps      Install simulator dependencies before running
  --python <binary>   Specify python interpreter (default: python3)
  --                  Pass the rest of arguments to sim_device.py

Environment:
  PROJECT_ROOT  Override repository root path detection
EOF
      exit 0
      ;;
    *)
      echo "[WARN] Unrecognized option $1 ignored" >&2
      ;;
  esac
  shift || true
done

SIM_REQUIREMENTS="$PROJECT_ROOT/sim_device_requirements.txt"
SIM_SCRIPT="$PROJECT_ROOT/sim_device.py"

if [[ ! -f "$SIM_SCRIPT" ]]; then
  echo "[ERROR] sim_device.py not found at $SIM_SCRIPT" >&2
  exit 1
fi

if [[ $INSTALL_DEPS -eq 1 ]]; then
  if [[ ! -f "$SIM_REQUIREMENTS" ]]; then
    echo "[ERROR] Requirements file missing at $SIM_REQUIREMENTS" >&2
    exit 1
  fi
  echo "[INFO] Installing simulator dependencies via $PYTHON_BIN -m pip ..."
  "$PYTHON_BIN" -m pip install --user -r "$SIM_REQUIREMENTS"
fi

cd "$PROJECT_ROOT"
echo "[INFO] Starting simulator with $PYTHON_BIN $SIM_SCRIPT"
exec "$PYTHON_BIN" "$SIM_SCRIPT" "${FORWARD_ARGS[@]}"
