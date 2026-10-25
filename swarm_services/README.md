# ⚙️ Swarm Services: Core Infrastructure for Agent Collaboration ⚙️

> **Swarm Services** provides the essential infrastructure services that enable intelligent agents within the Swarm framework to collaborate, share information, evaluate performance, and discover each other. By centralizing these services, `swarm_services` facilitates a robust, scalable, and interconnected multi-agent ecosystem.

## **Why Swarm Services?**

As a multi-agent system, Swarm relies on several critical backend services to function effectively. `swarm_services` brings these core functionalities together to:

*   **Enable Seamless Collaboration:** Provide mechanisms for agents to interact and share data efficiently.
*   **Enhance System Intelligence:** Offer services for evaluating agent performance and managing collective memory.
*   **Promote Scalability:** Decouple common services from individual agents, allowing for independent scaling and management.
*   **Simplify Agent Development:** Agents can rely on these established services rather than implementing complex cross-cutting concerns themselves.

## **Included Crates & Their Purpose**

`swarm_services` is a workspace containing several infrastructure-focused crates:

*   **`agent_service_adapters`**:
    *   **Purpose:** Contains client-side implementations that allow individual agents to interact with the core Swarm services (discovery, memory, evaluation). These adapters abstract the underlying communication protocols (e.g., HTTP) and provide an ergonomic interface for agents.
    *   **Key Features:** Provides client structs and methods for calling the various Swarm services.
*   **`agent_discovery_service`**:
    *   **Purpose:** An HTTP service responsible for enabling agents to register themselves within the Swarm ecosystem and discover other available agents based on their capabilities, domains, or IDs.
    *   **Key Features:** Agent registration, agent lookup, and service advertisement.
*   **`agent_memory_service`**:
    *   **Purpose:** A dedicated service for managing and sharing conversational history, contextual information, and long-term memory among agents. This allows agents to maintain continuity and leverage past interactions.
    *   **Key Features:** Stores and retrieves agent memory, potentially using embeddings for similarity search.
*   **`agent_evaluation_service`**:
    *   **Purpose:** Implements an LLM-as-a-Judge system to critically assess the performance and outcomes of individual agent actions and complete workflow executions. This service provides essential feedback for iterative improvement and self-correction within the Swarm.
    *   **Key Features:** Receives execution results, uses an LLM to evaluate outcomes, and returns evaluation scores.

## **Usage**

To use any of the crates within `swarm_services` or to integrate with these services from your agents, you would typically add `agent_service_adapters` as a dependency in your agent's `Cargo.toml`:

```toml
[dependencies]
swarm_services_agent_service_adapters = { path = "../swarm_services/agent_service_adapters" }
# For running the services themselves, you would build and launch them directly.
```

(Note: You might need to adjust the path based on your project structure if you're using these as local path dependencies.)

## **Contributing**

We welcome contributions to `swarm_services`! By contributing to these foundational services, you help strengthen the entire Swarm ecosystem. Please refer to the main Swarm project's contribution guidelines for more details.
