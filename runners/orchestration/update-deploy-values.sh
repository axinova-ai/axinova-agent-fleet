#!/usr/bin/env bash
set -euo pipefail

SERVICE="${1:?Usage: $0 <service> <env> <image-tag>}"
ENV="${2:?Missing env}"
IMAGE_TAG="${3:?Missing image-tag}"

AXINOVA_DIR="/Users/weixia/axinova"
DEPLOY_DIR="$AXINOVA_DIR/axinova-deploy"

BACKEND_VALUES="$DEPLOY_DIR/envs/$ENV/apps/${SERVICE}-go/values.yaml"
FRONTEND_VALUES="$DEPLOY_DIR/envs/$ENV/apps/${SERVICE}-web/values.yaml"

echo "==> Updating deployment values for $SERVICE ($ENV)"

# Update backend values.yaml
if [[ -f "$BACKEND_VALUES" ]]; then
  echo "→ Updating backend values: $BACKEND_VALUES"

  # Use yq to update image tag
  if command -v yq &>/dev/null; then
    yq eval ".image.tag = \"$IMAGE_TAG\"" -i "$BACKEND_VALUES"
  else
    # Fallback: sed
    sed -i.bak "s/tag: .*/tag: \"$IMAGE_TAG\"/" "$BACKEND_VALUES"
    rm -f "${BACKEND_VALUES}.bak"
  fi

  echo "  Set image.tag = $IMAGE_TAG"
else
  echo "Warning: Backend values.yaml not found: $BACKEND_VALUES"
fi

# Update frontend values.yaml (if exists)
if [[ -f "$FRONTEND_VALUES" ]]; then
  echo "→ Updating frontend values: $FRONTEND_VALUES"

  if command -v yq &>/dev/null; then
    yq eval ".image.tag = \"$IMAGE_TAG\"" -i "$FRONTEND_VALUES"
  else
    sed -i.bak "s/tag: .*/tag: \"$IMAGE_TAG\"/" "$FRONTEND_VALUES"
    rm -f "${FRONTEND_VALUES}.bak"
  fi

  echo "  Set image.tag = $IMAGE_TAG"
fi

echo "✅ Values updated"
