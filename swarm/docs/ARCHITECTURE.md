# Swarm Model Gateway Architecture

This document describes the architectural design, runtime components, and operational flow of the **Swarm Model Gateway** (`swarm_server`).

---

## Architectural Overview

Swarm Model Gateway functions as a production-grade, high-performance proxy and routing layer positioned between client applications and upstream LLM providers (cloud and local).

```text
                      Client Application / API Consumer
                                      │
                                      ▼
    ┌─────────────────────────────────────────────────────────────────┐
    │                     SWARM MODEL GATEWAY                         │
    │                    (Axum / Tokio Runtime)                       │
    ├─────────────────────────────────────────────────────────────────┤
    │ 1. INBOUND AUTH MIDDLEWARE (Optional)                           │
    │    • SharedAuthenticator (OAuth2 / HS256 JWT validation)        │
    │    • Public bypass for /health & /v1/health                     │
    ├─────────────────────────────────────────────────────────────────┤
    │ 2. RESILIENCE & ADMISSION CONTROLS                              │
    │    • Semaphore-based Concurrency Limiting (429 Too Many)        │
    │    • Request Execution Deadlines & Timeouts (504 Gateway Timeout│
    │    • Provider Circuit Breakers & Cooldown (503 Unavailable)     │
    ├─────────────────────────────────────────────────────────────────┤
    │ 3. API ROUTING & PROTOCOL HANDLERS                              │
    │    • POST /v1/chat/completions (OpenAI Compatible, Stateless)   │
    │    • POST /v1/responses (Stateful Multi-Turn Session Isolation) │
    │    • GET  /health (Readiness & Provider Probes)                 │
    ├─────────────────────────────────────────────────────────────────┤
    │ 4. SESSION & STATE MANAGEMENT                                   │
    │    • SessionStore (Bounded FIFO Turn Memory & TTL Eviction)     │
    │    • SessionKeyResolver (Tenant-isolated session keys)          │
    ├─────────────────────────────────────────────────────────────────┤
    │ 5. MULTI-MODEL BACKEND & PROVIDER ROUTING                       │
    │    • MultiModelGatewayBackend with Fallback Retries             │
    │    • Upstream Tool Forwarding & Call Preservation               │
    └─────────────────┬─────────────────────────────┬─────────────────┘
                      │                             │
               ┌──────┴──────────────┐       ┌──────┴──────────────┐
               ▼                     ▼       ▼                     ▼
          Groq Cloud            Google Gemini   OpenAI Cloud    Local Inference
          (Llama/Qwen)          (Gemini 2.0)    (GPT-4o)        (Ollama / vLLM)
```

---

## Core Gateway Components

### 1. Gateway Server Runtime (`swarm_server`)

Built with `axum` and `tokio`, the server provides an async, non-blocking runtime designed for high request concurrency with predictable P99 latencies and low RSS memory consumption.

- **Default Port**: `8088`.
- **Default Bind Address**: `127.0.0.1:8088` (safe localhost default preventing LAN exposure, avoiding conflict with Trust Gateway on `8080`).
- **Binary Footprint**: ~12MB release binary.
- **Cold Start**: Under 10ms.

### 2. API Endpoints

| Endpoint | Method | Mode | Purpose |
|---|:---:|:---:|---|
| `/v1/chat/completions` | `POST` | Stateless | OpenAI-compatible chat completion. Zero accidental session state writes. Supports tool forwarding and streaming SSE. |
| `/v1/responses` | `POST` | Stateful | Open Responses protocol. Automatically stores and chains assistant turns using isolated session identifiers (`previous_response_id`). |
| `/health` | `GET` | Probe | Public health probe returning gateway status and count of configured providers. |
| `/v1/health` | `GET` | Probe | Alias for `/health` to match versioned path prefixes. |

### 3. Multi-Model Gateway Backend (`MultiModelGatewayBackend`)

The gateway backend dynamically resolves models to their respective upstream providers:

- **Provider Adapters**:
  - `Groq`: Low-latency generation for open-weights models (e.g. Llama 3.3, Qwen).
  - `Google`: Gemini models via Generative Language API.
  - `OpenAI`: Standard GPT-4o / GPT-4o-mini endpoints.
  - `Custom`: OpenAI-compatible self-hosted servers (Ollama, vLLM, LocalAI).
- **Fallback Retries**: If a primary model provider encounters a recoverable error or outage, the backend automatically evaluates configured fallback providers before returning a failure.
- **Tool Forwarding & Call Preservation**: `GatewayTurnOptions` preserves client-provided `tools` and `tool_choice`, forwarding them to upstream models and maintaining returned tool call schemas across both streaming SSE and non-streaming responses.

### 4. Session & State Management (`SessionStore`)

For stateful `/v1/responses`:
- **Bounded Session History**: Configured via `SessionStore::with_limits(max_items, ttl)` with FIFO truncation when capacity is exceeded to eliminate memory leaks.
- **Background TTL Cleanup**: Expired sessions are evicted periodically in the background.
- **Tenant Isolation**: Handled via `SessionKeyResolver`:
  - `A2aSessionKeyResolver`: Prevents cross-tenant state leakage by requiring explicit session tokens.
  - `TenantThreadResolver`: Resolves composite `{tenant}_{thread}` keys for enterprise multi-tenancy.
- **Turn History Persistence**: Completed assistant turns are automatically recorded into the session store upon successful generation.

### 5. Resilience & Admission Control

Swarm embeds production safety controls directly in front of LLM calls:

- **Tokio Semaphore Concurrency Bounding**: Caps inflight requests to prevent worker thread starvation during traffic surges (`429 Too Many Requests`).
- **Execution Deadlines**: Cancels slow or stalled upstream connections after a configured timeout (`504 Gateway Timeout` or `408 Request Timeout`).
- **Provider Circuit Breakers**: Tracks consecutive upstream provider failures. Once the threshold is exceeded, requests fail fast with `503 Service Unavailable` without taxing the downstream model, until the cooldown window resets.
- **Structured Error Mapping**: Upstream errors (rate limits, timeouts, bad gateways) are translated into standardized HTTP status codes.

### 6. Security & Authentication Middleware

When JWT authentication is enabled:
- **Algorithm Pinning**: Strictly pinned to `HS256`.
- **Mandatory Audience and Issuer**: Both `audience` and `issuer` are required; configurations omitting them are rejected at startup.
- **Clock Skew Tolerance**: 60-second leeway on `exp` and `nbf` claims.
- **Safe Binding**: `parse_bind_address` safely parses `http://`, `https://`, or host:port strings.
- **Route Isolation**: `/v1/chat/completions` and `/v1/responses` require valid bearer tokens, while `/health` remains accessible for load balancer probes.

---

## Workspace Dependencies & Crate Architecture

The Gateway leverages shared primitives from `swarm_commons`:

```text
swarm (Workspace)
└── swarm_server (Gateway Binary & Router)
    ├── agent_core          # GatewayServer, MultiModelGatewayBackend, SessionStore
    ├── configuration       # Logging setup & config parsing
    ├── llm_api             # Provider HTTP clients & streaming abstractions
    └── agent_models        # Shared request/response types & RequestContext
```

- **`swarm_server`**: Binary crate and router definition.
- **`agent_core`**: Contains `GatewayServer`, `MultiModelGatewayBackend`, and `SessionStore`.
- **`llm_api`**: Upstream client abstractions for OpenAI, Google Gemini, Groq, and custom endpoints.
- **`configuration`**: Structured TOML loaders and logging initialization.

---

## Target Gateway Evolution

Key areas of upcoming architecture development include:
1. **OpenTelemetry Distributed Tracing**: Attaching global trace contexts across gateway admission, routing decisions, provider latency, and token metrics.
2. **Dynamic Policy Routing**: Declarative rules based on data residency (e.g. routing European requests to local inference), cost budgets, or latency thresholds.
3. **Response Caching**: Semantic and exact match caching layers for prompt reduction.
