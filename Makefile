.PHONY: all check test build launch stop test-chat test-responses clean

all: check test

check:
	@echo "==> Checking swarm_commons..."
	@cd swarm_commons && cargo check
	@echo "==> Checking swarm..."
	@cd swarm && cargo check
	@echo "==> Checking swarm_services..."
	@cd swarm_services && cargo check

test:
	@echo "==> Running Gateway Test Suite..."
	@cd swarm_commons && cargo test -p agent_core --test gateway_tests

bench:
	@echo "==> Running Gateway In-Process Benchmarks (Release)..."
	@cd swarm_commons && cargo test --release -p agent_core --test gateway_tests -- --nocapture

token:
	@bash ./examples_calls/mint_test_token.sh

build:
	@echo "==> Building Standalone Swarm Gateway (Release)..."
	@cd swarm_commons && cargo build --release -p agent_core --bin swarm_gateway

launch:
	@echo "==> Launching Swarm Gateway Server..."
	@cd swarm && ./kickstart/gateway_kickstart/01_launch_gateway.sh

stop:
	@echo "==> Stopping Swarm Gateway Server..."
	@cd swarm && ./kickstart/gateway_kickstart/04_terminate_gateway.sh

test-chat:
	@echo "==> Testing /v1/chat/completions..."
	@cd swarm && ./kickstart/gateway_kickstart/02_test_chat_completions.sh $(QUERY)

test-responses:
	@echo "==> Testing /v1/responses (Multi-Turn Stateful)..."
	@cd swarm && ./kickstart/gateway_kickstart/03_test_open_responses.sh

clean:
	@echo "==> Cleaning build artifacts..."
	@cd swarm_commons && cargo clean
	@cd swarm && cargo clean
	@cd swarm_services && cargo clean
