use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    routing::post,
    Json, Router,
};
use base64::{engine::general_purpose, Engine as _};
use hex::FromHex;
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use sp1_sdk::{
    include_elf, utils, ProverClient, SP1ProofWithPublicValues, SP1Stdin, SP1ProvingKey, SP1VerifyingKey,EnvProver
};
extern crate std;

use std::{net::SocketAddr, sync::Arc};

/// ──────────────────────────────────────────────────────────────
///  ⚙️  SP1 guest ELF compiled from your nullifier validation program
///     (rename accordingly).
/// ──────────────────────────────────────────────────────────────
pub const ELF: &[u8] = include_elf!("fibonacci-program");

/// ────────────────  Types that already live in your guest crate  ────────────────
/// Bring them in so we can build identical Rust structs on the host.
use fibonacci_lib::{MarketConditions, OrderData};

/// ────────────────  Shared app-level state  ────────────────
#[derive(Clone)]
struct AppState {
    client: Arc<EnvProver>,
    pk: Arc<SP1ProvingKey>,
    vk: Arc<SP1VerifyingKey>,
}

static STATE: Lazy<AppState> = Lazy::new(|| {
    utils::setup_logger();
    let client = Arc::new(ProverClient::from_env());
    let (pk, vk) = client.setup(ELF);
    AppState {
        client,
        pk: Arc::new(pk),
        vk: Arc::new(vk),
    }
});

/// ────────────────  Helper: decode 0x… hex into fixed array  ────────────────
fn hex_to_array<const N: usize>(s: &str) -> anyhow::Result<[u8; N]> {
    let s = s.strip_prefix("0x").unwrap_or(s);
    let bytes = hex::decode(s)
        .map_err(|e| anyhow::anyhow!("hex decode error: {e}"))?;
    
    let len = bytes.len();
    bytes.try_into()
        .map_err(|_| anyhow::anyhow!("Expected {} bytes, got {}", N, len))
}

/// ────────────────  Incoming payload  ────────────────
#[derive(Deserialize)]
struct ProveRequest {
    // Public
    market: MarketJson,
    tree_root: String,        // 32-byte hex
    nullifier_hash: String,   // 32-byte hex
    // Private
    order: OrderJson,
    commitment_nullifier: String, // 32-byte hex
    balance: u64,
    siblings: Vec<String>,    // Vec<32-byte hex>
    indices: Vec<u8>,
}

#[derive(Deserialize)]
struct MarketJson {
    current_price: u64,
    block_timestamp: u64,
}

#[derive(Deserialize)]
struct OrderJson {
    wallet_address: String,   // 20-byte hex
    token_in: String,         // 20-byte hex
    token_out: String,        // 20-byte hex
    amount_in: u64,
    min_amount_out: u64,
    target_price: u64,
    deadline: u64,
}

/// ────────────────  Outgoing response  ────────────────
#[derive(Serialize)]
struct ProveResponse {
    cycles: u64,
    // echoed guest outputs
    valid: bool,
    nullifier_hash: String,
    wallet_address: String,
    amount_in: u64,
    min_amount_out: u64,
    // proof
    proof_b64: String,
    verified: bool,
}

fn to_500<E: std::fmt::Display>(err: E) -> (StatusCode, String) {
    (StatusCode::INTERNAL_SERVER_ERROR, err.to_string())
}

/// ────────────────  Route handler  ────────────────
async fn prove_handler(
    State(state): State<AppState>,
    Json(req): Json<ProveRequest>,
) -> Result<impl IntoResponse, (StatusCode, String)> {
    // ─── Convert JSON → Rust structs expected by guest ───
    let market = MarketConditions {
        current_price: req.market.current_price,
        block_timestamp: req.market.block_timestamp,
    };

    let tree_root = hex_to_array::<32>(&req.tree_root).map_err(to_500)?;
    let nullifier_hash_arr = hex_to_array::<32>(&req.nullifier_hash).map_err(to_500)?;

    let order = OrderData {
        wallet_address: hex_to_array::<20>(&req.order.wallet_address).map_err(to_500)?,
        token_in: hex_to_array::<20>(&req.order.token_in).map_err(to_500)?,
        token_out: hex_to_array::<20>(&req.order.token_out).map_err(to_500)?,
        amount_in: req.order.amount_in,
        min_amount_out: req.order.min_amount_out,
        target_price: req.order.target_price,
        deadline: req.order.deadline,
    };

    let commitment_nullifier = hex_to_array::<32>(&req.commitment_nullifier).map_err(to_500)?;

    let siblings: Vec<[u8; 32]> = req
        .siblings
        .iter()
        .map(|h| hex_to_array::<32>(h))
        .collect::<Result<_, _>>().map_err(to_500)?;

    // ─── Build stdin exactly like in your script ───
    let mut stdin = SP1Stdin::new();
    // public
    stdin.write(&market);
    stdin.write(&tree_root);
    stdin.write(&nullifier_hash_arr);
    // private
    stdin.write(&order);
    stdin.write(&commitment_nullifier);
    stdin.write(&req.balance);
    stdin.write(&siblings);
    stdin.write(&req.indices);

    // ─── Execute for cycle count (optional) ───
    let (_, exec_report) = state.client.execute(ELF, &stdin).run().map_err(to_500)?;
    let cycles = exec_report.total_instruction_count();

    // ─── Prove & verify (unchanged) ───
    let mut proof = state
        .client
        .prove(&state.pk, &stdin)
        .plonk()
        .run()
        .map_err(to_500)?;

    let verified = state.client.verify(&proof, &state.vk).is_ok();

    // ─── Read guest-committed outputs ───
    let valid          = proof.public_values.read::<bool>();
    let out_nullifier  = proof.public_values.read::<[u8; 32]>();
    let out_wallet     = proof.public_values.read::<[u8; 20]>();
    let amount_in      = proof.public_values.read::<u64>();
    let min_amount_out = proof.public_values.read::<u64>();

    // ─── Serialize proof to b64 ───
    let proof_bytes = serde_json::to_vec(&proof).map_err(to_500)?;          // Vec<u8>
    let proof_b64   = general_purpose::URL_SAFE_NO_PAD.encode(&proof_bytes);

    // ─── Return JSON ───
    Ok(Json(ProveResponse {
        cycles,
        valid,
        nullifier_hash: format!("0x{}", hex::encode(out_nullifier)),
        wallet_address: format!("0x{}", hex::encode(out_wallet)),
        amount_in,
        min_amount_out,
        proof_b64,
        verified,
    }))
}

/// ────────────────  Tokio main ────────────────
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let app = Router::new()
        .route("/prove", post(prove_handler))
        .with_state(STATE.clone());

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8080").await?;
    println!("dark-pool server listening on {}", listener.local_addr()?);
    axum::serve(listener, app).await?;
    Ok(())
}