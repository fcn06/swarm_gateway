use dashmap::DashMap;

use agent_models::memory::memory_models::{FactItem, LogEntry, LogPayload, MemoryQuery};
use axum::{
    extract::{Path, Query, State},
    response::Json,
    routing::{get, post},
    Router,
};
use serde::Deserialize;
use std::sync::Arc;
use tracing::info;

/// Application state holding configurations
/// The outcome could be converted into a ConversationContext
#[derive(Clone)] // AppState needs to be Clone to be used as Axum state
pub struct AppState {
    pub db_memory: Arc<DashMap<String, Vec<LogEntry>>>,
    pub db_facts: Arc<DashMap<String, FactItem>>,
}

/// Memory_server
pub struct MemoryServer {
    pub uri: String,
    pub app: Router,
}

#[derive(Debug, Deserialize)]
pub struct ConversationParams {
    pub limit: Option<usize>,
}

impl MemoryServer {
    pub async fn new(uri: String) -> anyhow::Result<Self> {
        let db_memory: DashMap<String, Vec<LogEntry>> = DashMap::new();
        let db_facts: DashMap<String, FactItem> = DashMap::new();

        // Create AppState
        let app_state = AppState {
            db_memory: Arc::new(db_memory),
            db_facts: Arc::new(db_facts),
        };

        let app = Router::new()
            .route("/", get(root))
            .route("/log", post(log_message))
            .route("/conversation/{conversation_id}", get(get_conversation))
            .route("/facts", post(store_fact))
            .route("/facts/recall", post(recall_facts))
            .with_state(app_state);

        Ok(Self { uri, app })
    }

    /// Start the HTTP server
    pub async fn start_http(&self) -> anyhow::Result<()> {
        // Run our app with hyper
        let listener = tokio::net::TcpListener::bind(self.uri.clone()).await?;
        println!("Memory Server started on {}", self.uri);
        axum::serve(listener, self.app.clone()).await?;

        Ok(())
    }
}

async fn root() -> &'static str {
    "Hello, Swarm Memory Service!"
}

async fn log_message(
    State(state): State<AppState>, // Extract the AppState
    Json(payload): Json<LogPayload>,
) -> Json<Vec<LogEntry>> {
    
    info!("Received log_message for conversation : {:?}", payload.conversation_id);

    let db_memory = state.db_memory.to_owned();

    let new_entry = LogEntry {
        role: payload.role,
        content: payload.content,
        agent_id: payload.agent_id,
    };

    let mut conversation = db_memory
        .entry(payload.conversation_id)
        .or_insert_with(Vec::new);
    conversation.push(new_entry);

    Json(conversation.clone())
}

async fn get_conversation(
    State(state): State<AppState>, // Extract the AppState
    Path(conversation_id): Path<String>,
    Query(params): Query<ConversationParams>,
) -> Json<Option<Vec<LogEntry>>> {
    
    info!("Received get_conversation request for id: {}, limit: {:?}", conversation_id, params.limit);

    let db_memory = state.db_memory.to_owned();

    let conversation = db_memory.get(&conversation_id).map(|entry| {
        let entries = entry.clone();
        if let Some(limit) = params.limit {
            if entries.len() > limit {
                entries[entries.len() - limit..].to_vec()
            } else {
                entries
            }
        } else {
            entries
        }
    });

    Json(conversation)
}

async fn store_fact(
    State(state): State<AppState>,
    Json(fact): Json<FactItem>,
) -> Json<bool> {
    info!("Received store_fact request for key: {}", fact.key);
    state.db_facts.insert(fact.key.clone(), fact);
    Json(true)
}

async fn recall_facts(
    State(state): State<AppState>,
    Json(query): Json<MemoryQuery>,
) -> Json<Vec<FactItem>> {
    info!("Received recall_facts request for query: {}", query.query);
    let q_lower = query.query.to_lowercase();
    let limit = query.limit.unwrap_or(5);

    let results: Vec<FactItem> = state
        .db_facts
        .iter()
        .filter(|entry| {
            let fact = entry.value();
            if let Some(ref cat) = query.category {
                if fact.category.as_ref() != Some(cat) {
                    return false;
                }
            }
            if query.query.is_empty() {
                return true;
            }
            fact.key.to_lowercase().contains(&q_lower)
                || fact.content.to_lowercase().contains(&q_lower)
        })
        .map(|entry| entry.value().clone())
        .take(limit)
        .collect();

    Json(results)
}
