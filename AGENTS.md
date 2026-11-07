# Component Agent Instructions

<!-- BEGIN GENERATED:component (meta/bin/build, do not edit inside) -->
## Swarm Gateway (Tier 1 Cognitive Proxy) (`COMP-swarm-gateway`)

Stateless LLM ingress proxy routing completions, managing token budgets, and formatting responses without business state.

Inspect any ID with `./meta/bin/ctx show <ID>`. Before editing, run `./meta/bin/ctx impact <files>`.

### Governing Invariants (must remain true)
- `INV-001` [P0, enforced by dependency_rule]: Cognitive Ingress Isolation & Zero Runtime LLM Bypass

### Forbidden Responsibilities & Shortcuts
- Holding standing enterprise credentials or master database connections
- Direct execution of side-effecting tools or downstream API calls
- Bypassing token budget checks or rate limits on /v1/responses

### Canonical Implementation Patterns (Golden Exemplars)
- `PAT-005`: Multi-Turn Cognitive Planning Loop over /v1/responses

### Hidden Couplings (breaks at a distance)
- `COUP-001`: Mesh Loopback Port Topology & Service Route Table

### Fast Verification Commands
- `make -C swarm_gateway test`
- `cargo check --manifest-path swarm_gateway/swarm/Cargo.toml --all-targets`
- `cargo clippy --manifest-path swarm_gateway/swarm/Cargo.toml --all-targets -- -D warnings`
<!-- END GENERATED:component -->
