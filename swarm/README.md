# 🚀 Swarm — Production-Grade, Resilient AI Model Gateway 🦀

[![Rust](https://img.shields.io/badge/Rust-1.80%2B-orange?logo=rust)](https://www.rust-lang.org)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue)](LICENSE)
[![Binary Size](https://img.shields.io/badge/Gateway%20Binary-~12MB-success)](#operational-footprint)
[![Resilience](https://img.shields.io/badge/Resilience-Circuit%20Breaker%20%2B%20Throttling-brightgreen)](#enterprise-resilience--production-hardening)
[![OpenAI Compatible](https://img.shields.io/badge/API-OpenAI%20%2B%20Open%20Responses-blue)](#api-surfaces)

> **Swarm is a high-performance, resilient AI Model Gateway built in Rust. It provides unified, production-hardened access to cloud and local LLMs through standard OpenAI-compatible endpoints (`/v1/chat/completions`) and stateful, multi-turn Open Responses (`/v1/responses`) with built-in circuit breaking, concurrency throttling, and multi-provider failover.**

---

## Table of Contents

- [Why Swarm Gateway?](#why-swarm-gateway)
- [Operational Footprint](#operational-footprint)
- [API Surfaces](#api-surfaces)
  - [Stateless Chat Completions (`/v1/chat/completions`)](#1-stateless-chat-completions-v1chatcompletions)
  - [Stateful Open Responses (`/v1/responses`)](#2-stateful-open-responses-v1responses)
  - [Cloud-Native Health Probes (`/health`)](#3-cloud-native-health-probes-health)
- [Enterprise Resilience & Production Hardening](#enterprise-resilience--production-hardening)
- [Quick Start](#quick-start)
  - [Step 1 — Launch the Gateway](#step-1--launch-the-gateway)
  - [Step 2 — Verify Health & Readiness](#step-2--verify-health--readiness)
  - [Step 3 — Execute Chat & Stateful Turns](#step-3--execute-chat--stateful-turns)
- [Supported Model Providers](#supported-model-providers)
- [Configuration Reference](#configuration-reference)
- [Key Capabilities](#key-capabilities)
- [Project Roadmap](#project-roadmap)
- [Documentation](#documentation)
- [Repository Structure](#repository-structure)
- [License](#license)

---

## Why Swarm Gateway?

Production applications integrating LLMs face operational hurdles: provider outages, unexpected rate limits, hung connections, incompatible payload formats, and lack of state management across turns.

Swarm addresses this by providing a unified, ultra-fast gateway proxy between your applications and upstream LLM providers:

```text
                Client Application / API Consumer
                                │
                                ▼
  ┌───────────────────────────────────────────────────────────┐
  │                 SWARM MODEL GATEWAY                       │
  │                 (swarm_server :8088)                      │
  ├───────────────────────────────────────────────────────────┤
  │  • /v1/chat/completions (OpenAI Compatible + Tool Forward)│
  │  • /v1/responses (Stateful Multi-Turn Session Isolation)  │
  │  • Multi-Provider Routing & Automatic Fallback Retries    │
  │  • Tokio Semaphore Concurrency Throttling                 │
  │  • Circuit Breaker Outage Isolation & Cooldown            │
  │  • Pluggable Bearer JWT Authentication                    │
  │  • Public /health & /v1/health Readiness Probes           │
  └──────────────┬─────────────────────────────┬──────────────┘
                 │                             │
          ┌──────┴──────────────┐       ┌──────┴──────────────┐
          ▼                     ▼       ▼                     ▼
     Cloud Providers               Local Inference Endpoints
     OpenAI, Gemini, Groq          Ollama, vLLM, LocalAI
```

### Key Customer Value Proposition

- **Single Stable API**: Code against one standard interface while routing across Groq, Gemini, OpenAI, or self-hosted Ollama/vLLM backends.
- **Resilient Against Provider Outages**: Circuit breakers isolate failing providers; automatic fallback retries seamlessly reroute requests to alternative models.
- **Stateful Multi-Turn Turns Built-In**: Use `/v1/responses` for isolated conversational history without maintaining external state machinery in your application layer.
- **High Concurrency & Predictable Latency**: Written in 100% safe Rust and Tokio, delivering sub-10ms startup, zero garbage-collection pauses, and minimal memory usage.

---

## Operational Footprint

- **Lightweight Binary**: Single release binary (`swarm_server`) under **12 MB**.
- **Cold Starts**: Under **10ms**, making it ideal for Kubernetes sidecars, serverless containers, or edge deployment.
- **Memory Consumption**: Extremely low baseline RSS memory footprint with bounded FIFO session stores and automatic TTL cleanup.
- **Zero-Panic Safety**: Compile-time `#![deny(clippy::unwrap_used, clippy::expect_used)]` enforced across core runtime code paths.

---

## API Surfaces

### 1. Stateless Chat Completions (`/v1/chat/completions`)
Strictly adheres to the OpenAI Chat Completions specification with:
- Zero accidental session store side effects.
- Full upstream tool forwarding (`tools` and `tool_choice`) with preserved tool call structures.
- Both Server-Sent Events (SSE) token streaming and synchronous JSON responses.

### 2. Stateful Open Responses (`/v1/responses`)
Provides multi-turn conversational session chaining:
- Assistant responses are automatically recorded into session memory.
- Sessions are isolated by composite keys (`SessionKeyResolver`) to eliminate cross-tenant data leakage.
- Linked follow-ups via `previous_response_id`.

### 3. Cloud-Native Health Probes (`/health` & `/v1/health`)
Unauthenticated health probe endpoints designed for Kubernetes liveness and readiness checks, returning provider readiness and server status.

---

## Enterprise Resilience & Production Hardening

When deploying LLMs to production, upstream provider latency spikes, rate limits, and outages can compromise your application. Swarm includes zero-dependency resilience features with structured HTTP error mappings:

| Resilience Feature | Description | HTTP Status On Trip |
|---|---|:---:|
| **Concurrency Limiting** | Caps inflight requests with a Tokio semaphore to protect worker threads from starvation under traffic surges. | `429 Too Many Requests` |
| **Execution Deadlines** | Enforces per-request timeouts so hung provider connections never tie up client sockets. | `408 Request Timeout` / `504 Gateway Timeout` |
| **Provider Circuit Breakers** | Detects consecutive upstream provider errors, tripping offline to fail fast and auto-recovering after a cooldown window. | `503 Service Unavailable` |
| **Multi-Provider Fallback Retries** | Automatically retries requests across alternative configured fallback providers in `MultiModelGatewayBackend`. | Transparent recovery / `502 Bad Gateway` |
| **Upstream Error Mapping** | Maps upstream rate limits and provider errors into clear, structured HTTP responses. | `429 Too Many Requests` / `502 Bad Gateway` |
| **Inbound Auth Middleware** | Optional `SharedAuthenticator` enforcing bearer JWT validation on API endpoints while keeping `/health` open. | `401 Unauthorized` |
| **Cloud-Native Health Checks** | Built-in `/health` endpoints returning operational readiness for load balancers. | `200 OK` / `503 Unhealthy` |

---

## Quick Start

### Step 1 — Launch the Gateway

Start the standalone gateway with its default configuration:

```bash
cd swarm
./kickstart/gateway_kickstart/01_launch_gateway.sh
```

By default, the server binds to `127.0.0.1:8088` (preventing conflicts with Trust Gateway on 8080).

### Step 2 — Verify Health & Readiness

```bash
curl http://localhost:8088/health
```

Expected response:
```json
{
  "mode": "gateway-only",
  "service": "swarm-gateway",
  "status": "healthy",
  "version": "0.2.0"
}
```

### Step 3 — Execute Chat & Stateful Turns

#### Standard OpenAI-Compatible Chat (`/v1/chat/completions`)

```bash
curl -X POST http://localhost:8088/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-oss-20b",
    "messages": [
      {"role": "user", "content": "Explain Swarm Gateway in one sentence."}
    ]
  }'
```

#### Tool Calling Request (Forwarded to Upstream Provider)

```bash
curl -X POST http://localhost:8088/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-oss-20b",
    "messages": [
      {"role": "user", "content": "What is the weather in Boston?"}
    ],
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get current weather for a city",
          "parameters": {
            "type": "object",
            "properties": {
              "location": {"type": "string"}
            },
            "required": ["location"]
          }
        }
      }
    ]
  }'
```

#### Stateful Turn Chaining (`/v1/responses`)

```bash
# Turn 1: Initial query (returns session ID "resp_123...")
curl -X POST http://localhost:8088/v1/responses \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-oss-20b",
    "input": "My favorite city is Boston."
  }'

# Turn 2: Follow-up query linked with previous_response_id
curl -X POST http://localhost:8088/v1/responses \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-oss-20b",
    "previous_response_id": "resp_123...",
    "input": "What is its most famous historic trail?"
  }'
```

*(Note: When inbound auth is enabled, include `-H "Authorization: Bearer <jwt>"` in your requests.)*

---

## Supported Model Providers

Swarm routes seamlessly across cloud and local providers:

| Provider | Type | Typical Use Case |
|---|---|---|
| **Groq** | Cloud | Ultra-low latency Llama 3.3 / Qwen generation |
| **Google Gemini** | Cloud | Multimodal and large context-window reasoning |
| **OpenAI** | Cloud | Industry-standard GPT-4o models |
| **Ollama / vLLM / LocalAI** | Local / Self-Hosted | Private, on-premise, zero-egress inference |

---

## Configuration Reference

The Gateway is configured via TOML (e.g. `kickstart/gateway_kickstart/config_files/gateway_config.toml`):

```toml
[server]
bind_address = "127.0.0.1:8088"
host = "127.0.0.1"
port = 8088
log_level = "info"

[session]
# In-memory session store settings
max_history_items = 100
session_timeout_seconds = 3600

[models]
default_model = "openai/gpt-oss-20b"

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
# Local Ollama / vLLM endpoint
api_url = "http://localhost:11434/v1/chat/completions"
recommended_models = [
    "llama3.2:latest",
    "mistral:latest"
]

[resilience]
# Concurrency limit for inflight requests (Tokio semaphore)
max_concurrent_requests = 512

# Global request execution timeout in seconds
request_timeout_seconds = 60

# Circuit breaker failure threshold before tripping
circuit_breaker_failure_threshold = 5

# Cooldown window in seconds before testing recovery
circuit_breaker_reset_seconds = 30
```

---

## Key Capabilities

- **Strict OpenAI Spec Compliance**: Stateless `/v1/chat/completions` with identical payload schemas.
- **Stateful Open Responses**: Multi-turn `/v1/responses` with pluggable session isolation (`A2aSessionKeyResolver`, composite `{tenant}_{thread}` keys).
- **Tool Forwarding & Preservation**: Full forwarding of `tools` and `tool_choice` across both streaming and non-streaming responses.
- **Multi-Provider Fallback Routing**: Automatic failover chains in `MultiModelGatewayBackend`.
- **Enterprise Resilience**: Concurrency caps, request execution deadlines, and circuit breakers with structured HTTP error codes.
- **Hardened Authentication**: Pluggable `SharedAuthenticator` enforcing HS256 JWT validation, audience & issuer checks, and clock skew tolerance.
- **Blazing Performance**: Sub-10ms cold start, ~12MB binary, and zero-mutex turn concurrency.

---

## Project Roadmap

Key upcoming gateway features include:
- **Unified OpenTelemetry Tracing**: Distributed tracing across gateway entry, routing decisions, provider latency, and token attribution.
- **Policy-Based Routing**: Declarative rules for data residency, model allow/deny lists, and cost budgets.
- **Semantic & Exact Response Caching**: In-memory and distributed caching to cut latency and API spend.
- **Per-Tenant Rate Limiting & Quotas**: Token and request-rate budgets enforced per tenant.
- **Cloud-Native Packaging**: Official lightweight Docker images, Helm charts, and Kubernetes sidecar templates.

See [docs/ROADMAP.md](docs/ROADMAP.md) for full roadmap details.

---

## Documentation

- [Architecture & Design](docs/ARCHITECTURE.md)
- [Deployment & Operations](docs/DEPLOYMENT.md)
- [Design Principles](docs/DESIGN_PRINCIPLES.md)
- [Roadmap](docs/ROADMAP.md)

---

## Repository Structure

```text
swarm/
├── Cargo.toml                                 # Workspace configuration (members = ["swarm_server"])
├── swarm_server/                              # Standalone Gateway server crate
│   ├── Cargo.toml
│   ├── src/
│   │   └── lib.rs                             # Gateway router, handlers, and session integrations
│   └── bin/
│       └── swarm_server.rs                    # Gateway CLI binary & configuration loader
├── kickstart/
│   └── gateway_kickstart/                     # Gateway launch scripts & payloads
│       ├── 01_launch_gateway.sh
│       ├── 02_test_chat_completions.sh
│       ├── 03_test_open_responses.sh
│       ├── 04_terminate_gateway.sh
│       └── config_files/
│           ├── gateway_config.toml            # Provider & resilience settings
│           └── chat_completions_request.json
├── docs/                                      # Gateway architectural & operational guides
│   ├── ARCHITECTURE.md
│   ├── DEPLOYMENT.md
│   ├── DESIGN_PRINCIPLES.md
│   └── ROADMAP.md
└── site/                                      # Documentation site assets
```

---

## License

Distributed under the [Apache License 2.0](LICENSE).
