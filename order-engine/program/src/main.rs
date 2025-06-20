#![no_main]
sp1_zkvm::entrypoint!(main);

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OrderData {
    pub wallet_address: [u8; 20],
    pub token_in: [u8; 20],
    pub token_out: [u8; 20],
    pub amount_in: u64,
    pub min_amount_out: u64,
    pub target_price: u64,
    pub deadline: u64,
    pub permit2_nonce: u64,
    pub permit2_deadline: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MarketConditions {
    pub current_price: u64,
    pub block_timestamp: u64,
}

pub fn main() {
    let order_data = sp1_zkvm::io::read::<OrderData>();
    let market_conditions = sp1_zkvm::io::read::<MarketConditions>();
    let expected_order_hash = sp1_zkvm::io::read::<[u8; 32]>();
    let merkle_root = sp1_zkvm::io::read::<[u8; 32]>(); // public
    let merkle_siblings = sp1_zkvm::io::read::<Vec<[u8; 32]>>(); // private
    let merkle_indices = sp1_zkvm::io::read::<Vec<u8>>(); // 0 = left, 1 = right
    let user_balance = sp1_zkvm::io::read::<u64>(); // balance committed privately

    let order_valid = validate_order(&order_data, &market_conditions, &expected_order_hash);
    let merkle_valid = verify_merkle_proof(
        &order_data.wallet_address,
        user_balance,
        &merkle_siblings,
        &merkle_indices,
        &merkle_root,
    );
    let balance_sufficient = user_balance >= order_data.amount_in;

    let final_validity = order_valid && merkle_valid && balance_sufficient;
    sp1_zkvm::io::commit(&final_validity);
}

fn validate_order(order: &OrderData, market: &MarketConditions, expected_hash: &[u8; 32]) -> bool {
    if market.block_timestamp > order.deadline {
        return false;
    }
    if market.block_timestamp > order.permit2_deadline {
        return false;
    }
    if market.current_price < order.target_price {
        return false;
    }

    let computed_hash = hash_order(order);
    computed_hash == *expected_hash
}

fn hash_order(order: &OrderData) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(&order.wallet_address);
    hasher.update(&order.token_in);
    hasher.update(&order.token_out);
    hasher.update(&order.amount_in.to_le_bytes());
    hasher.update(&order.min_amount_out.to_le_bytes());
    hasher.update(&order.target_price.to_le_bytes());
    hasher.update(&order.deadline.to_le_bytes());
    hasher.update(&order.permit2_nonce.to_le_bytes());
    hasher.update(&order.permit2_deadline.to_le_bytes());
    hasher.finalize().into()
}

fn verify_merkle_proof(
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
