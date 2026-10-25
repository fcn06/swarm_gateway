# 🌐 Swarm Gateway — Sample API Calls & Testing Guide

This guide provides tested, executable cURL examples and request/response payloads for the **Swarm Standalone Model Gateway** (`127.0.0.1:8088`), covering both **OpenAI-compatible Chat Completions** and **Stateful Open Responses** endpoints.

---

## 📋 Table of Contents
- [1. Prerequisites & Launching Gateway](#1-prerequisites--launching-gateway)
- [2. Health & Readiness Probes (`GET /health` & `GET /v1/health`)](#2-health--readiness-probes-get-health--get-v1health)
- [3. Stateless Chat Completions (`POST /v1/chat/completions`)](#3-stateless-chat-completions-post-v1chatcompletions)
  - [3.1 Basic Chat Completion](#31-basic-chat-completion)
  - [3.2 Streaming SSE Completion](#32-streaming-sse-completion)
  - [3.3 Tool / Function Calling](#33-tool--function-calling)
- [4. Stateful Open Responses (`POST /v1/responses`)](#4-stateful-open-responses-post-v1responses)
  - [4.1 Turn 1: Initial Turn](#41-turn-1-initial-turn)
  - [4.2 Turn 2: Follow-Up Chained Turn](#42-turn-2-follow-up-chained-turn)
  - [4.3 Streaming Stateful Response](#43-streaming-stateful-response)
- [5. Provider Routing Examples](#5-provider-routing-examples)
- [6. Security & Bearer Authentication](#6-security--bearer-authentication)
- [7. Automated Test Script (`run_examples.sh`)](#7-automated-test-script-run_examplessh)

---

## 1. Prerequisites & Launching Gateway

Ensure at least one LLM provider API key is set in your environment or configured in `.env`:
```bash
export GROQ_API_KEY="gsk_..."
# or
export GEMINI_API_KEY="AIza..."
# or
export OPENAI_API_KEY="sk-..."
# or run a local Ollama instance on port 11434
```

Launch the gateway server from the workspace root:
```bash
cd /home/fred/Agents_Projects/Antigravity/codebase/four_tier_entreprise_agentic_stack/swarm_gateway
make launch
# Alternatively:
cd swarm && ./kickstart/gateway_kickstart/01_launch_gateway.sh
```

---

## 2. Health & Readiness Probes (`GET /health` & `GET /v1/health`)

Verify the gateway is operational and probe readiness:

```bash
curl -s http://127.0.0.1:8088/health | jq .
# or
curl -s http://127.0.0.1:8088/v1/health | jq .
```

### Verified Response:
```json
{
  "mode": "gateway-only",
  "service": "swarm-gateway",
  "status": "healthy",
  "version": "0.2.0"
}
```

---

## 3. Stateless Chat Completions (`POST /v1/chat/completions`)

The `/v1/chat/completions` endpoint is strictly OpenAI-compatible and stateless (zero accidental writes to the session store).

### 3.1 Basic Chat Completion

```bash
curl -s -X POST http://127.0.0.1:8088/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-oss-20b",
    "messages": [
      {
        "role": "system",
        "content": "You are a concise, helpful assistant."
      },
      {
        "role": "user",
        "content": "What is the capital of France?"
      }
    ],
    "stream": false
  }' | jq .
```

#### Verified Response:
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

### 3.2 Streaming SSE Completion

To receive token-by-token streaming, pass `"stream": true` and use `curl -N`:

```bash
curl -N -s -X POST http://127.0.0.1:8088/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-oss-20b",
    "messages": [
      {"role": "user", "content": "Count from 1 to 3."}
    ],
    "stream": true
  }'
```

#### Verified Stream Output:
```text
data: {"id":"chatcmpl-4fec...","object":"chat.completion.chunk","choices":[{"delta":{"content":"1"}}]}
data: {"id":"chatcmpl-4fec...","object":"chat.completion.chunk","choices":[{"delta":{"content":", "}}]}
data: {"id":"chatcmpl-4fec...","object":"chat.completion.chunk","choices":[{"delta":{"content":"2"}}]}
data: {"id":"chatcmpl-4fec...","object":"chat.completion.chunk","choices":[{"delta":{"content":", "}}]}
data: {"id":"chatcmpl-4fec...","object":"chat.completion.chunk","choices":[{"delta":{"content":"3"}}]}
data: [DONE]
```

---

### 3.3 Tool / Function Calling

Forward tool definitions directly to upstream providers (OpenAI, Gemini, Groq) with preserved structured arguments:

```bash
curl -s -X POST http://127.0.0.1:8088/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-oss-20b",
    "messages": [
      {"role": "user", "content": "What is the weather in Boston right now?"}
    ],
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Fetch the current weather for a specified city",
          "parameters": {
            "type": "object",
            "properties": {
              "location": {
                "type": "string",
                "description": "City and state/country, e.g. Boston, MA"
              },
              "unit": {
                "type": "string",
                "enum": ["celsius", "fahrenheit"]
              }
            },
            "required": ["location"]
          }
        }
      }
    ],
    "tool_choice": "auto"
  }' | jq .
```

#### Expected Tool Call Response:
```json
{
  "id": "chatcmpl-tools-8f3a1e2b",
  "object": "chat.completion",
  "created": 1729796410,
  "model": "openai/gpt-oss-20b",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": null,
        "tool_calls": [
          {
            "id": "call_weather_boston",
            "type": "function",
            "function": {
              "name": "get_weather",
              "arguments": "{\"location\":\"Boston, MA\",\"unit\":\"fahrenheit\"}"
            }
          }
        ]
      },
      "finish_reason": "tool_calls"
    }
  ]
}
```

---

## 4. Stateful Open Responses (`POST /v1/responses`)

The Open Responses standard supports stateful multi-turn interactions without requiring client applications to resend the entire conversation history with every turn.

Turns are chained using `previous_response_id`. Assistant answers are stored in the gateway's lock-free session store (`DashMap` / `RedB`).

### 4.1 Turn 1: Initial Turn

```bash
curl -s -X POST http://127.0.0.1:8088/v1/responses \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-oss-20b",
    "input": "My favorite city is Boston.",
    "stream": false
  }' | jq .
```

#### Verified Turn 1 Response:
```json
{
  "id": "resp_b8d1312d-507c-4495-bd0e-83656ead8826",
  "object": "response",
  "created": 1792930198,
  "model": "openai/gpt-oss-20b",
  "output": [
    {
      "type": "message",
      "id": "resp_msg_dba81ca0-31f3-4fb9-90a7-99ef3ffbfcb0",
      "role": "assistant",
      "content": [
        {
          "type": "text",
          "text": "That’s great! Boston has so much to offer. What’s your favorite thing about the city?"
        }
      ]
    }
  ],
  "usage": {
    "input_tokens": 77,
    "output_tokens": 128,
    "total_tokens": 205
  }
}
```

---

### 4.2 Turn 2: Follow-Up Chained Turn

Provide the `id` from Turn 1 as `previous_response_id`. The gateway automatically links the conversation context:

```bash
curl -s -X POST http://127.0.0.1:8088/v1/responses \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-oss-20b",
    "previous_response_id": "resp_b8d1312d-507c-4495-bd0e-83656ead8826",
    "input": "What city did I say was my favorite?",
    "stream": false
  }' | jq .
```

#### Verified Turn 2 Response:
```json
{
  "id": "resp_d9dc3872-4cd4-41a8-8ec8-fb467e897577",
  "object": "response",
  "created": 1792930198,
  "model": "openai/gpt-oss-20b",
  "output": [
    {
      "type": "message",
      "id": "resp_msg_7c5fae5f-8ec4-4c1e-a752-210bff075960",
      "role": "assistant",
      "content": [
        {
          "type": "text",
          "text": "You said your favorite city is **Boston**."
        }
      ]
    }
  ],
  "usage": {
    "input_tokens": 159,
    "output_tokens": 49,
    "total_tokens": 208
  }
}
```

---

### 4.3 Streaming Stateful Response

Use `"stream": true` with `curl -N`:

```bash
curl -N -s -X POST http://127.0.0.1:8088/v1/responses \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-oss-20b",
    "input": "Say hello in Spanish.",
    "stream": true
  }'
```

#### Verified Stream Output:
```text
event: response.item
data: {"id":"chatcmpl-...","object":"chat.completion.chunk","choices":[{"delta":{"content":"¡"}}]}

event: response.item
data: {"id":"chatcmpl-...","object":"chat.completion.chunk","choices":[{"delta":{"content":"Hola"}}]}

event: response.item
data: {"id":"chatcmpl-...","object":"chat.completion.chunk","choices":[{"delta":{"content":"!"}}]}

data: [DONE]
```

---

## 5. Provider Routing Examples

Swarm routes transparently based on model prefix or explicit config:

### Groq (Ultra-fast Cloud Llama / Qwen)
```bash
curl -s -X POST http://127.0.0.1:8088/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "groq/llama-3.3-70b-versatile",
    "messages": [{"role": "user", "content": "Write quick Fibonacci in Rust."}]
  }' | jq .
```

### Google Gemini (Multimodal / Large Context)
```bash
curl -s -X POST http://127.0.0.1:8088/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemini-2.0-flash",
    "messages": [{"role": "user", "content": "Summarize quantum computing."}]
  }' | jq .
```

### OpenAI (GPT-4o)
```bash
curl -s -X POST http://127.0.0.1:8088/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "messages": [{"role": "user", "content": "Hello GPT-4o!"}]
  }' | jq .
```

### Local Ollama / vLLM (Zero-data-egress on port 11434)
```bash
curl -s -X POST http://127.0.0.1:8088/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "custom/llama3.2:latest",
    "messages": [{"role": "user", "content": "Tell me a joke."}]
  }' | jq .
```

---

## 6. Security & Bearer Authentication

When inbound authentication is enabled on the server, include the bearer token header in your requests:

```bash
curl -s -X POST http://127.0.0.1:8088/v1/chat/completions \
  -H "Authorization: Bearer <YOUR_GATEWAY_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-oss-20b",
    "messages": [{"role": "user", "content": "Secure request."}]
  }' | jq .
```

*Note: `/health` and `/v1/health` remain accessible without authentication for Kubernetes liveness/readiness probes.*

---

## 7. Automated Test Script (`run_examples.sh`)

Use the included test runner to test all endpoints in sequence:

```bash
# Standard automated run
./examples_calls/run_examples.sh

# With SSE streaming verification
./examples_calls/run_examples.sh --stream

# Auto-launch the gateway if not currently running
./examples_calls/run_examples.sh --launch

# Test with a specific model or port
./examples_calls/run_examples.sh --model "groq/llama-3.3-70b-versatile" --port 8088
```
