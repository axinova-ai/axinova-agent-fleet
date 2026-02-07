#!/usr/bin/env bash
set -euo pipefail

REPO_PATH="${1:?Usage: $0 <repo-path>}"
cd "$REPO_PATH"

echo "==> Running Go CI for $(basename "$REPO_PATH")"

# Verify we're in a Go repo
if [[ ! -f "go.mod" ]]; then
  echo "Error: Not a Go module (no go.mod found)"
  exit 1
fi

# Step 1: Dependencies
echo "→ Tidying dependencies..."
go mod tidy

# Step 2: Formatting
echo "→ Formatting code..."
go fmt ./...

# Step 3: Linting
echo "→ Running go vet..."
go vet ./...

# Step 4: Tests with race detector
echo "→ Running tests with race detector..."
go test ./... -race -coverprofile=coverage.out

# Step 5: Vulnerability check
echo "→ Running govulncheck..."
if ! command -v govulncheck &>/dev/null; then
  echo "Installing govulncheck..."
  go install golang.org/x/vuln/cmd/govulncheck@latest
fi

# Build binary for govulncheck
if [[ -d "cmd/service" ]]; then
  go build -trimpath -ldflags "-s -w" -o /tmp/app ./cmd/service
  govulncheck -mode=binary /tmp/app
  rm /tmp/app
else
  # Fallback to source mode if no cmd/service
  govulncheck ./...
fi

# Step 6: SQLC validation (if applicable)
if [[ -f "sqlc.yaml" ]] || [[ -f "sqlc.yml" ]]; then
  echo "→ Validating SQLC queries..."
  if command -v sqlc &>/dev/null; then
    sqlc generate
    # Check for uncommitted changes (sqlc should be up to date)
    if [[ -d "internal/db" ]] && ! git diff --quiet internal/db/; then
      echo "Error: SQLC generated code out of date. Run 'make sqlc' and commit."
      exit 1
    fi
  else
    echo "Warning: sqlc not installed, skipping SQLC validation"
  fi
fi

# Step 7: Check for common issues
echo "→ Checking for common issues..."

# Check for TODO/FIXME without issue references
if grep -rn "TODO\|FIXME" --include="*.go" . | grep -v "#[0-9]"; then
  echo "Warning: Found TODOs/FIXMEs without issue references"
fi

# Check for hardcoded credentials
if grep -rn "password\s*=\|secret\s*=\|token\s*=" --include="*.go" . | grep -v "test"; then
  echo "Warning: Potential hardcoded credentials found"
fi

echo ""
echo "✅ Go CI passed for $(basename "$REPO_PATH")"
echo "  Coverage: $(go tool cover -func=coverage.out | tail -1 | awk '{print $3}')"
