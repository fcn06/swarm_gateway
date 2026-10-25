#!/usr/bin/env bash

# ==============================================================================
# Swarm Gateway Sample Calls Runner
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source .env if present in root or swarm/
if [ -f "$WORKSPACE_ROOT/.env" ]; then
  # shellcheck disable=SC1091
  set -a; source "$WORKSPACE_ROOT/.env"; set +a
elif [ -f "$WORKSPACE_ROOT/swarm/.env" ]; then
  # shellcheck disable=SC1091
  set -a; source "$WORKSPACE_ROOT/swarm/.env"; set +a
fi

# Configurations & Defaults
PORT="${PORT:-8088}"
HOST="${HOST:-127.0.0.1}"
GATEWAY_URL="http://$HOST:$PORT"
MODEL="${MODEL:-openai/gpt-oss-20b}"
AUTH_TOKEN="${AUTH_TOKEN:-${BEARER_TOKEN:-}}"
RUN_STREAM="${RUN_STREAM:-false}"
AUTO_LAUNCH="${AUTO_LAUNCH:-false}"

# Usage help
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -m, --model <NAME>      Model name to test (default: $MODEL)
  -p, --port <PORT>       Gateway port (default: $PORT)
  -t, --token <TOKEN>     Bearer authentication token (if inbound auth is enabled)
  -s, --stream            Include SSE streaming verification in the test run
  -l, --launch            Automatically start gateway daemon if not currently running
  -h, --help              Show this help message

Environment Variables:
  MODEL                   Model identifier (e.g., openai/gpt-oss-20b, groq/llama-3.3-70b-versatile)
  PORT                    Gateway server port (default: 8088)
  AUTH_TOKEN              Inbound Bearer JWT token
  AUTO_LAUNCH             Auto-launch gateway daemon (true/false)
  RUN_STREAM              Run streaming SSE checks (true/false)
EOF
  exit 0
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--model)
      MODEL="$2"; shift 2 ;;
    -p|--port)
      PORT="$2"; GATEWAY_URL="http://$HOST:$PORT"; shift 2 ;;
    -t|--token)
      AUTH_TOKEN="$2"; shift 2 ;;
    -s|--stream)
      RUN_STREAM="true"; shift ;;
    -l|--launch)
      AUTO_LAUNCH="true"; shift ;;
    -h|--help)
      usage ;;
    *)
      echo "Unknown option: $1" >&2
      usage ;;
  esac
done

echo "=========================================================================="
echo "          🌐 Swarm Gateway Sample Calls Demonstration                     "
echo "=========================================================================="
echo " Gateway URL : $GATEWAY_URL"
echo " Model       : $MODEL"
echo " Auth Token  : ${AUTH_TOKEN:+[Configured]}${AUTH_TOKEN:-[None]}"
echo " Streaming   : $RUN_STREAM"
echo "=========================================================================="
echo ""

# Helper to check gateway connectivity
check_gateway_reachable() {
  curl -s --connect-timeout 2 "$GATEWAY_URL/health" >/dev/null 2>&1
}

# Auto-launch if requested and not running
if ! check_gateway_reachable; then
  if [ "$AUTO_LAUNCH" = "true" ]; then
    echo "⚡ Gateway is not running. Launching via make launch..."
    (cd "$WORKSPACE_ROOT" && make launch)
    # Wait for gateway to become ready
    READY=false
    for _ in {1..15}; do
      if check_gateway_reachable; then
        READY=true
        break
      fi
      sleep 1
    done
    if [ "$READY" = "false" ]; then
      echo "❌ Error: Timed out waiting for gateway server to start." >&2
      exit 1
    fi
  else
    cat <<EOF
❌ Gateway is not reachable at $GATEWAY_URL.

💡 To launch the gateway server:
    cd "$WORKSPACE_ROOT"
    make launch

Or run this script with --launch to start it automatically:
    ./examples_calls/run_examples.sh --launch
EOF
    exit 1
  fi
fi

# Build auth header array
AUTH_HEADER=()
if [ -n "$AUTH_TOKEN" ]; then
  AUTH_HEADER=(-H "Authorization: Bearer $AUTH_TOKEN")
fi

format_json() {
  if command -v jq &>/dev/null; then
    jq . 2>/dev/null || cat
  else
    cat
  fi
}

# 1. Health Probes
echo "--------------------------------------------------------------------------"
echo " 1. GET /health & /v1/health Probes"
echo "--------------------------------------------------------------------------"
HEALTH_RESP=$(curl -s "$GATEWAY_URL/health")
echo "Probe /health:"
echo "$HEALTH_RESP" | format_json

V1_HEALTH_RESP=$(curl -s "$GATEWAY_URL/v1/health")
echo "Probe /v1/health:"
echo "$V1_HEALTH_RESP" | format_json
echo ""

# 2. Stateless Chat Completion
echo "--------------------------------------------------------------------------"
echo " 2. POST /v1/chat/completions (OpenAI-Compatible Stateless)"
echo "--------------------------------------------------------------------------"
CHAT_PAYLOAD=$(cat <<EOF
{
  "model": "$MODEL",
  "messages": [
    {"role": "system", "content": "You are a concise assistant."},
    {"role": "user", "content": "What is the capital of France?"}
  ],
  "stream": false
}
EOF
)

CHAT_RESP=$(curl -s -X POST "$GATEWAY_URL/v1/chat/completions" \
  "${AUTH_HEADER[@]}" \
  -H "Content-Type: application/json" \
  -d "$CHAT_PAYLOAD")

echo "$CHAT_RESP" | format_json
echo ""

# 3. Stateful Open Responses (Turn 1: Initial Query)
echo "--------------------------------------------------------------------------"
echo " 3. POST /v1/responses (Turn 1: Initial Query)"
echo "--------------------------------------------------------------------------"
TURN1_PAYLOAD=$(cat <<EOF
{
  "model": "$MODEL",
  "input": "My favorite city is Boston.",
  "stream": false
}
EOF
)

TURN1_RESP=$(curl -s -X POST "$GATEWAY_URL/v1/responses" \
  "${AUTH_HEADER[@]}" \
  -H "Content-Type: application/json" \
  -d "$TURN1_PAYLOAD")

echo "$TURN1_RESP" | format_json

# Extract previous_response_id
PREV_ID=""
if command -v jq &>/dev/null; then
  PREV_ID=$(echo "$TURN1_RESP" | jq -r '.id // empty' 2>/dev/null || true)
fi

echo ""

# 4. Stateful Open Responses (Turn 2: Follow-up Query)
if [ -n "$PREV_ID" ] && [ "$PREV_ID" != "null" ]; then
  echo "--------------------------------------------------------------------------"
  echo " 4. POST /v1/responses (Turn 2: Follow-up chained with ID: $PREV_ID)"
  echo "--------------------------------------------------------------------------"
  TURN2_PAYLOAD=$(cat <<EOF
{
  "model": "$MODEL",
  "previous_response_id": "$PREV_ID",
  "input": "What city did I say was my favorite?",
  "stream": false
}
EOF
)

  TURN2_RESP=$(curl -s -X POST "$GATEWAY_URL/v1/responses" \
    "${AUTH_HEADER[@]}" \
    -H "Content-Type: application/json" \
    -d "$TURN2_PAYLOAD")

  echo "$TURN2_RESP" | format_json
else
  echo "⚠️ Skipping Turn 2: Could not extract .id from Turn 1 response."
fi
echo ""

# 5. Optional SSE Streaming Verification
if [ "$RUN_STREAM" = "true" ]; then
  echo "--------------------------------------------------------------------------"
  echo " 5. POST /v1/chat/completions (SSE Token-Streaming)"
  echo "--------------------------------------------------------------------------"
  STREAM_PAYLOAD=$(cat <<EOF
{
  "model": "$MODEL",
  "messages": [
    {"role": "user", "content": "Count from 1 to 3."}
  ],
  "stream": true
}
EOF
)

  curl -s -N -X POST "$GATEWAY_URL/v1/chat/completions" \
    "${AUTH_HEADER[@]}" \
    -H "Content-Type: application/json" \
    -d "$STREAM_PAYLOAD"
  echo ""
fi

echo "=========================================================================="
echo "✔ Swarm Gateway sample calls demonstration successfully completed!"
echo "=========================================================================="
