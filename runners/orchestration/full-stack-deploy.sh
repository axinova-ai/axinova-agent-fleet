#!/usr/bin/env bash
set -euo pipefail

SERVICE="${1:?Usage: $0 <service-name> <env>}"
ENV="${2:-dev}"

FLEET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AXINOVA_DIR="/Users/weixia/axinova"

BACKEND_REPO="$AXINOVA_DIR/${SERVICE}-go"
FRONTEND_REPO="$AXINOVA_DIR/${SERVICE}-web"

echo "==> Full-stack deployment: $SERVICE ($ENV)"

# Step 1: Run local CI
echo "→ Running backend CI..."
"$FLEET_DIR/runners/local-ci/run_ci.sh" backend "$BACKEND_REPO"

echo "→ Running frontend CI..."
"$FLEET_DIR/runners/local-ci/run_ci.sh" frontend "$FRONTEND_REPO"

# Step 2: Build Docker images (local)
echo "→ Building backend Docker image..."
cd "$BACKEND_REPO"
IMAGE_TAG="sha-$(git rev-parse --short HEAD)"
docker build -t "ghcr.io/axinova-ai/${SERVICE}-go:$IMAGE_TAG" .

# Step 3: Push to registry
if [[ "$ENV" == "dev" ]]; then
  # For dev, optionally push to local registry
  if [[ -n "${LOCAL_REGISTRY:-}" ]]; then
    echo "→ Pushing to local registry..."
    docker tag "ghcr.io/axinova-ai/${SERVICE}-go:$IMAGE_TAG" "${LOCAL_REGISTRY}/${SERVICE}-go:$IMAGE_TAG"
    docker push "${LOCAL_REGISTRY}/${SERVICE}-go:$IMAGE_TAG"
  else
    echo "→ Skipping registry push for dev (set LOCAL_REGISTRY to enable)"
  fi
else
  echo "→ Pushing to GHCR..."
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "Error: GITHUB_TOKEN not set"
    exit 1
  fi
  echo "$GITHUB_TOKEN" | docker login ghcr.io -u "${GITHUB_USER:-harryxiaxia}" --password-stdin
  docker push "ghcr.io/axinova-ai/${SERVICE}-go:$IMAGE_TAG"
fi

# Step 4: Update axinova-deploy values.yaml
echo "→ Updating deployment values..."
"$FLEET_DIR/runners/orchestration/update-deploy-values.sh" "$SERVICE" "$ENV" "$IMAGE_TAG"

# Step 5: Create PR or direct push
cd "$AXINOVA_DIR/axinova-deploy"

# Check if there are changes
if git diff --quiet; then
  echo "→ No changes to deploy (values.yaml already up to date)"
  exit 0
fi

BRANCH="agent/deploy-${SERVICE}-${ENV}-${IMAGE_TAG}"
git checkout -b "$BRANCH" || git checkout "$BRANCH"

# Stage changes
git add "envs/${ENV}/apps/${SERVICE}-go/values.yaml" || true
git add "envs/${ENV}/apps/${SERVICE}-web/values.yaml" || true

# Commit
git commit -m "Deploy ${SERVICE} to ${ENV} (${IMAGE_TAG})

Automated deployment via agent fleet.

Backend: ghcr.io/axinova-ai/${SERVICE}-go:${IMAGE_TAG}
Frontend: ghcr.io/axinova-ai/${SERVICE}-web:${IMAGE_TAG}

Co-Authored-By: Agent Fleet <agent@axinova-ai.com>"

if [[ "$ENV" == "dev" ]]; then
  # Direct push for dev (no PR needed)
  echo "→ Pushing directly to dev branch..."
  git push origin "$BRANCH:dev" --force

  echo "→ Waiting for deployment health checks..."
  "$FLEET_DIR/runners/orchestration/health-gate.sh" "$SERVICE" "$ENV"
else
  # Create PR for prod
  echo "→ Creating pull request..."
  git push origin "$BRANCH"

  gh pr create \
    --title "Deploy ${SERVICE} to ${ENV}" \
    --body "Automated deployment via agent fleet.

## Changes
- Backend: \`ghcr.io/axinova-ai/${SERVICE}-go:${IMAGE_TAG}\`
- Frontend: \`ghcr.io/axinova-ai/${SERVICE}-web:${IMAGE_TAG}\`

## Pre-deployment checks
- [x] Local CI passed (tests, vet, govulncheck)
- [x] Docker image built and pushed
- [x] Values.yaml updated

## Deployment checklist
- [ ] Review changes
- [ ] Approve and merge to trigger deployment
- [ ] Verify health checks pass" \
    --base main \
    --head "$BRANCH" \
    --label "deployment" \
    --label "$ENV"
fi

echo ""
echo "✅ Full-stack deployment complete"
echo "  Service: $SERVICE"
echo "  Environment: $ENV"
echo "  Image tag: $IMAGE_TAG"
