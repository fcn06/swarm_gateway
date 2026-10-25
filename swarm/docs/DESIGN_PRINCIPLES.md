# Design Principles

Swarm Model Gateway is built upon a core set of engineering principles designed to deliver an ultra-fast, resilient, and production-hardened LLM proxy.

---

## 1. Open Standards & Interoperability

Applications should not be forced into proprietary SDKs or runtime lock-in.

- **Stateless Compatibility**: Fully compliant with the standard OpenAI `/v1/chat/completions` API specification.
- **Stateful Turn Chaining**: Native support for `/v1/responses` for multi-turn sessions with isolated context.
- **Tool Fidelity**: Unaltered forwarding and retention of `tools` and `tool_choice` schemas across both streaming SSE and non-streaming calls.

---

## 2. Resilient by Default

Downstream LLM provider degradation or outages must never bring down user-facing applications.

- **Admission Control**: Semaphore-based concurrency limiting protects server worker threads from being overwhelmed.
- **Circuit Breakers**: Consecutive provider errors automatically trip circuit breakers, failing fast during outages and probing recovery during cooldown windows.
- **Multi-Provider Fallbacks**: Requests transparently retry across secondary configured providers when primary endpoints fail.
- **Structured Error Mapping**: Upstream failures translate into unambiguous HTTP status codes (`429`, `502`, `503`, `504`).

---

## 3. Cloud / Local Inference Symmetry

Local and self-hosted models are treated as first-class citizens.

- Applications interact with the same gateway API surface whether querying cloud endpoints (Groq, Google Gemini, OpenAI) or local infrastructure (Ollama, vLLM, LocalAI).
- Switching models or routing requests between edge and cloud requires zero changes to application code.

---

## 4. Strict Session & Tenant Isolation

Multi-turn state must be safe in multi-tenant environments.

- **Pluggable Session Key Resolvers**: Composite keys (`{tenant}_{thread}`) and mandatory session tokens eliminate cross-tenant data leakage.
- **Memory Bounding**: Bounded FIFO session stores with automatic background TTL eviction prevent unbounded memory growth and memory exhaustion.
- **Clean Separation**: Stateless `/v1/chat/completions` guarantees zero unintended writes to session stores.

---

## 5. Production-Oriented Safety

Reliability is enforced at compile time and runtime:

- **Zero-Panic Assurance**: Strict compile-time `#![deny(clippy::unwrap_used, clippy::expect_used)]` across runtime code paths.
- **Hardened Authentication**: Pinned HS256 JWT validation, mandatory audience and issuer verification, and clock-skew leeway.
- **Public Probe Bypass**: Container readiness probes (`/health`) remain accessible even when token authentication is enforced on API routes.

---

## 6. Minimal Operational Footprint

The gateway is built for high density, edge deployment, and microservice sidecars:

- **Fast Cold Starts**: Starts in under 10ms.
- **Compact Binary**: Under 12MB release binary.
- **Low Baseline Memory**: Predictable, small RSS memory footprint with zero garbage-collection pauses.
