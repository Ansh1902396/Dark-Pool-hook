use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::Json,
    routing::{get, post},
    Router,
};
use serde::{Deserialize, Serialize};
use std::{collections::HashMap, sync::Arc};
use tokio::sync::RwLock;
use tower::ServiceBuilder;
use tower_http::{cors::CorsLayer, trace::TraceLayer, timeout::TimeoutLayer};
use uuid::Uuid;
use std::time::Duration;

use sp1_sdk::{include_elf, ProverClient, SP1ProofWithPublicValues, SP1Stdin};
use fibonacci_lib::{
    create_order_commitment, hash_order, verify_commitment_merkle_proof,
    MarketConditions, OrderData, OrderCommitment, NullifierData,
};

/// The ELF for the SP1 program
const FIBONACCI_ELF: &[u8] = include_elf!("fibonacci-program");

/// API Request/Response Types
#[derive(Debug, Serialize, Deserialize)]
pub struct ProofGenerationRequest {
    /// Order details
    pub order: OrderData,
    /// User's private secret (32 bytes hex)
    pub user_secret: String,
    /// User's current balance
    pub balance: u64,
    /// Market conditions at time of proof generation
    pub market_conditions: MarketConditions,
    /// Merkle tree data
    pub merkle_proof: MerkleProofData,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct MerkleProofData {
    /// Merkle root (32 bytes hex)
    pub root: String,
    /// Sibling hashes for proof path (32 bytes hex each)
    pub siblings: Vec<String>,
    /// Path indices (0 = left, 1 = right)
    pub indices: Vec<u8>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ProofResponse {
    /// Unique proof ID
    pub proof_id: String,
    /// Whether proof generation was successful
    pub success: bool,
    /// Proof data (base64 encoded)
    pub proof_data: Option<String>,
    /// Public values from the proof
    pub public_values: Option<PublicValues>,
    /// Error message if generation failed
    pub error: Option<String>,
    /// Generation time in milliseconds
    pub generation_time_ms: u64,
    /// Cycle count
    pub cycles: Option<u64>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PublicValues {
    /// Whether the order is valid
    pub is_valid: bool,
    /// Nullifier hash for replay prevention
    pub nullifier_hash: String,
    /// Wallet address
    pub wallet_address: String,
    /// Order amount in
    pub amount_in: u64,
    /// Minimum amount out
    pub min_amount_out: u64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ProofVerificationRequest {
    /// Proof data (base64 encoded)
    pub proof_data: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ProofVerificationResponse {
    /// Whether verification was successful
    pub valid: bool,
    /// Public values extracted from proof
    pub public_values: Option<PublicValues>,
    /// Error message if verification failed
    pub error: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct HealthResponse {
    pub status: String,
    pub timestamp: u64,
    pub version: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct StatsResponse {
    pub total_proofs_generated: u64,
    pub total_proofs_verified: u64,
    pub average_generation_time_ms: f64,
    pub uptime_seconds: u64,
}

#[derive(Debug)]
pub struct ApiError {
    pub code: StatusCode,
    pub message: String,
}

impl axum::response::IntoResponse for ApiError {
    fn into_response(self) -> axum::response::Response {
        let body = serde_json::json!({
            "error": self.message,
            "code": self.code.as_u16()
        });
        (self.code, Json(body)).into_response()
    }
}

/// Application state
#[derive(Clone)]
pub struct AppState {
    pub prover_client: Arc<ProverClient>,
    pub stats: Arc<RwLock<Stats>>,
    pub start_time: std::time::Instant,
}

#[derive(Debug, Default)]
pub struct Stats {
    pub total_proofs_generated: u64,
    pub total_proofs_verified: u64,
    pub total_generation_time_ms: u64,
}

impl Stats {
    pub fn average_generation_time_ms(&self) -> f64 {
        if self.total_proofs_generated == 0 {
            0.0
        } else {
            self.total_generation_time_ms as f64 / self.total_proofs_generated as f64
        }
    }
}

/// Utility functions
fn hex_to_bytes32(hex: &str) -> Result<[u8; 32], ApiError> {
    let hex = hex.strip_prefix("0x").unwrap_or(hex);
    if hex.len() != 64 {
        return Err(ApiError {
            code: StatusCode::BAD_REQUEST,
            message: "Invalid hex length, expected 64 characters".to_string(),
        });
    }
    
    let mut bytes = [0u8; 32];
    hex::decode_to_slice(hex, &mut bytes).map_err(|_| ApiError {
        code: StatusCode::BAD_REQUEST,
        message: "Invalid hex encoding".to_string(),
    })?;
    
    Ok(bytes)
}

fn hex_to_bytes20(hex: &str) -> Result<[u8; 20], ApiError> {
    let hex = hex.strip_prefix("0x").unwrap_or(hex);
    if hex.len() != 40 {
        return Err(ApiError {
            code: StatusCode::BAD_REQUEST,
            message: "Invalid address length, expected 40 characters".to_string(),
        });
    }
    
    let mut bytes = [0u8; 20];
    hex::decode_to_slice(hex, &mut bytes).map_err(|_| ApiError {
        code: StatusCode::BAD_REQUEST,
        message: "Invalid address encoding".to_string(),
    })?;
    
    Ok(bytes)
}

fn bytes_to_hex(bytes: &[u8]) -> String {
    format!("0x{}", hex::encode(bytes))
}

/// API Handlers
pub async fn generate_proof(
    State(state): State<AppState>,
    Json(request): Json<ProofGenerationRequest>,
) -> Result<Json<ProofResponse>, ApiError> {
    let start_time = std::time::Instant::now();
    let proof_id = Uuid::new_v4().to_string();
    
    // Setup SP1 inputs
    let mut stdin = SP1Stdin::new();
    
    // Public inputs
    stdin.write(&request.market_conditions);
    stdin.write(&merkle_root);
    stdin.write(&nullifier_data.nullifier_hash);
    
    // Private inputs
    stdin.write(&request.order);
    stdin.write(&commitment.nullifier);
    stdin.write(&request.balance);
    stdin.write(&merkle_siblings);
    stdin.write(&request.merkle_proof.indices);

    // Generate proof
    match generate_sp1_proof(&state.prover_client, &stdin).await {
        Ok((proof, cycles)) => {
            let generation_time = start_time.elapsed().as_millis() as u64;
            
            // Extract public values
            let mut proof_clone = proof.clone();
            let is_valid = proof_clone.public_values.read::<bool>();
            let nullifier_hash = proof_clone.public_values.read::<[u8; 32]>();
            let wallet_address = proof_clone.public_values.read::<[u8; 20]>();
            let amount_in = proof_clone.public_values.read::<u64>();
            let min_amount_out = proof_clone.public_values.read::<u64>();

            let public_values = PublicValues {
                is_valid,
                nullifier_hash: bytes_to_hex(&nullifier_hash),
                wallet_address: bytes_to_hex(&wallet_address),
                amount_in,
                min_amount_out,
            };

            // Update stats
            let mut stats = state.stats.write().await;
            stats.total_proofs_generated += 1;
            stats.total_generation_time_ms += generation_time;
            drop(stats);

            tracing::info!(
                "Proof generated successfully: proof_id={}, time={}ms, cycles={}", 
                proof_id, generation_time, cycles
            );

            Ok(Json(ProofResponse {
                proof_id,
                success: true,
                proof_data: Some(base64::encode(proof.bytes())),
                public_values: Some(public_values),
                error: None,
                generation_time_ms: generation_time,
                cycles: Some(cycles),
            }))
        }
        Err(e) => {
            let generation_time = start_time.elapsed().as_millis() as u64;
            
            tracing::error!(
                "Proof generation failed: proof_id={}, error={}, time={}ms", 
                proof_id, e, generation_time
            );

            Ok(Json(ProofResponse {
                proof_id,
                success: false,
                proof_data: None,
                public_values: None,
                error: Some(e.to_string()),
                generation_time_ms: generation_time,
                cycles: None,
            }))
        }
    }
}



pub async fn health() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "healthy".to_string(),
        timestamp: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs(),
        version: env!("CARGO_PKG_VERSION").to_string(),
    })
}

pub async fn stats(State(state): State<AppState>) -> Json<StatsResponse> {
    let stats = state.stats.read().await;
    let uptime = state.start_time.elapsed().as_secs();
    
    Json(StatsResponse {
        total_proofs_generated: stats.total_proofs_generated,
        total_proofs_verified: stats.total_proofs_verified,
        average_generation_time_ms: stats.average_generation_time_ms(),
        uptime_seconds: uptime,
    })
}

/// SP1 proof operations
async fn generate_sp1_proof(
    client: &ProverClient,
    stdin: &SP1Stdin,
) -> Result<(SP1ProofWithPublicValues, u64), Box<dyn std::error::Error + Send + Sync>> {
    // Setup proving and verification keys
    let (pk, vk) = client.setup(FIBONACCI_ELF);
    
    // Generate proof
    let proof = client.prove(&pk, stdin).run()?;
    
    // Get cycle count
    let (_, report) = client.execute(FIBONACCI_ELF, stdin).run()?;
    let cycles = report.total_instruction_count();
    
    
    Ok((proof, cycles))
}

async fn verify_sp1_proof(
    client: &ProverClient,
    proof_bytes: &[u8],
) -> Result<PublicValues, Box<dyn std::error::Error + Send + Sync>> {
    // Load proof from bytes
    let mut proof = SP1ProofWithPublicValues::from_bytes(proof_bytes)?;
    
    // Setup verification key
    let (_, vk) = client.setup(FIBONACCI_ELF);
    
    // Verify proof
    client.verify(&proof, &vk)?;
    
    // Extract public values
    let is_valid = proof.public_values.read::<bool>();
    let nullifier_hash = proof.public_values.read::<[u8; 32]>();
    let wallet_address = proof.public_values.read::<[u8; 20]>();
    let amount_in = proof.public_values.read::<u64>();
    let min_amount_out = proof.public_values.read::<u64>();

    Ok(PublicValues {
        is_valid,
        nullifier_hash: bytes_to_hex(&nullifier_hash),
        wallet_address: bytes_to_hex(&wallet_address),
        amount_in,
        min_amount_out,
    })
}

/// Application setup
pub fn create_app() -> Router {
    let prover_client = Arc::new(ProverClient::from_env());
    let stats = Arc::new(RwLock::new(Stats::default()));
    let start_time = std::time::Instant::now();

    let state = AppState {
        prover_client,
        stats,
        start_time,
    };

    Router::new()
        .route("/health", get(health))
        .route("/stats", get(stats))
        .route("/proof/generate", post(generate_proof))
        .route("/proof/verify", post(verify_proof))
        .with_state(state)
        .layer(
            ServiceBuilder::new()
                .layer(TraceLayer::new_for_http())
                .layer(TimeoutLayer::new(Duration::from_secs(300))) // 5 minute timeout
                .layer(CorsLayer::permissive())
        )
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .init();

    // Create application
    let app = create_app();

    // Start server
    let port = std::env::var("PORT").unwrap_or_else(|_| "3000".to_string());
    let addr = format!("0.0.0.0:{}", port);
    
    tracing::info!("Starting Dark Pool API server on {}", addr);
    
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use tower::ServiceExt;

    #[tokio::test]
    async fn test_health_endpoint() {
        let app = create_app();
        
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/health")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn test_stats_endpoint() {
        let app = create_app();
        
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/stats")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
    }

    #[test]
    fn test_hex_conversion() {
        let hex = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        let bytes = hex_to_bytes32(hex).unwrap();
        let converted_back = bytes_to_hex(&bytes);
        assert_eq!(hex.to_lowercase(), converted_back.to_lowercase());
    }
}