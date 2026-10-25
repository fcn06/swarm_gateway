# Swarm Gateway Kickstart Suite (`kickstart/`)

Self-contained kickstart environment for launching and testing the **Swarm Model Gateway Server**:

```text
swarm/kickstart/
└── gateway_kickstart/                     # Standalone Model Gateway Server
    ├── 01_launch_gateway.sh
    ├── 02_test_chat_completions.sh
    ├── 03_test_open_responses.sh
    ├── 04_terminate_gateway.sh
    ├── README.md
    └── config_files/
        ├── gateway_config.toml
        ├── chat_completions_request.json
        ├── open_responses_request.json
        └── open_responses_followup_request.json
```

---

## 🌐 Launching & Testing the Gateway Server

The standalone gateway server (`swarm_server`) supports OpenAI-compatible `/v1/chat/completions` and stateful multi-turn Open Responses `/v1/responses`.

```bash
cd swarm

# 1. Start the Gateway Server (configured via config_files/gateway_config.toml):
./kickstart/gateway_kickstart/01_launch_gateway.sh

# 2. Test OpenAI-compatible Chat Completions:
./kickstart/gateway_kickstart/02_test_chat_completions.sh "What is the weather like in Boston ?"

# 3. Test Stateful Multi-Turn Open Responses:
./kickstart/gateway_kickstart/03_test_open_responses.sh

# 4. Stop the Gateway Server:
./kickstart/gateway_kickstart/04_terminate_gateway.sh
```
