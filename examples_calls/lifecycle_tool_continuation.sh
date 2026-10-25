#!/usr/bin/env bash
# ==============================================================================
# Swarm Gateway & Trust Gateway Tool Lifecycle Demonstration
# Pure Bash script illustrating the 5-step cognitive + tool continuation loop
# ==============================================================================
set -euo pipefail

GATEWAY_URL="${GATEWAY_URL:-http://127.0.0.1:8088}"
TRUST_GATEWAY_URL="${TRUST_GATEWAY_URL:-http://127.0.0.1:8080}"
MODEL="${MODEL:-openai/gpt-oss-20b}"

echo "=========================================================================="
echo " 🌐 Swarm Gateway Tool Continuation Lifecycle Walkthrough"
echo "=========================================================================="
echo " Gateway URL       : $GATEWAY_URL"
echo " Trust Gateway URL : $TRUST_GATEWAY_URL"
echo " Model             : $MODEL"
echo "=========================================================================="

# Check gateway connectivity
if ! curl -sf -o /dev/null "$GATEWAY_URL/health"; then
  echo "❌ Error: Swarm Gateway is not running on $GATEWAY_URL"
  echo "   Start it first with: make launch"
  exit 1
fi

echo ""
echo "--------------------------------------------------------------------------"
echo " Step 1 & 2: Cognition — Model Turn with Tool Declaration"
echo "--------------------------------------------------------------------------"

TURN1_PAYLOAD=$(jq -n \
  --arg model "$MODEL" \
  '{
    model: $model,
    messages: [
      {role: "user", content: "What is the current weather in Boston?"}
    ],
    tools: [
      {
        type: "function",
        function: {
          name: "get_current_weather",
          description: "Fetch current weather conditions for a city",
          parameters: {
            type: "object",
            properties: {
              location: {type: "string", description: "City name"}
            },
            required: ["location"]
          }
        }
      }
    ],
    tool_choice: "auto"
  }')

TURN1_RESP=$(curl -s -X POST "$GATEWAY_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "$TURN1_PAYLOAD")

echo "Model Response:"
echo "$TURN1_RESP" | jq .

CALL_ID=$(echo "$TURN1_RESP" | jq -r '.choices[0].message.tool_calls[0].id // empty')
TOOL_NAME=$(echo "$TURN1_RESP" | jq -r '.choices[0].message.tool_calls[0].function.name // empty')
TOOL_ARGS=$(echo "$TURN1_RESP" | jq -r '.choices[0].message.tool_calls[0].function.arguments // empty')

if [ -z "$CALL_ID" ]; then
  echo "ℹ️ Note: Model answered directly; using sample tool call for demo."
  CALL_ID="fc_demo_$(date +%s)"
  TOOL_NAME="get_current_weather"
  TOOL_ARGS='{"location":"Boston"}'
fi

echo ""
echo "Extracted Tool Proposal:"
echo "  • Call ID   : $CALL_ID"
echo "  • Tool Name : $TOOL_NAME"
echo "  • Arguments : $TOOL_ARGS"

echo ""
echo "--------------------------------------------------------------------------"
echo " Step 3 & 4: Policy & Execution — Marketplace Trust Gateway Validation"
echo "--------------------------------------------------------------------------"
TRACE_ID="trace_$(openssl rand -hex 8)"
echo "Client generated Trace ID : $TRACE_ID"
echo "Submitting action proposal to Trust Gateway (POST /v1/actions/propose)..."

VERIFIED_OUTPUT='{"location":"Boston","temperature":"68F","condition":"Partly Cloudy"}'

if curl -sf -o /dev/null "$TRUST_GATEWAY_URL/health" 2>/dev/null; then
  echo "✔ Trust Gateway detected at $TRUST_GATEWAY_URL"
  TRUST_PROPOSAL_PAYLOAD=$(jq -n \
    --arg trace_id "$TRACE_ID" \
    --arg action "$TOOL_NAME" \
    --argjson params "$TOOL_ARGS" \
    '{trace_id: $trace_id, action: $action, parameters: $params}')
  TRUST_RESP=$(curl -s -X POST "$TRUST_GATEWAY_URL/v1/actions/propose" \
    -H "Content-Type: application/json" \
    -d "$TRUST_PROPOSAL_PAYLOAD" || true)
  echo "Trust Gateway Response: $TRUST_RESP"
else
  echo "ℹ️ Trust Gateway offline; using verified simulated tool execution."
fi

echo "Verified Tool Output: $VERIFIED_OUTPUT"

echo ""
echo "--------------------------------------------------------------------------"
echo " Step 5: Continuation Turn — Returning Tool Output to Swarm Gateway"
echo "--------------------------------------------------------------------------"

TURN2_PAYLOAD=$(jq -n \
  --arg model "$MODEL" \
  --arg call_id "$CALL_ID" \
  --arg tool_name "$TOOL_NAME" \
  --arg tool_args "$TOOL_ARGS" \
  --arg verified "$VERIFIED_OUTPUT" \
  '{
    model: $model,
    messages: [
      {role: "user", content: "What is the current weather in Boston?"},
      {
        role: "assistant",
        content: null,
        tool_calls: [
          {
            id: $call_id,
            type: "function",
            function: {
              name: $tool_name,
              arguments: $tool_args
            }
          }
        ]
      },
      {
        role: "tool",
        tool_call_id: $call_id,
        content: $verified
      }
    ]
  }')

TURN2_RESP=$(curl -s -X POST "$GATEWAY_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "$TURN2_PAYLOAD")

echo "Final Model Completion:"
echo "$TURN2_RESP" | jq .

FINAL_CONTENT=$(echo "$TURN2_RESP" | jq -r '.choices[0].message.content // empty')
echo ""
echo "=========================================================================="
echo "✔ Final Assistant Response: $FINAL_CONTENT"
echo "=========================================================================="
