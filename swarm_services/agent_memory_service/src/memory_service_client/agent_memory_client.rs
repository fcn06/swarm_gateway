use reqwest::Client;
use anyhow::Result;

//use crate::models::{LogEntry, LogPayload, Role};
use agent_models::memory::memory_models::{FactItem, LogEntry, LogPayload, MemoryQuery, Role};


#[derive(Debug, Clone)]
pub struct AgentMemoryServiceClient {
    memory_service_url: String,
    client: Client,
}

impl AgentMemoryServiceClient {
    pub fn new(memory_service_url: String) -> Self {
        AgentMemoryServiceClient {
            memory_service_url,
            client: Client::new(),
        }
    }

    pub async fn log(&self, conversation_id: String, role: Role, content: String, agent_id: Option<String>) -> Result<Vec<LogEntry>> {
        let url = format!("{}/log", self.memory_service_url);
        let payload = LogPayload {
            conversation_id,
            role,
            content,
            agent_id,
        };

        let response = self.client.post(&url)
            .json(&payload)
            .send()
            .await?;

        Ok(response.json::<Vec<LogEntry>>().await?)
    }

    pub async fn get_conversation(&self, conversation_id: &str) -> Result<Option<Vec<LogEntry>>> {
        self.get_conversation_with_limit(conversation_id, None).await
    }

    pub async fn get_conversation_with_limit(&self, conversation_id: &str, limit: Option<usize>) -> Result<Option<Vec<LogEntry>>> {
        let mut url = format!("{}/conversation/{}", self.memory_service_url, conversation_id);
        if let Some(l) = limit {
            url = format!("{}?limit={}", url, l);
        }
        let response = self.client.get(&url)
            .send()
            .await?;

        Ok(response.json::<Option<Vec<LogEntry>>>().await?)
    }

    pub async fn store_fact(&self, fact: &FactItem) -> Result<bool> {
        let url = format!("{}/facts", self.memory_service_url);
        let response = self.client.post(&url)
            .json(fact)
            .send()
            .await?;

        Ok(response.json::<bool>().await?)
    }

    pub async fn recall_facts(&self, query: &MemoryQuery) -> Result<Vec<FactItem>> {
        let url = format!("{}/facts/recall", self.memory_service_url);
        let response = self.client.post(&url)
            .json(query)
            .send()
            .await?;

        Ok(response.json::<Vec<FactItem>>().await?)
    }
}