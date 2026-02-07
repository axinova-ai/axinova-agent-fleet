#!/usr/bin/env bash
set -euo pipefail

REPO_PATH="${1:?Usage: $0 <repo-path>}"
cd "$REPO_PATH"

echo "==> Running Vue CI for $(basename "$REPO_PATH")"

# Verify we're in a Node.js repo
if [[ ! -f "package.json" ]]; then
  echo "Error: Not a Node.js repo (no package.json found)"
  exit 1
fi

# Step 1: Install dependencies
echo "→ Installing dependencies..."
npm ci

# Step 2: Type checking
echo "→ Running TypeScript type check..."
if grep -q "vue-tsc" package.json; then
  npx vue-tsc -b --noEmit
else
  echo "Warning: vue-tsc not found, skipping type check"
fi

# Step 3: Build
echo "→ Building production bundle..."
npm run build

# Check build output size
if [[ -d "dist" ]]; then
  BUILD_SIZE=$(du -sh dist | awk '{print $1}')
  echo "  Build size: $BUILD_SIZE"

  # Warn if bundle is too large (>5MB)
  SIZE_BYTES=$(du -s dist | awk '{print $1}')
  if [[ $SIZE_BYTES -gt 5120 ]]; then  # 5MB in KB
    echo "⚠️  Warning: Build size exceeds 5MB, consider code splitting"
  fi
fi

# Step 4: Lint (if configured)
if grep -q '"lint"' package.json; then
  echo "→ Running linter..."
  npm run lint
fi

# Step 5: Check for common issues
echo "→ Checking for common issues..."

# Check for console.log in production code (outside dev blocks)
if grep -rn "console\\.log\\|console\\.debug" --include="*.vue" --include="*.ts" src/ | grep -v "//.*console" | grep -v "if.*import.meta.env.DEV"; then
  echo "⚠️  Warning: Found console.log statements (remove for production)"
fi

# Check for hardcoded API URLs
if grep -rn "http://localhost\\|https://api\\." --include="*.vue" --include="*.ts" src/ | grep -v ".env"; then
  echo "⚠️  Warning: Potential hardcoded API URLs (use environment variables)"
fi

# Check for large dependencies
echo "→ Checking dependency sizes..."
if command -v npx &>/dev/null; then
  npx vite-bundle-visualizer --no-open || true
fi

echo ""
echo "✅ Vue CI passed for $(basename "$REPO_PATH")"
