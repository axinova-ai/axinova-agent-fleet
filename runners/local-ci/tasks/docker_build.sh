#!/usr/bin/env bash
set -euo pipefail

REPO_PATH="${1:?Usage: $0 <repo-path>}"
PUSH="${2:-false}"  # Optional: push to registry

cd "$REPO_PATH"

echo "==> Building Docker image for $(basename "$REPO_PATH")"

# Verify Dockerfile exists
if [[ ! -f "Dockerfile" ]]; then
  echo "Error: Dockerfile not found"
  exit 1
fi

# Determine image name from repo
REPO_NAME=$(basename "$REPO_PATH")
IMAGE_NAME="ghcr.io/axinova-ai/${REPO_NAME}"

# Get git commit SHA for tag
GIT_SHA=$(git rev-parse --short HEAD)
IMAGE_TAG="sha-${GIT_SHA}"

echo "→ Building image: ${IMAGE_NAME}:${IMAGE_TAG}"

# Build with BuildKit
DOCKER_BUILDKIT=1 docker build \
  --platform linux/amd64 \
  --tag "${IMAGE_NAME}:${IMAGE_TAG}" \
  --tag "${IMAGE_NAME}:latest" \
  --build-arg GIT_SHA="$GIT_SHA" \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  .

# Get image size
IMAGE_SIZE=$(docker images "${IMAGE_NAME}:${IMAGE_TAG}" --format "{{.Size}}")
echo "  Image size: $IMAGE_SIZE"

# Scan for vulnerabilities (if trivy installed)
if command -v trivy &>/dev/null; then
  echo "→ Scanning for vulnerabilities..."
  trivy image --severity HIGH,CRITICAL "${IMAGE_NAME}:${IMAGE_TAG}"
fi

# Push to registry if requested
if [[ "$PUSH" == "true" ]]; then
  echo "→ Pushing to registry..."

  # Check if authenticated
  if ! docker info 2>/dev/null | grep -q "Username"; then
    echo "Error: Not authenticated to Docker registry"
    echo "Run: echo \$GITHUB_TOKEN | docker login ghcr.io -u harryxiaxia --password-stdin"
    exit 1
  fi

  docker push "${IMAGE_NAME}:${IMAGE_TAG}"
  docker push "${IMAGE_NAME}:latest"

  echo "✅ Pushed ${IMAGE_NAME}:${IMAGE_TAG}"
else
  echo "→ Skipping registry push (set second arg to 'true' to push)"
fi

echo ""
echo "✅ Docker build complete"
echo "  Image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "  Size: $IMAGE_SIZE"
