#!/usr/bin/env bash
set -uo pipefail

# Ollama LLM Benchmark — Compare models for agent tasks
# Usage: ./scripts/benchmark-ollama.sh [ollama-host]
#
# Run on M2 Pro (or wherever Ollama is running)

OLLAMA_HOST="${1:-http://localhost:11434}"
RESULTS_FILE="/tmp/ollama-benchmark-$(date +%Y%m%d-%H%M%S).md"

echo "==========================================="
echo "  Ollama LLM Benchmark"
echo "  Host: $OLLAMA_HOST"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "==========================================="

# Check Ollama is running
if ! curl -sf "$OLLAMA_HOST/api/tags" >/dev/null 2>&1; then
  echo "ERROR: Ollama not reachable at $OLLAMA_HOST"
  exit 1
fi

# List available models
echo ""
echo "Available models:"
curl -sf "$OLLAMA_HOST/api/tags" | python3 -c "
import sys, json
models = json.load(sys.stdin)['models']
for m in models:
    size_gb = m.get('size', 0) / 1e9
    print(f'  {m[\"name\"]:40s} {size_gb:.1f} GB')
" 2>/dev/null

# Models to benchmark
MODELS=("qwen2.5-coder:7b" "gemma3:4b")

# Test prompts (coding-oriented)
declare -A PROMPTS
PROMPTS[go-handler]='Write a Go HTTP handler function that returns JSON with a health check response including status "ok", timestamp, and version "1.0.0". Use net/http and encoding/json only. Output the complete function.'
PROMPTS[vue-component]='Write a Vue 3 component using <script setup lang="ts"> that displays a loading spinner when a "loading" prop is true, and shows a slot content when false. Use Tailwind CSS classes. Output the complete .vue file.'
PROMPTS[fix-typo]='Fix the typo in this Go code and output the corrected version:
func main() {
    fmt.Pritnln("Hello, World!")
}'
PROMPTS[diff-output]='Given a file at path "internal/api/health.go" containing:
```go
package api

func HealthHandler() string {
    return "ok"
}
```
Add a timestamp field. Output ONLY a unified diff (no commentary):
--- a/internal/api/health.go
+++ b/internal/api/health.go'

# Benchmark function
benchmark_model() {
  local model="$1"
  local prompt_name="$2"
  local prompt="$3"

  # Check model exists
  if ! curl -sf "$OLLAMA_HOST/api/tags" | jq -e ".models[] | select(.name == \"$model\")" >/dev/null 2>&1; then
    echo "  SKIP  $model not installed"
    return
  fi

  local start_time end_time duration
  start_time=$(date +%s%N)

  local response
  response=$(curl -sf --max-time 120 "$OLLAMA_HOST/api/chat" \
    -d "$(jq -n --arg model "$model" --arg prompt "$prompt" \
      '{model: $model, messages: [{role: "user", content: $prompt}], stream: false}')" 2>&1)

  end_time=$(date +%s%N)
  duration=$(( (end_time - start_time) / 1000000 ))  # ms

  if [[ -z "$response" ]]; then
    echo "  FAIL  $model / $prompt_name — timeout or error"
    echo "| $model | $prompt_name | FAIL | - | - |" >> "$RESULTS_FILE"
    return
  fi

  # Extract metrics
  local content tokens_total tokens_per_sec eval_duration
  content=$(echo "$response" | jq -r '.message.content // ""' 2>/dev/null)
  tokens_total=$(echo "$response" | jq -r '.eval_count // 0' 2>/dev/null)
  eval_duration=$(echo "$response" | jq -r '.eval_duration // 0' 2>/dev/null)

  if [[ "$eval_duration" -gt 0 ]]; then
    tokens_per_sec=$(python3 -c "print(f'{$tokens_total / ($eval_duration / 1e9):.1f}')" 2>/dev/null || echo "?")
  else
    tokens_per_sec="?"
  fi

  local content_len=${#content}
  local quality="?"

  # Simple quality check: does the output look reasonable?
  case "$prompt_name" in
    go-handler)
      echo "$content" | grep -q 'func.*Health' && quality="PASS" || quality="FAIL"
      ;;
    vue-component)
      echo "$content" | grep -q 'script setup' && quality="PASS" || quality="FAIL"
      ;;
    fix-typo)
      echo "$content" | grep -q 'Println' && quality="PASS" || quality="FAIL"
      ;;
    diff-output)
      echo "$content" | grep -q '^\(---\|+++\|@@\)' && quality="PASS" || quality="FAIL"
      ;;
  esac

  local duration_sec
  duration_sec=$(python3 -c "print(f'{$duration / 1000:.1f}')" 2>/dev/null || echo "?")

  echo "  $quality  $model / $prompt_name — ${duration_sec}s, ${tokens_total} tokens, ${tokens_per_sec} tok/s"
  echo "| $model | $prompt_name | $quality | ${duration_sec}s | ${tokens_per_sec} tok/s |" >> "$RESULTS_FILE"
}

# Initialize results file
cat > "$RESULTS_FILE" <<EOF
# Ollama Benchmark Results

Date: $(date '+%Y-%m-%d %H:%M:%S')
Host: $OLLAMA_HOST

| Model | Prompt | Quality | Duration | Speed |
|-------|--------|---------|----------|-------|
EOF

# Run benchmarks
for model in "${MODELS[@]}"; do
  echo ""
  echo "--- $model ---"
  for prompt_name in "${!PROMPTS[@]}"; do
    benchmark_model "$model" "$prompt_name" "${PROMPTS[$prompt_name]}"
  done
done

echo ""
echo "==========================================="
echo "Results saved to: $RESULTS_FILE"
echo ""
cat "$RESULTS_FILE"
echo ""
echo "Recommendation: Use the model with best PASS rate and >10 tok/s"
echo "==========================================="
