use alloy_sol_types::sol;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

sol! {
    /// The public values encoded as a struct that can be easily deserialized inside Solidity.
    struct PublicValuesStruct {
        uint32 n;
        uint32 a;
        uint32 b;
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OrderData {
    pub wallet_address: [u8; 20],
    pub token_in: [u8; 20],
    pub token_out: [u8; 20],
    pub amount_in: u64,
    pub min_amount_out: u64,
    pub target_price: u64,
    pub deadline: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MarketConditions {
    pub current_price: u64,
    pub block_timestamp: u64,
}

/// Compute the n'th fibonacci number (wrapping around on overflows), using normal Rust code.
pub fn fibonacci(n: u32) -> (u32, u32) {
    let mut a = 0u32;
    let mut b = 1u32;
    for _ in 0..n {
        let c = a.wrapping_add(b);
        a = b;
        b = c;
    }
    (a, b)
}

pub fn validate_order(
    order: &OrderData,
    market: &MarketConditions,
    expected_hash: &[u8; 32],
) -> bool {
    if market.block_timestamp > order.deadline {
        return false;
    }

    if market.current_price < order.target_price {
        return false;
    }

    let computed_hash = hash_order(order);
    computed_hash == *expected_hash
}

pub fn hash_order(order: &OrderData) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(&order.wallet_address);
    hasher.update(&order.token_in);
    hasher.update(&order.token_out);
    hasher.update(&order.amount_in.to_le_bytes());
    hasher.update(&order.min_amount_out.to_le_bytes());
    hasher.update(&order.target_price.to_le_bytes());
    hasher.update(&order.deadline.to_le_bytes());
    hasher.finalize().into()
}

pub fn verify_merkle_proof(
    address: &[u8; 20],
    balance: u64,
    siblings: &Vec<[u8; 32]>,
    indices: &Vec<u8>,
    expected_root: &[u8; 32],
) -> bool {
    if siblings.len() != indices.len() {
        return false;
    }

    // Compute leaf: H(address || balance)
    let mut hasher = Sha256::new();
    hasher.update(address);
    hasher.update(&balance.to_le_bytes());
    let result = hasher.finalize();
    let mut current_hash = [0u8; 32];
    current_hash.copy_from_slice(&result);

    // Traverse up the tree
    for (i, sibling) in siblings.iter().enumerate() {
        let mut hasher = Sha256::new();
        if indices[i] == 0 {
            hasher.update(sibling);
            hasher.update(&current_hash);
        } else {
            hasher.update(&current_hash);
            hasher.update(sibling);
        }
        current_hash = hasher.finalize().into();
    }

    &current_hash == expected_root
}
