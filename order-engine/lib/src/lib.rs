use alloy_sol_types::sol;
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
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MarketConditions {
    pub current_price: u64,
    pub block_timestamp: u64,
}

/// Nullifier-based order commitment
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OrderCommitment {
    pub order_data: OrderData,
    pub nullifier: [u8; 32], // Private nullifier secret
    pub balance: u64,        // User's private balance
}

/// Public nullifier data for preventing double-spending
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NullifierData {
    pub nullifier_hash: [u8; 32],  // Public nullifier hash (prevents replay)
    pub commitment_hash: [u8; 32], // Public commitment hash (goes in Merkle tree)
}

/// Validates order conditions including market and time constraints
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

/// Computes deterministic hash of order data
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

/// Computes nullifier hash from private nullifier (prevents double-spending)
pub fn compute_nullifier_hash(nullifier: &[u8; 32]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(b"NULLIFIER_HASH"); // Domain separation
    hasher.update(nullifier);
    hasher.finalize().into()
}

/// Computes commitment hash from order, nullifier, and balance (goes in Merkle tree)
pub fn compute_commitment_hash(order: &OrderData, nullifier: &[u8; 32], balance: u64) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(b"COMMITMENT_HASH"); // Domain separation

    // Hash order data
    let order_hash = hash_order(order);
    hasher.update(&order_hash);

    // Hash nullifier
    hasher.update(nullifier);

    // Hash balance
    hasher.update(&balance.to_le_bytes());

    hasher.finalize().into()
}

/// Verifies that the user knows the nullifier for their commitment
pub fn verify_nullifier_knowledge(
    commitment: &OrderCommitment,
    expected_commitment_hash: &[u8; 32],
    expected_nullifier_hash: &[u8; 32],
) -> bool {
    // Verify commitment hash matches
    let computed_commitment = compute_commitment_hash(
        &commitment.order_data,
        &commitment.nullifier,
        commitment.balance,
    );

    if computed_commitment != *expected_commitment_hash {
        return false;
    }

    // Verify nullifier hash matches
    let computed_nullifier_hash = compute_nullifier_hash(&commitment.nullifier);
    if computed_nullifier_hash != *expected_nullifier_hash {
        return false;
    }

    true
}

/// Verifies Merkle proof for commitment hash (not individual balance)
pub fn verify_commitment_merkle_proof(
    commitment_hash: &[u8; 32],
    siblings: &Vec<[u8; 32]>,
    indices: &Vec<u8>,
    expected_root: &[u8; 32],
) -> bool {
    if siblings.len() != indices.len() {
        return false;
    }

    let mut current_hash = *commitment_hash;

    // Traverse up the tree
    for (i, sibling) in siblings.iter().enumerate() {
        let mut hasher = Sha256::new();
        hasher.update(b"MERKLE_NODE"); // Domain separation

        if indices[i] == 0 {
            // Current node is left child
            hasher.update(&current_hash);
            hasher.update(sibling);
        } else {
            // Current node is right child
            hasher.update(sibling);
            hasher.update(&current_hash);
        }
        current_hash = hasher.finalize().into();
    }

    &current_hash == expected_root
}

/// Legacy balance verification for backward compatibility
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
    hasher.update(b"BALANCE_LEAF"); // Domain separation
    hasher.update(address);
    hasher.update(&balance.to_le_bytes());
    let result = hasher.finalize();
    let mut current_hash = [0u8; 32];
    current_hash.copy_from_slice(&result);

    // Traverse up the tree
    for (i, sibling) in siblings.iter().enumerate() {
        let mut hasher = Sha256::new();
        hasher.update(b"MERKLE_NODE"); // Domain separation

        if indices[i] == 0 {
            hasher.update(&current_hash);
            hasher.update(sibling);
        } else {
            hasher.update(sibling);
            hasher.update(&current_hash);
        }
        current_hash = hasher.finalize().into();
    }

    &current_hash == expected_root
}

/// Verifies that an order can be executed with nullifier protection
pub fn verify_nullifier_order(
    commitment: &OrderCommitment,
    market: &MarketConditions,
    commitment_hash: &[u8; 32],
    nullifier_hash: &[u8; 32],
) -> bool {
    // 1. Verify nullifier knowledge
    if !verify_nullifier_knowledge(commitment, commitment_hash, nullifier_hash) {
        return false;
    }

    // 2. Verify sufficient balance
    if commitment.balance < commitment.order_data.amount_in {
        return false;
    }

    // 3. Verify order conditions
    let order_hash = hash_order(&commitment.order_data);
    if !validate_order(&commitment.order_data, market, &order_hash) {
        return false;
    }

    true
}

/// Generates a deterministic nullifier from user secret and order context
pub fn generate_order_nullifier(
    user_secret: &[u8; 32],
    order_context: &[u8; 32], // Could be order hash or trading session ID
) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(b"ORDER_NULLIFIER"); // Domain separation
    hasher.update(user_secret);
    hasher.update(order_context);
    hasher.finalize().into()
}

/// Creates order commitment for Merkle tree inclusion
pub fn create_order_commitment(
    order: &OrderData,
    user_secret: &[u8; 32],
    balance: u64,
    order_context: &[u8; 32],
) -> (OrderCommitment, NullifierData) {
    // Generate nullifier
    let nullifier = generate_order_nullifier(user_secret, order_context);

    // Create commitment
    let commitment = OrderCommitment {
        order_data: order.clone(),
        nullifier,
        balance,
    };

    // Generate public nullifier data
    let nullifier_data = NullifierData {
        nullifier_hash: compute_nullifier_hash(&nullifier),
        commitment_hash: compute_commitment_hash(order, &nullifier, balance),
    };

    (commitment, nullifier_data)
}
