# Gateway Evaluation & Provider Benchmarking

This document details benchmarking methodologies, provider performance tracking, and reliability evaluation for the **Swarm Model Gateway**.

---

## Gateway Evaluation Goals

When routing traffic across multiple upstream LLM providers (Groq, Gemini, OpenAI, Ollama), the gateway provides the ideal vantage point to measure:

1. **Latency & Response Times**: Time-to-First-Token (TTFT) and Total Response Time (TRT) per model.
2. **Availability & Error Rates**: Upstream provider 429 rate limits, 502/503 errors, and timeout frequencies.
3. **Resilience Behavior**: Verifying circuit breaker tripping, concurrency throttling, and automatic fallback retries.
4. **Output Integrity**: Ensuring upstream tool-call structures and token streams are preserved without distortion.

---

## Key Performance Indicators (KPIs)

| Metric | Target | Description |
|---|:---:|---|
| **Gateway Proxy Overhead** | `< 2 ms` | Internal processing overhead added by the gateway routing pipeline. |
| **Cold Start Time** | `< 10 ms` | Time from binary launch to socket bind and readiness. |
| **Concurrency Ceiling** | `512+ reqs` | Inflight requests handled safely without worker thread starvation. |
| **Circuit Breaker Trip Accuracy** | `100%` | Fast failure triggered when consecutive errors reach configured threshold. |
| **Fallback Switchover Time** | `< 50 ms` | Duration to reroute to secondary provider upon primary failure. |

---

## Automated Verification & Test Harnesses

The Gateway kickstart suite provides reproducible scripts to evaluate endpoint behavior:

### 1. Chat Completions Test
Validates stateless OpenAI payload parsing and upstream response forwarding:

```bash
./kickstart/gateway_kickstart/02_test_chat_completions.sh "Hello! Provide a 1-sentence response."
```

### 2. Stateful Turn Chaining Test
Validates multi-turn context retention, session isolation, and assistant turn persistence:

```bash
./kickstart/gateway_kickstart/03_test_open_responses.sh
```

### 3. Health & Readiness Probe
Validates provider registration and socket responsiveness:

```bash
curl -i http://localhost:8088/health
```

---

## Evaluating Resilience Under Load

To evaluate gateway resilience under simulated production stress:

### Concurrency Throttling Test
Trigger high concurrent load exceeding `max_concurrent_requests` (default: 512). The gateway must return `429 Too Many Requests` for surplus requests rather than crashing or exhausting file descriptors.

### Provider Outage & Circuit Breaker Test
Point a provider to an unreachable endpoint. Verify that:
1. The first $N$ requests (threshold) attempt connections and fail with structured timeouts.
2. Subsequent requests immediately return `503 Service Unavailable` without attempting upstream connections.
3. Once the cooldown window expires, the gateway allows a probe request to test provider recovery.

---

## Roadmap: Continuous Gateway Observability

Future gateway releases will introduce:
- Built-in OpenTelemetry metrics export (Prometheus/OTLP format).
- Automated token-cost tracking and latency percentile histograms per provider.
- Dynamic quality routing based on continuous historical latency and availability scores.
