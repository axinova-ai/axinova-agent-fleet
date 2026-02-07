#!/usr/bin/env bash
set -euo pipefail

SERVICE="${1:?Usage: $0 <service> <env>}"
ENV="${2:-dev}"

TIMEOUT="${TIMEOUT:-300}"  # 5 minutes
INTERVAL=10

echo "==> Waiting for $SERVICE ($ENV) health checks..."

# Determine health check URL based on service and env
case "$ENV" in
  dev)
    BASE_URL="https://${SERVICE}.axinova-dev.xyz"
    ;;
  stage)
    BASE_URL="https://${SERVICE}.axinova-stage.xyz"
    ;;
  prod)
    BASE_URL="https://${SERVICE}.axinova.ai"
    ;;
  *)
    echo "Error: Unknown environment: $ENV"
    exit 1
    ;;
esac

HEALTH_URL="${BASE_URL}/api/health"

echo "  Health endpoint: $HEALTH_URL"
echo "  Timeout: ${TIMEOUT}s"
echo ""

START_TIME=$(date +%s)

while true; do
  ELAPSED=$(($(date +%s) - START_TIME))

  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    echo "❌ Timeout waiting for health check"
    exit 1
  fi

  # Try health check
  if curl -sf --max-time 5 "$HEALTH_URL" >/dev/null 2>&1; then
    echo "✅ Health check passed"

    # Additional checks: verify service version
    VERSION=$(curl -sf "$HEALTH_URL" | jq -r '.version // "unknown"' 2>/dev/null || echo "unknown")
    echo "  Version: $VERSION"

    exit 0
  fi

  echo "→ Service not ready yet (${ELAPSED}s elapsed)..."
  sleep $INTERVAL
done
