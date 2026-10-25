# 🌐 Swarm Gateway — Examples & API Calls Suite

This directory contains executable test scripts and verified API call documentation for testing the **Swarm Model Gateway**.

---

## 📁 Contents

| File | Description |
| :--- | :--- |
| **[`run_examples.sh`](run_examples.sh)** | Automated test runner verifying health probes, chat completions, stateful responses, and SSE streaming. |
| **[`lifecycle_tool_continuation.sh`](lifecycle_tool_continuation.sh)** | Pure Bash 5-step walkthrough demonstrating model tool call proposal, Trust Gateway validation, and continuation turn. |
| **[`mint_test_token.sh`](mint_test_token.sh)** | Pure Bash script using OpenSSL to mint valid HS256 JWT tokens for testing inbound authentication (`make token`). |
| **[`sample_calls.md`](sample_calls.md)** | Comprehensive API documentation with curl commands and verified JSON payloads for all routes. |

---

## 🚀 Quick Execution

Run the automated test runner directly from the workspace root:

```bash
# Basic run (tests health, chat completions, and multi-turn stateful turns)
./examples_calls/run_examples.sh

# Run with token-by-token SSE streaming test
./examples_calls/run_examples.sh --stream

# Auto-launch the gateway daemon if not currently running
./examples_calls/run_examples.sh --launch

# Test with a specific model or port
./examples_calls/run_examples.sh --model "groq/llama-3.3-70b-versatile" --port 8088
```

---

## 🧪 What `run_examples.sh` Tests

1. **Health Probes**: `GET /health` & `GET /v1/health` (Kubernetes liveness and readiness probes).
2. **Stateless Chat**: `POST /v1/chat/completions` (OpenAI spec compliance, prompt and completion token accounting).
3. **Stateful Turn 1**: `POST /v1/responses` (Initial query saving state in gateway session store).
4. **Stateful Turn 2**: `POST /v1/responses` (Follow-up linked by `previous_response_id`, verifying conversational memory).
5. **SSE Streaming (Optional)**: `POST /v1/chat/completions` with `--stream` (validates real-time token delivery and `data: [DONE]`).

---

## 📖 Detailed Payload Reference

For exhaustive examples including function/tool calling, custom model routing (Groq, Gemini, OpenAI, Ollama), and JWT bearer authentication, refer to:
👉 **[sample_calls.md](sample_calls.md)**
