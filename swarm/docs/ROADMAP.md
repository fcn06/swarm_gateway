# Swarm Model Gateway Roadmap

This document outlines the current capabilities and planned development milestones for the **Swarm Model Gateway**.

---

## Current Foundation

### 1. API Surfaces & Protocols
- [x] **OpenAI Chat Completions**: Stateless, standard `/v1/chat/completions` compliant with upstream OpenAI specifications.
- [x] **Open Responses**: Stateful `/v1/responses` with multi-turn session chaining and linked `previous_response_id`.
- [x] **Tool Forwarding & Preservation**: Forwarding `tools` and `tool_choice` schemas, retaining tool calls across both SSE streams and JSON payloads.
- [x] **Streaming**: Token-level Server-Sent Events (SSE) streaming for low perceived latency.
- [x] **Health Probes**: Public `/health` and `/v1/health` endpoints returning operational status and provider counts.

### 2. Multi-Provider Routing & Backends
- [x] **Cloud Providers**: Native support for Groq (Llama, Qwen), Google Gemini, and OpenAI (GPT-4o).
- [x] **Local & Self-Hosted**: Seamless support for Ollama, vLLM, and LocalAI endpoints.
- [x] **Automatic Fallback Retries**: Transparent retry chain across configured fallback providers in `MultiModelGatewayBackend`.

### 3. Production Resilience & Security
- [x] **Concurrency Throttling**: Tokio semaphore-backed inflight request bounding (`429 Too Many Requests`).
- [x] **Request Execution Deadlines**: Configurable request timeouts (`504 Gateway Timeout` / `408 Request Timeout`).
- [x] **Circuit Breaker**: Outage isolation with cooldown recovery window (`503 Service Unavailable`).
- [x] **Structured Error Mapping**: Clean translation of upstream rate limits (`429`) and gateway failures (`502`).
- [x] **Inbound JWT Authentication**: Pluggable `SharedAuthenticator` enforcing HS256 algorithm pinning, audience & issuer verification, and 60-second clock skew leeway.
- [x] **Tenant & Session Isolation**: Bounded FIFO session stores with automatic background TTL eviction and `SessionKeyResolver` isolation.
- [x] **Zero-Panic Safety**: Compile-time `#![deny(clippy::unwrap_used, clippy::expect_used)]` across runtime code paths.

---

## Near-Term Priorities

### 1. Distributed Tracing & OpenTelemetry
- [ ] Native OpenTelemetry (OTLP) export for traces and metrics.
- [ ] Distributed trace IDs linking client requests to upstream provider calls.
- [ ] Latency breakdowns (gateway proxy latency vs. upstream provider TTFT/TRT).
- [ ] Token-cost accounting and per-request token usage attribution.

### 2. Policy-Based Routing
- [ ] Declarative routing rules based on request metadata or tenant ID.
- [ ] Data-residency policies (e.g. enforcing local model routing for sensitive data).
- [ ] Model allowlists and blocklists per client or environment.
- [ ] Dynamic model fallback chains based on budget or speed requirements.

### 3. Semantic & Exact Response Caching
- [ ] Exact-match in-memory and Redis response cache for identical prompts.
- [ ] Semantic vector-based similarity caching to reduce redundant LLM calls.
- [ ] Configurable cache TTL and cache-control headers.
- [ ] Privacy-aware caching (bypassing caching for authenticated or sensitive requests).

### 4. Enterprise Rate Limiting & Quotas
- [ ] Token-bucket rate limiting per API key or tenant.
- [ ] Monthly / daily token consumption quotas.
- [ ] Tiered throttling with graceful degradation.

---

## Strategic Roadmap

### 5. Cloud-Native Packaging & Deployment
- [ ] Official hardened, multi-architecture Docker container images.
- [ ] Production Helm charts with autoscaling (HPA) based on inflight concurrency.
- [ ] Kubernetes sidecar injection manifests for ultra-low latency mesh routing.
- [ ] Native secret manager integrations (AWS Secrets Manager, HashiCorp Vault).

### 6. Reproducible Benchmark Suite
- [ ] Standardized benchmark harness measuring proxy overhead under high concurrent loads (1,000+ connections).
- [ ] Streaming throughput and memory footprint metrics under peak traffic.
- [ ] Comparative provider latency distributions published across releases.
