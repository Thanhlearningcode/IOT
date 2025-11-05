#!/usr/bin/env bash
# dev_stack.sh - Convenience wrapper to control the local Docker stack
# Usage: bash scripts/dev_stack.sh <start|stop|restart|logs|ps|status|shell>
# Optional env:
#   COMPOSE_CMD   - override docker compose command (default "docker compose")
#   PROJECT_ROOT  - override repository root detection
#
# Examples:
#   bash scripts/dev_stack.sh start
#   bash scripts/dev_stack.sh logs api
#   bash scripts/dev_stack.sh shell api sh

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: dev_stack.sh <command> [args]
Commands:
  start [service...]   Start the stack (build on first run) for optional services (default all)
  stop                 Stop stack (docker compose down)
  restart              Restart stack (down && up)
  logs [service...]    Tail logs (default follow all services)
  ps                   Show container status
  status               Alias for ps
  shell <service> [cmd]
                       Execute interactive shell (default /bin/sh) inside service container
EOF
}

PROJECT_ROOT=${PROJECT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
COMPOSE_CMD=${COMPOSE_CMD:-docker compose}
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "[ERROR] docker-compose.yml not found at $COMPOSE_FILE" >&2
  exit 1
fi

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

cmd=$1
shift || true

compose() {
  (cd "$PROJECT_ROOT" && $COMPOSE_CMD "$@")
}

case "$cmd" in
  start)
    if [[ $# -gt 0 ]]; then
      compose up -d "$@"
    else
      compose up -d --build
    fi
    ;;
  stop)
    compose down
    ;;
  restart)
    compose down
    compose up -d
    ;;
  logs)
    if [[ $# -gt 0 ]]; then
      compose logs -f "$@"
    else
      compose logs -f
    fi
    ;;
  ps|status)
    compose ps
    ;;
  shell)
    if [[ $# -lt 1 ]]; then
      echo "[ERROR] shell command needs a service name" >&2
      usage >&2
      exit 1
    fi
    service=$1
    shift || true
    if [[ $# -gt 0 ]]; then
      compose exec "$service" "$@"
    else
      compose exec "$service" /bin/sh
    fi
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "[ERROR] Unknown command: $cmd" >&2
    usage >&2
    exit 1
    ;;
 esac
