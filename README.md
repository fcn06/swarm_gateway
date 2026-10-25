# Swarm Gateway

[![Rust](https://img.shields.io/badge/Rust-1.80%2B-orange?logo=rust)](https://www.rust-lang.org)
[![License](https://img.shields.io/badge/License-BSL%201.1-blue)](LICENSE)
[![API](https://img.shields.io/badge/API-OpenAI%20%2B%20Open%20Responses-blueviolet)](#supported-api-endpoints)

> A lightweight, single-binary Rust LLM gateway: OpenAI-compatible, with stateful sessions and multi-provider failover.

> [!NOTE]
> **Maturity (v0.2.0)**: Swarm Gateway is actively developed and tested for core inference proxying, multi-provider failover, and stateful turn chaining. Production capabilities such as Prometheus metrics export, OpenTelemetry distributed tracing, policy-based routing, and per-tenant quota enforcement are actively tracked on the [Product Roadmap](#product-roadmap).

---

## Quickstart

### 1. Clone and Configure
```bash
git clone https://github.com/fcn06/swarm_gateway.git
cd swarm_gateway

# Copy template to .env (read automatically by make launch):
cp .env.example .env

# Populate at least one provider API key in .env (or export in shell):
export GROQ_API_KEY="gsk_..."
# or export GEMINI_API_KEY="AIza..."
# or export OPENAI_API_KEY="sk-..."
```

### 2. Build and Launch
```bash
# Builds release binary (~12MB) and launches gateway daemon on 127.0.0.1:8088:
make launch
```

### 3. Verify Endpoints
```bash
# Run automated test suite (health, chat completions, stateful turn chaining, SSE streaming):
./examples_calls/run_examples.sh --stream
```

### 4. Stop Gateway
```bash
make stop
```

---

## Table of Contents

- [Why Swarm Gateway?](#why-swarm-gateway)
- [Pairs with Trust Gateway](#pairs-with-trust-gateway)
- [Swarm vs. LiteLLM](#swarm-vs-litellm)
- [Performance & Footprint](#performance--footprint)
- [Security & Inbound Authentication](#security--inbound-authentication)
- [Supported API Endpoints](#supported-api-endpoints)
  - [1. Stateless Chat Completions (`POST /v1/chat/completions`)](#1-stateless-chat-completions-post-v1chatcompletions)
  - [2. Stateful Open Responses (`POST /v1/responses`)](#2-stateful-open-responses-post-v1responses)
  - [3. Health & Readiness Probes (`GET /health` & `GET /v1/health`)](#3-health--readiness-probes-get-health--get-v1health)
- [Resilience & Error Mapping](#resilience--error-mapping)
- [Intelligent Model Routing](#intelligent-model-routing)
- [Session Storage Architecture](#session-storage-architecture)
- [Configuration Reference (`gateway_config.toml`)](#configuration-reference-gateway_configtoml)
- [Deep Dive & Documentation](#deep-dive--documentation)
- [Product Roadmap](#product-roadmap)
- [License](#license)

---

## Why Swarm Gateway?

Operating production AI applications typically introduces heavy operational friction:
1. **Bloated Container Layers**: Python/Node-based proxies demand gigabytes of container dependencies, consume hundreds of megabytes of baseline memory, and suffer from multi-second container cold starts.
2. **Provider Lock-In & Unreliability**: Upstream provider latency spikes, rate limits, and transient outages crash downstream services without resilient failover.
3. **Stateless vs. Stateful Impedance**: Modern interactive agents require stateful turn chaining (`previous_response_id`), while legacy developer tools demand strict, stateless OpenAI `/v1/chat/completions` compatibility.

Swarm Gateway resolves this with a purpose-built, pure-Rust network proxy compiled into a single ~12MB static binary with sub-10ms boot times:

```text
               Client Applications / Microservices / Agent Frameworks
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       S W A R M   G A T E W A Y                             │
│                       (127.0.0.1:8088)                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│  Ingress Protocols:                                                         │
│   • POST /v1/chat/completions   (Stateless OpenAI Spec, Tool Forwarding)    │
│   • POST /v1/responses          (Stateful Open Responses, SSE Streaming)    │
│   • GET  /health & /v1/health   (Readiness & Liveness Probes)               │
├─────────────────────────────────────────────────────────────────────────────┤
│  Resilience & Production Hardening Layer:                                   │
│   • Optional Bearer JWT Auth    • Concurrency Limiter (Tokio Semaphore)     │
│   • Per-Request Deadlines       • Upstream Provider Circuit Breakers        │
│   • Multi-Provider Fallbacks    • Structured Upstream Error Mapping         │
├─────────────────────────────────────────────────────────────────────────────┤
│  Session & State Management:                                                │
│   • In-Memory DashMap (Lock-Free)  • Persistent Embedded Store (RedB)       │
├─────────────────────────────────────────────────────────────────────────────┤
│  Multi-Provider Routing & Failover Engine:                                  │
│   • Groq API       • Google Gemini API     • OpenAI API    • Local Ollama   │
└──────────────┬──────────────────┬──────────────────┬────────────────┬───────┘
               ▼                  ▼                  ▼                ▼
          Groq Cloud         Google Cloud       OpenAI Cloud     Local Inference
       (Llama 3.3, Qwen)   (Gemini 2.0 Flash)     (GPT-4o)      (vLLM / Ollama)
```

---

## Pairs with Trust Gateway

Swarm Gateway is designed to pair directly with **[Marketplace Trust Gateway](https://github.com/fcn06/marketplace_trust_gateway)**:

* **Swarm Gateway (Model Gateway — Port `8088`)**: Handles inference routing, multi-provider circuit breaking, stateless completions (`/v1/chat/completions`), stateful conversational session memory (`/v1/responses`), and transparently forwards tool-call declarations. **Swarm Gateway never executes tools.**
* **Trust Gateway (Policy & Execution Gateway — Port `8080` Community / `8081` Commercial)**: Sits **alongside** Swarm Gateway as the de facto MCP server from an agent's standpoint. It intercepts proposed tool actions from the client, validates cryptographic capability tokens (UCAN), checks arguments with regex PII scrubbing, manages human-in-the-loop approvals, and executes approved tools in isolated OS subprocesses. **Trust Gateway maintains security execution state (audit logs, taint state per trace, nonce tracking, approvals queue), but maintains zero conversational session state.**

### Request Lifecycle with Both Gateways

Neither gateway calls the other directly. They sit alongside each other, with the **Client / Agent Orchestrator** in the center coordinating cognition (Swarm) and verified execution (Trust):

```text
                           Client / Agent Orchestrator
                            │         ▲             │         ▲
               1. Prompt:   │         │ 2. Tool     │ 3. Action│ 4. Verified
               "Book flight"│         │    Proposal │    Propose│    Tool Output
                            ▼         │             ▼         │
                 ┌───────────────────────┐       ┌───────────────────────┐
                 │  SWARM GATEWAY :8088  │       │  TRUST GATEWAY :8080  │
                 │  (Model & Session)    │       │  (Execution & Policy) │
                 └───────────────────────┘       └───────────────────────┘
                            ▲
           5. Continuation: │
              Function Output
```

#### Step-by-Step Execution:
1. **Model Turn (Cognition)**: The client submits a user prompt to Swarm Gateway (`POST http://127.0.0.1:8088/v1/responses`).
2. **Tool Proposal**: Swarm Gateway forwards the prompt and tool declarations to the upstream LLM, which emits a tool-call proposal (e.g. `call_id: "call_abc123"`, name: `book_flight`, args: `{"dest": "NYC"}`). Swarm records this in turn history and returns it to the client.
3. **Action Proposal (Policy Check)**: The client submits the proposed tool execution to Trust Gateway via `POST http://127.0.0.1:8080/v1/actions/propose` (or via standard MCP protocol) along with cryptographic invocation capability tokens.
4. **Tool Execution & Sanitization**: Trust Gateway checks policy, verifies authorization, executes the tool in an isolated OS subprocess, scrubs PII, and returns the verified tool output to the client.
5. **Context Continuation (Turn 2)**: The client sends the tool output back to Swarm Gateway (`POST http://127.0.0.1:8088/v1/responses`), chained via `previous_response_id`. Swarm records the output in session memory and prompts the model for the final response.

#### Step 5 Request Shape (Returning Tool Output to Swarm):
The glue between Trust Gateway and Swarm Gateway is the `function_call_output` item in the stateful `/v1/responses` request:

```json
{
  "model": "openai/gpt-oss-20b",
  "previous_response_id": "resp_b8d1312d-94c2-4a0b-8012-1f486a249112",
  "input": [
    {
      "type": "function_call_output",
      "call_id": "call_abc123",
      "output": "{\"status\": \"confirmed\", \"booking_ref\": \"BK-9021\", \"destination\": \"NYC\"}"
    }
  ]
}
```

### Critical Architectural Boundaries & Operational Considerations

#### 1. The Taint Ingestion Boundary
> [!IMPORTANT]
> **Taint tracking in Trust Gateway is tool-mediated only**: Taint state is triggered strictly when an agent executes an `UntrustedExternal` tool through Trust Gateway.
> 
> Untrusted content that reaches the LLM through other vectors—such as a user-pasted document in the initial prompt, RAG retrieval chunks injected directly by client application code, or an email body fetched by the client's own HTTP stack—**never taints the trace in Trust Gateway**, because Trust Gateway never sees it.
> 
> **Integrator Recommendation**: For end-to-end prompt injection and exfiltration defense, route all untrusted data-fetching actions (web search, document scraping, external email retrieval) through Trust Gateway tools rather than performing them client-side.

#### 2. Trace ID Propagation
* **Creation**: The `trace_id` is generated by the client application (e.g., a standard UUIDv4 formatted as `trace_<uuid>`).
* **Propagation**: The client attaches `trace_id` to the metadata of the Swarm Gateway request and passes it to Trust Gateway in the action proposal envelope.
* **Scoping**: Taint marks, action nonces, and approval states in Trust Gateway are strictly partitioned and scoped to this `trace_id`.

#### 3. Handling Asynchronous Human Approvals (`PENDING_HUMAN_APPROVAL`)
When Trust Gateway encounters high-risk actions (e.g., financial transactions, database writes), it halts synchronous execution and returns:
```json
{
  "status": "PENDING_HUMAN_APPROVAL",
  "approval_id": "appr_789456",
  "reason": "Policy Rule PR-004 requires two-party signoff for payment actions"
}
```
In this scenario:
1. The client **must not** proceed to Step 5 or send an empty result to Swarm Gateway.
2. The client suspends the agent loop and either polls `GET /v1/approvals/appr_789456` or awaits an incoming approval webhook.
3. Once approved and executed by Trust Gateway, the client retrieves the verified tool output and delivers it to Swarm Gateway (`/v1/responses`) using the original `previous_response_id`.

---

## Swarm vs. LiteLLM

| Dimension | Swarm Gateway | LiteLLM Proxy |
| :--- | :--- | :--- |
| **Runtime & Footprint** | Single static **~12 MB** Rust binary; **<18 MB** idle RSS memory. | Python application; **150–350 MB** idle RSS in our local measurements (v1.50+ on Python 3.11). |
| **Startup Time** | **<10 ms** process start; well-suited for Kubernetes sidecars and edge nodes. | **1.5–4.5 s** cold start typical for Python/Uvicorn runtime initialization. |
| **Gateway Routing Latency** | **<1.2 ms p50** added proxy overhead (measured via in-process benchmark). | **5–15 ms p50** added routing overhead typical for Python ASGI event loops. |
| **Stateful Sessions** | **Native `/v1/responses`** turn chaining with in-process lock-free `DashMap` & embedded `RedB`. | Primarily stateless proxy; supports OpenAI Responses API; relies on external Redis/PostgreSQL for caching & persistent state. |
| **External Dependencies** | **Zero external dependencies**; embedded persistence included in binary. | Operates standalone from YAML config; PostgreSQL/Redis required when enabling virtual keys, team budget tracking, or caching. |
| **Provider Breadth** | Curated high-throughput backends (Groq, Gemini, OpenAI, Ollama/vLLM). | **100+ LLM providers** supported out-of-the-box. |
| **Virtual Keys & UI** | Minimalist configuration via TOML and environment variables. | Comprehensive Web UI dashboard, virtual API key provisioning, and team spend management. |

**When to choose Swarm**: When you require low proxy routing latency (<1.2ms), minimal container footprints (<18MB RSS), sub-10ms container cold starts, native in-process stateful turn persistence, or a lightweight Kubernetes sidecar.

---

## Performance & Footprint

Measurements below were captured on an 8-core x86_64 Linux host with a release build (`cargo build --release -p agent_core --bin swarm_gateway`):

| Metric | Swarm Gateway | Notes / Reproducibility |
| :--- | :---: | :--- |
| **Binary Size** | **~12 MB** | Single stripped static binary; zero dynamic runtime dependencies. |
| **Cold Start Time** | **< 10 ms** | Time from process invocation to listening socket ready on `127.0.0.1:8088`. |
| **Idle Memory (RSS)** | **< 18 MB** | Clean baseline RSS after Tokio async runtime initialization. |
| **Added Proxy Latency** | **< 1.2 ms (p50) / < 3.5 ms (p99)** | Added gateway overhead per request (excluding upstream model inference). Reproduce with `make bench`. |
| **Concurrency Model** | **Tokio Async Epoll** | Asynchronous, non-blocking I/O event loop; avoids thread-per-request allocation. |
| **Session Lookup** | **In-Process Lock-Free** | Local `DashMap` memory access; avoids loopback socket hops and serialization overhead. |
| **Runtime Safety** | **Enforced by Lint** | Compile-time `#![deny(clippy::unwrap_used, clippy::expect_used)]` on non-test runtime code. *(Note: Does not prevent slice index panics, arithmetic overflows, explicit `panic!`, or panics in dependencies.)* |

---

## Security & Inbound Authentication

### Safe Default Binding
By default, Swarm Gateway binds strictly to loopback: `bind_address = "127.0.0.1:8088"`.

> [!WARNING]
> **Authentication is disabled by default**: If you override the bind address to `0.0.0.0:8088` for container deployments without configuring authentication, any client on your network can issue model completions against your upstream provider API keys.
> 
> When exposing Swarm Gateway beyond `127.0.0.1`, always enable inbound authentication.

### How to Enable Authentication

1. **Environment Variables**:
   Provide a 256-bit symmetric secret key (at least 32 characters long), audience, and issuer:
   ```bash
   export SWARM_AUTH_SECRET="your-256-bit-secret-key-here-must-be-at-least-32-chars-long"
   export SWARM_AUTH_AUDIENCE="swarm-api"
   export SWARM_AUTH_ISSUER="swarm-auth-service"
   ```

2. **Configuration File (`gateway_config.toml`)**:
   ```toml
   [auth]
   enabled = true
   secret = "your-256-bit-secret-key-here-must-be-at-least-32-chars-long" # Min 32 bytes
   audience = "swarm-api"
   issuer = "swarm-auth-service"
   ```

3. **In-Code Initialization**:
   Attach the authenticator to the gateway server instance:
   ```rust
   let auth = OAuth2JwtAuthenticator::try_new(secret, audience, issuer)?;
   let gateway_server = GatewayServer::new(session_store, backend)
       .with_authenticator(SharedAuthenticator::new(auth));
   ```

### Minting a Test JWT Token

Use the bundled pure-Bash token generator (`openssl`-based, zero external dependencies):

```bash
# Mint a valid 1-hour test token with claims {sub: user_1, tenant_id: tenant_demo}:
make token
# or execute the script directly:
./examples_calls/mint_test_token.sh
```

### Making Authenticated Requests

Pass the minted JWT token in the `Authorization: Bearer <token>` header:

```bash
TOKEN=$(make token)

curl -s -X POST http://127.0.0.1:8088/v1/chat/completions \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model": "openai/gpt-oss-20b", "messages": [{"role": "user", "content": "Hello"}]}'
```

### Authentication Characteristics:
* **Algorithm**: **HS256 symmetric HMAC secret only**. (RS256 and JWKS public key endpoints are on the roadmap).
* **Minimum Secret Length**: 32 characters (256 bits). Shorter keys fail with an initialization error.
* **Validation**: Enforces `exp` (expiration), `nbf` (not-before), `iss` (issuer), `aud` (audience), and allows a 60-second clock skew tolerance.
* **Tenant Extraction**: Extracts `tenant_id` (or `sub`) from validated claims to bind session operations to caller identity.
* **Health Endpoint Bypass**: `/health` and `/v1/health` probes deliberately bypass authentication for container liveness and readiness monitoring.

---

## Supported API Endpoints

### 1. Stateless Chat Completions (`POST /v1/chat/completions`)
* Strictly OpenAI API specification compliant (compatible with official OpenAI SDKs, LangChain, LlamaIndex, Cursor, Continue).
* Completely stateless: does not mutate or access session memory stores.
* Preserves and forwards `tools` and `tool_choice` declarations to upstream models.

```bash
curl -s -X POST http://127.0.0.1:8088/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-oss-20b",
    "messages": [
      {"role": "system", "content": "You are a concise assistant."},
      {"role": "user", "content": "What is the capital of France?"}
    ],
    "stream": false
  }' | jq .
```

#### Output:
```json
{
  "id": "chatcmpl-a1f7f614-1c9d-40ac-a7ad-3eb79960f02c",
  "object": "chat.completion",
  "created": 1792930197,
  "model": "openai/gpt-oss-20b",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Paris.",
        "tool_calls": null
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 87,
    "completion_tokens": 23,
    "total_tokens": 110
  }
}
```

---

### 2. Stateful Open Responses (`POST /v1/responses`)
* **Stateful Turn Chaining**: Eliminates client-side context resending. Clients send only the latest turn.
* **Chained by ID**: Provide `previous_response_id` to link the conversation turn to existing session memory.

```bash
# Turn 1: Initial query (saves state in gateway store)
TURN1_RESP=$(curl -s -X POST http://127.0.0.1:8088/v1/responses \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-oss-20b",
    "input": "My favorite city is Boston.",
    "stream": false
  }')

echo "$TURN1_RESP" | jq .
# Returns: { "id": "resp_b8d1312d...", ... }

PREV_ID=$(echo "$TURN1_RESP" | jq -r .id)

# Turn 2: Follow-up query sending ONLY the new turn
curl -s -X POST http://127.0.0.1:8088/v1/responses \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-oss-20b",
    "previous_response_id": "'"$PREV_ID"'",
    "input": "What city did I say was my favorite?",
    "stream": false
  }' | jq .
```

#### Turn 2 Response (demonstrating recovered state):
```json
{
  "id": "resp_d9dc3872-4cd4-41a8-8ec8-fb467e897577",
  "object": "response",
  "output": [
    {
      "type": "message",
      "role": "assistant",
      "content": [
        {
          "type": "text",
          "text": "You said your favorite city is **Boston**."
        }
      ]
    }
  ]
}
```

---

### 3. Health & Readiness Probes (`GET /health` & `GET /v1/health`)
Unauthenticated probes designed for Kubernetes liveness/readiness probes and load balancers. Returns `200 OK` and active operational mode.

> [!NOTE]
> Probes report gateway process health (`status: "healthy"`) and operational mode (`mode: "gateway-only"`). They do **not** run live upstream inference pings on every probe to avoid latency and recurring API billing during high-frequency orchestrator health checks.

```bash
curl -s http://127.0.0.1:8088/health | jq .
```
```json
{
  "mode": "gateway-only",
  "service": "swarm-gateway",
  "status": "healthy",
  "version": "0.2.0"
}
```

---

## Resilience & Error Mapping

Swarm includes zero-dependency resilience primitives to isolate upstream provider instability:

| Resilience Feature | Description | HTTP Status On Trip |
| :--- | :--- | :---: |
| **Concurrency Limiting** | Semaphore-backed inflight request cap. Rejects excess requests to prevent Tokio worker starvation under traffic surges. | `429 Too Many Requests` |
| **Execution Deadlines** | Enforces per-request deadlines (`request_timeout_seconds`). Cancels hung provider sockets and frees client connections. | `408 Request Timeout` / `504 Gateway Timeout` |
| **Provider Circuit Breakers** | Tracks consecutive provider failures. Temporarily trips broken providers offline and uses half-open probes for cooldown and recovery. | `503 Service Unavailable` |
| **Cross-Provider Fallback** | Automatically retries across configured `models.fallback` list before reporting an upstream failure. | Transparent Recovery / `502 Bad Gateway` |
| **Upstream Error Mapping** | Transforms provider rate limits and transient errors into structured, client-friendly error payloads. | `429 Too Many Requests` / `502 Bad Gateway` |

### Mid-Stream Failure Behavior
* **Pre-stream Failover**: If an upstream provider fails before emitting any response tokens, Swarm transparently executes configured fallback models.
* **Mid-stream Failover**: If an upstream connection drops **after** HTTP 200 headers and initial SSE token chunks have been flushed to the client, protocol constraints prevent switching models mid-stream. In this case, Swarm terminates the SSE connection with an error event.

---

## Intelligent Model Routing

### Routing Precedence Rules

Swarm resolves which upstream provider handles a given request using the following strict resolution order:

| Precedence | Step | Matching Condition | Examples | Routed Provider |
| :---: | :--- | :--- | :--- | :--- |
| **1** | **Exact Config Mapping** | Model string explicitly listed under `[providers.<name>].recommended_models` | `openai/gpt-oss-20b` listed under `[providers.groq]` | Provider declared in TOML |
| **2** | **Prefix & Keyword Matching** | Target model starts with provider prefix or contains engine keyword | `google/*`, `*gemini*`<br>`groq/*`, `qwen/*`<br>`gpt-*`, `o1*`, `o3*` (prefix match)<br>`ollama/*`, `local/*`, `custom/*`, or tags with `:` (`llama3.2:latest`) | Google Gemini<br>Groq<br>OpenAI<br>Custom local endpoint |
| **3** | **Default Model** | Unmatched model strings fallback to `models.default_model` | Unspecified model | Configured default provider |

*Note on `openai/gpt-oss-20b`: This model identifier is hosted by Groq and is explicitly listed in `[providers.groq].recommended_models` (Precedence 1). Furthermore, the OpenAI rule checks for prefix `gpt-` (`starts_with("gpt-")`), so `openai/gpt-oss-20b` would not match OpenAI prefix routing.*

### Cross-Provider Fallback & Data Egress

#### Cross-Provider Resilience
In [`gateway_config.toml`](swarm/kickstart/gateway_kickstart/config_files/gateway_config.toml), fallbacks should target **distinct providers**. For example:
```toml
[models]
default_model = "openai/gpt-oss-20b"            # Primary: Groq
fallback = ["gemini-2.0-flash", "gpt-4o-mini"] # Fallback: Google -> OpenAI
```
*If a fallback targets another model on the same provider (e.g. Groq -> Groq), an outage on that provider will trip the circuit breaker for both models, defeating the purpose of the failover.*

#### Data Egress Warning for Local Models
> [!IMPORTANT]
> If you configure a local inference model (`custom/llama3.2:latest`) and configure cloud models in `models.fallback`, a local provider failure **will fail over to the cloud provider**, causing data to leave your infrastructure.
> 
> To guarantee **Zero Data Egress**, configure `models.fallback` to contain only local endpoints, or leave `fallback` empty.

---

## Session Storage Architecture

Swarm Gateway features a two-tiered session storage architecture:
1. **In-Memory Tier (`DashMap`)**: High-throughput, lock-free concurrent hash map. Bounded by FIFO eviction (`max_history_items`) and timeout expiration (`session_timeout_seconds`).
2. **Persistent Tier (`RedB`)**: Pure Rust embedded key-value database (ACID-compliant, zero external C dependencies). Guarantees session survival across gateway restarts.

### Tenancy & Session Isolation
* **Collision-Free Composite Keys**: In multi-tenant environments, session keys use length-prefixed colon namespacing (`urn:swarm:tenant:{tenant_id}:session:{session_id}`) rather than simple underscore delimiters. This prevents cross-tenant delimiter collision attacks (e.g. distinguishing tenant `a_b` with thread `c` from tenant `a` with thread `b_c`).
* **Tenant Boundary Enforcement**: When authentication is enabled, requesting a `previous_response_id` belonging to another tenant **returns HTTP 404 Not Found**. Callers cannot access or append turns to foreign sessions.
* **Storage at Rest**: By default, `RedB` stores session history unencrypted on disk in `database/`. For sensitive production environments, apply filesystem-level encryption (e.g. LUKS/dm-crypt) and restrict directory permissions (`chmod 700 database/` to preserve directory traversal execute permissions, with `chmod 600 database/*` on the database files).

---

## Configuration Reference (`gateway_config.toml`)

Gateway configuration is defined in [`swarm/kickstart/gateway_kickstart/config_files/gateway_config.toml`](swarm/kickstart/gateway_kickstart/config_files/gateway_config.toml):

```toml
[server]
# TCP socket binding address (127.0.0.1 for safe local isolation; 0.0.0.0 for Docker/Kubernetes)
bind_address = "127.0.0.1:8088"
host = "127.0.0.1"
port = 8088
log_level = "info"

[auth]
# When enabled, protects /v1/chat/completions and /v1/responses with HS256 JWT
enabled = false
# Minimum 32 characters (256-bit symmetric HMAC secret):
secret = "your-256-bit-secret-key-here-must-be-at-least-32-chars-long"
audience = "swarm-api"
issuer = "swarm-auth-service"

[session]
# Max turns retained per session in memory before FIFO eviction
max_history_items = 100
# Session inactivity expiration in seconds
session_timeout_seconds = 3600

[models]
default_model = "openai/gpt-oss-20b"
# Cross-provider fallbacks tried in sequence if primary provider fails:
fallback = [
    "gemini-2.0-flash",
    "gpt-4o-mini"
]

[providers.groq]
api_url = "https://api.groq.com/openai/v1/chat/completions"
recommended_models = [
    "groq/llama-3.3-70b-versatile",
    "openai/gpt-oss-20b"
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
# Local inference endpoint (Ollama / vLLM)
api_url = "http://localhost:11434/v1/chat/completions"
recommended_models = [
    "llama3.2:latest",
    "mistral:latest"
]

[resilience]
# Max concurrent in-flight requests (Tokio semaphore load shedding)
max_concurrent_requests = 512

# Per-request execution timeout in seconds
request_timeout_seconds = 60

# Consecutive error threshold before tripping circuit breaker
circuit_breaker_failure_threshold = 5

# Reset cooldown in seconds before testing recovery probe
circuit_breaker_reset_seconds = 30
```

---

## Deep Dive & Documentation

For developers and architects requiring detailed subsystem specifications and deployment blueprints:

* **[swarm/README.md](swarm/README.md)**: **Standalone server crate deep dive** covering internal runtime structures, operational kickstart scripts, and crate compilation.
* **[Architecture & Design Guide](swarm/docs/ARCHITECTURE.md)**: Subsystem pipelines, session key resolution models, and async concurrency lifecycles.
* **[Deployment & Operations](swarm/docs/DEPLOYMENT.md)**: Bare metal, Docker, and Kubernetes deployment patterns and liveness configurations.
* **[Design Principles](swarm/docs/DESIGN_PRINCIPLES.md)**: Architectural invariants and safe isolation standards.
* **[Evaluation & Benchmarks](swarm/docs/EVALUATION.md)**: Resilience test cases, circuit-breaker trip verification, and latency benchmarks under load.
* **[Product Roadmap](swarm/docs/ROADMAP.md)**: Strategic development milestones and planned capabilities.

---

## Product Roadmap

Key planned capabilities currently under development:
* **Prometheus Metrics Exporter**: Native `/metrics` endpoint publishing latency histograms, circuit-breaker states, and token counters.
* **Unified OpenTelemetry Tracing**: Distributed tracing across gateway ingress, routing decisions, provider latency, and token attribution.
* **Policy-Based Routing Engine**: Declarative rules for strict data residency enforcement, cost budgets, and model allow/deny lists.
* **Per-Tenant Rate Limiting & Quotas**: Token and request-rate budgets enforced per tenant with composite session keys.
* **RS256 / JWKS Support**: Asymmetric OAuth2 JWT verification supporting external identity providers (OIDC / Keycloak / Okta).
* **Exact & Semantic Response Caching**: In-memory and distributed caching to cut latency and API spend for idempotent prompts.
* **Cloud-Native Packaging**: Official lightweight Docker images, Helm charts, and Kubernetes sidecar deployment templates.

---

## License

This project is licensed under the **Business Source License 1.1 (BSL 1.1)** - see the [LICENSE](LICENSE) file for details.

* **Personal & Evaluation Use**: Free of charge for personal, non-commercial, research, and testing/evaluation purposes.
* **Commercial & Production Use**: Requires a separate commercial license from the Licensor.
* **Eventual Open Source Conversion**: Converts automatically to the **Apache License, Version 2.0** 3 years after the release date.

For commercial licensing terms and inquiries, please see [LICENSE](LICENSE).
