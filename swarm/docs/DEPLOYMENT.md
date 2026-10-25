# Gateway Deployment and Operations

This document covers operational prerequisites, deployment procedures, and configuration settings for the **Swarm Model Gateway** (`swarm_server`).

---

## Prerequisites

### 1. Rust Toolchain
Rust 1.80+ is required:

```bash
rustup update
```

### 2. Environment Configuration
Copy the environment template:

```bash
cp .env.example .env
```

Set the API keys for the providers you plan to use:

```bash
export GROQ_API_KEY="gsk_your_groq_api_key_here"
export GEMINI_API_KEY="your_gemini_api_key_here"
export OPENAI_API_KEY="your_openai_api_key_here"
```

For local inference with Ollama or vLLM:

```bash
export SWARM_LLM_URL="http://localhost:11434/v1/chat/completions"
```

---

## Running the Gateway

### Start the Gateway Server

Launch the standalone gateway using the provided kickstart script:

```bash
cd swarm
./kickstart/gateway_kickstart/01_launch_gateway.sh
```

By default, the server binds to port `8088` (default secure bind: `127.0.0.1:8088`, preventing conflict with Trust Gateway on 8080).

### Testing Chat Completions

Send a test request via the OpenAI-compatible `/v1/chat/completions` endpoint:

```bash
./kickstart/gateway_kickstart/02_test_chat_completions.sh "What is the capital of France?"
```

### Testing Open Responses (Stateful Multi-Turn)

Send a multi-turn conversational request via `/v1/responses`:

```bash
./kickstart/gateway_kickstart/03_test_open_responses.sh
```

### Stopping the Gateway

Terminate the running gateway process:

```bash
./kickstart/gateway_kickstart/04_terminate_gateway.sh
```

---

## Four-Tier Stack Runtime Topology & Port Mapping

| Tier | Component / Service | Default Port | Protocol | Role in Agentic Architecture |
|---|---|:---:|---|---|
| **Tier 1** | **Swarm Model Gateway** | **`8088`** *(default `127.0.0.1:8088`)* | HTTP/1.1, HTTP/2, SSE | **Cognitive Ingress Proxy**: Model routing, OpenAI `/v1/chat/completions`, Open Responses (`/v1/responses`), and session storage. Works with optional memory service on a configurable port. |
| **Tier 2** | **Marketplace Trust Gateway** | **`8080`** *(Community)*<br>**`8081`** *(Commercial)* | HTTP / REST / MCP | **Execution Egress Firewall & MCP Server**: De facto MCP server from an agent's standpoint. Validates capability tokens, executes sandboxed tools, tracks taint traces, and logs compliance audits. |
| **Tier 3** | **B2B Specialist Agents** | *Configurable / Dynamic*<br>(Various A2A ports) | A2A (HTTP / WebSocket) | **Autonomous Workers**: Domain state loops translating tasks into reasoning steps (via Swarm Gateway) and signed tool invocations (via Trust Gateway). |
| **Tier 4** | **Outcome Orchestrator** | *Configurable / Dynamic*<br>(Various A2A ports) | A2A / Orchestration | **Control Plane**: High-level business goal decomposition, SLA tracking, and multi-agent workflow DAG execution. |

> **Port Conflict Avoidance**: Swarm Gateway defaults to port `8088` specifically to avoid port collisions with the Marketplace Trust Gateway (`8080` for Community or `8081` for Commercial), allowing all tiers to run concurrently on `localhost`.

---

## Configuration Reference

The Gateway reads its configuration from a TOML file (default: `kickstart/gateway_kickstart/config_files/gateway_config.toml` or passed via `-c <path>`):

```toml
[server]
# Bind address (use 0.0.0.0:8088 for Docker / Kubernetes container exposure)
bind_address = "127.0.0.1:8088"
host = "127.0.0.1"
port = 8088
log_level = "info"

[session]
# In-memory session store bounds for /v1/responses
max_history_items = 100
session_timeout_seconds = 3600

[models]
# Default fallback model when not specified in client request
default_model = "openai/gpt-oss-20b"

[providers.groq]
api_url = "https://api.groq.com/openai/v1/chat/completions"
recommended_models = [
    "groq/llama-3.3-70b-versatile",
    "openai/gpt-oss-20b",
    "qwen/qwen3.8-27b"
]

[providers.google]
api_url = "https://generativelanguage.googleapis.com/v1beta/models"
recommended_models = [
    "gemini-2.0-flash",
    "gemini-1.5-pro"
]

[providers.openai]
api_url = "https://api.openai.com/v1/chat/completions"
recommended_models = [
    "gpt-4o",
    "gpt-4o-mini"
]

[providers.custom]
# Local inference endpoint (e.g., Ollama or vLLM)
api_url = "http://localhost:11434/v1/chat/completions"
recommended_models = [
    "llama3.2:latest",
    "mistral:latest",
    "deepseek-r1:8b"
]

[resilience]
# Concurrency limit for inflight requests (protects Tokio worker threads)
max_concurrent_requests = 512

# Global request timeout in seconds (guards against hung upstream connections)
request_timeout_seconds = 60

# Circuit breaker: trip provider offline if N consecutive errors occur
circuit_breaker_failure_threshold = 5

# Cooldown window: wait N seconds before probing provider recovery
circuit_breaker_reset_seconds = 30
```

---

## Security & Authentication

Swarm provides hardened authentication for production deployments:

### Inbound JWT Authentication

When inbound authentication is enabled:
- **Algorithm Pinning**: Strictly pinned to `HS256`.
- **Mandatory Audience and Issuer**: Both `audience` and `issuer` are required; configurations omitting them are rejected at startup.
- **Clock Skew Tolerance**: 60-second leeway on `exp` (expiration) and `nbf` (not-before) claims.
- **Protected Routes**: `/v1/chat/completions` and `/v1/responses` require `Authorization: Bearer <jwt>`.
- **Public Health Probes**: `/health` and `/v1/health` remain unauthenticated so container liveness and readiness checks succeed without tokens.

Environment variables:
```bash
export SWARM_AUTH_SECRET="your-256-bit-secret-key-here"
export SWARM_AUTH_AUDIENCE="swarm-api"
export SWARM_AUTH_ISSUER="swarm-auth-service"
```

---

## Production Deployment Patterns

### Kubernetes Deployment
- **Deployment Model**: Deploy `swarm_server` either as a standalone gateway Deployment behind an Ingress or as a sidecar container in client application pods.
- **Liveness & Readiness Probes**: Point probes to `http://localhost:8088/health`.
- **Resource Recommendations**:
  - Memory: Requests `64Mi`, Limits `256Mi` (Gateway RSS is typically <20MB).
  - CPU: Requests `100m`, Limits `1000m`.

### Docker Container Run
To run `swarm_server` in Docker:

```bash
docker run -d \
  --name swarm-gateway \
  -p 8088:8088 \
  -e GROQ_API_KEY="gsk_..." \
  -e OPENAI_API_KEY="sk-..." \
  -e GEMINI_API_KEY="..." \
  swarm-gateway:latest \
  --config-file /etc/swarm/gateway_config.toml
```
