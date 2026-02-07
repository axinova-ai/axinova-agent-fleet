#!/usr/bin/env bash
set -euo pipefail

TASK="${1:-}"
REPO_PATH="${2:-.}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Show usage if no task provided
if [[ -z "$TASK" ]]; then
  cat <<EOF
Usage: $0 <task> [repo-path]

Tasks:
  backend       Run Go backend CI (tests, vet, govulncheck, sqlc)
  frontend      Run Vue frontend CI (type check, build, lint)
  docker        Build Docker image (optionally push with PUSH=true)
  full-stack    Run backend + frontend CI in parallel

Examples:
  $0 backend /Users/weixia/axinova/axinova-home-go
  $0 frontend /Users/weixia/axinova/axinova-home-web
  $0 full-stack /Users/weixia/axinova/axinova-home
  PUSH=true $0 docker /Users/weixia/axinova/axinova-home-go
EOF
  exit 2
fi

# Validate repo path
if [[ ! -d "$REPO_PATH" ]]; then
  echo "Error: Repository path does not exist: $REPO_PATH"
  exit 1
fi

# Run task
case "$TASK" in
  backend)
    "$SCRIPT_DIR/tasks/go_backend.sh" "$REPO_PATH"
    ;;
  frontend)
    "$SCRIPT_DIR/tasks/vue_frontend.sh" "$REPO_PATH"
    ;;
  docker)
    PUSH="${PUSH:-false}"
    "$SCRIPT_DIR/tasks/docker_build.sh" "$REPO_PATH" "$PUSH"
    ;;
  full-stack)
    # Extract base name (remove -go or -web suffix)
    BASE_PATH="${REPO_PATH%-go}"
    BASE_PATH="${BASE_PATH%-web}"

    BACKEND_PATH="${BASE_PATH}-go"
    FRONTEND_PATH="${BASE_PATH}-web"

    if [[ ! -d "$BACKEND_PATH" ]]; then
      echo "Error: Backend repo not found: $BACKEND_PATH"
      exit 1
    fi

    if [[ ! -d "$FRONTEND_PATH" ]]; then
      echo "Error: Frontend repo not found: $FRONTEND_PATH"
      exit 1
    fi

    echo "==> Running full-stack CI"
    echo "  Backend: $BACKEND_PATH"
    echo "  Frontend: $FRONTEND_PATH"
    echo ""

    # Run in parallel
    "$SCRIPT_DIR/tasks/go_backend.sh" "$BACKEND_PATH" &
    BACKEND_PID=$!

    "$SCRIPT_DIR/tasks/vue_frontend.sh" "$FRONTEND_PATH" &
    FRONTEND_PID=$!

    # Wait for both
    FAILED=0
    if ! wait $BACKEND_PID; then
      echo "❌ Backend CI failed"
      FAILED=1
    fi

    if ! wait $FRONTEND_PID; then
      echo "❌ Frontend CI failed"
      FAILED=1
    fi

    if [[ $FAILED -eq 0 ]]; then
      echo ""
      echo "✅ Full-stack CI passed"
    else
      exit 1
    fi
    ;;
  *)
    echo "Error: Unknown task: $TASK"
    echo "Run '$0' without arguments for usage"
    exit 2
    ;;
esac
