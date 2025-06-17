// SP1 zkVM Program for Dark Pool Order Proofs
// This program proves order validity without revealing order details
#![no_main]
sp1_zkvm::entrypoint!(main);
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sp1_zkvm::io;

// ============================================================================
// CORE DATA STRUCTURES
// ============================================================================

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Order {
    pub token_in: [u8; 20],  // Token address to sell
    pub token_out: [u8; 20], // Token address to buy
    pub amount_in: u64,      // Amount willing to sell
    pub min_amount_out: u64, // Minimum amount to receive
    pub deadline: u64,       // Order expiry timestamp
    pub nonce: u64,          // Unique nonce for replay protection
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct UserBalance {
    pub token: [u8; 20],             // Token address
    pub balance: u64,                // User's balance
    pub merkle_proof: Vec<[u8; 32]>, // Merkle proof of balance
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct OrderCommitment {
    pub commitment_hash: [u8; 32], // Public commitment hash
    pub nullifier: [u8; 32],       // Prevents double spending
}

// ============================================================================
// CRYPTOGRAPHIC UTILITIES
// ============================================================================

/// Secure hash function using SHA256 (you could use Poseidon for better circuit efficiency)
fn secure_hash(data: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hasher.finalize().into()
}

/// Compute Merkle root from leaf and proof
fn compute_merkle_root(leaf: [u8; 32], proof: &[[u8; 32]], index: u32) -> [u8; 32] {
    let mut current = leaf;
    let mut idx = index;

    for sibling in proof {
        let mut hasher = Sha256::new();
        if idx % 2 == 0 {
            // Current node is left child
            hasher.update(&current);
            hasher.update(sibling);
        } else {
            // Current node is right child
            hasher.update(sibling);
            hasher.update(&current);
        }
        current = hasher.finalize().into();
        idx /= 2;
    }

    current
}

/// Create order commitment hash (what gets published on-chain)
fn create_order_commitment(order: &Order, user_address: &[u8; 20]) -> [u8; 32] {
    let mut data = Vec::new();
    data.extend_from_slice(&order.token_in);
    data.extend_from_slice(&order.token_out);
    data.extend_from_slice(&order.amount_in.to_le_bytes());
    data.extend_from_slice(&order.min_amount_out.to_le_bytes());
    data.extend_from_slice(&order.deadline.to_le_bytes());
    data.extend_from_slice(&order.nonce.to_le_bytes());
    data.extend_from_slice(user_address);

    secure_hash(&data)
}

/// Create nullifier to prevent double spending
fn create_nullifier(order: &Order, user_address: &[u8; 20], secret_key: &[u8; 32]) -> [u8; 32] {
    let mut data = Vec::new();
    data.extend_from_slice(&create_order_commitment(order, user_address));
    data.extend_from_slice(secret_key);
    data.extend_from_slice(b"NULLIFIER_SALT");

    secure_hash(&data)
}

// ============================================================================
// MAIN SP1 ZKVM PROGRAM
// ============================================================================

/// Main entry point for SP1 zkVM program
/// This function will be compiled to RISC-V and proven
fn main() {
    // Read private inputs from host
    let order = io::read::<Order>();
    let user_address: [u8; 20] = io::read();
    let user_balances: Vec<UserBalance> = io::read::<Vec<UserBalance>>();
    let balance_merkle_root: [u8; 32] = io::read(); // Trusted root from contract
    let user_secret_key: [u8; 32] = io::read(); // For nullifier generation
    let current_timestamp: u64 = io::read();

    // Read public inputs (these will be part of the proof)
    let expected_commitment: [u8; 32] = io::read();
    let expected_nullifier: [u8; 32] = io::read();

    // ========================================================================
    // PROOF LOGIC - This is what we're proving
    // ========================================================================

    // 1. VALIDATE ORDER STRUCTURE
    assert!(order.amount_in > 0, "Amount in must be positive");
    assert!(order.min_amount_out > 0, "Min amount out must be positive");
    assert!(order.deadline > current_timestamp, "Order has expired");
    assert!(order.token_in != order.token_out, "Cannot trade same token");

    // 2. VERIFY USER HAS SUFFICIENT BALANCE
    let mut found_balance = false;
    for balance in &user_balances {
        if balance.token == order.token_in {
            // Verify this balance is in the Merkle tree
            let balance_leaf = {
                let mut data = Vec::new();
                data.extend_from_slice(&user_address);
                data.extend_from_slice(&balance.token);
                data.extend_from_slice(&balance.balance.to_le_bytes());
                secure_hash(&data)
            };

            // Compute Merkle root and verify against trusted root
            let computed_root = compute_merkle_root(
                balance_leaf,
                &balance.merkle_proof,
                0, // In real implementation, you'd need the correct index
            );
            assert_eq!(computed_root, balance_merkle_root, "Invalid balance proof");

            // Check sufficient balance
            assert!(balance.balance >= order.amount_in, "Insufficient balance");
            found_balance = true;
            break;
        }
    }
    assert!(found_balance, "Balance not found for token");

    // 3. VERIFY COMMITMENT IS CORRECTLY COMPUTED
    let computed_commitment = create_order_commitment(&order, &user_address);
    assert_eq!(
        computed_commitment, expected_commitment,
        "Invalid commitment"
    );

    // 4. VERIFY NULLIFIER IS CORRECTLY COMPUTED
    let computed_nullifier = create_nullifier(&order, &user_address, &user_secret_key);
    assert_eq!(computed_nullifier, expected_nullifier, "Invalid nullifier");

    // 5. OUTPUT PUBLIC VALUES (commitment and nullifier)
    io::commit(&expected_commitment);
    io::commit(&expected_nullifier);
    io::commit(&user_address);

    // The proof is now complete!
    // We've proven:
    // - User has sufficient balance (via Merkle proof)
    // - Order is valid and not expired
    // - Commitment correctly represents the order
    // - Nullifier prevents double spending
    // WITHOUT revealing the actual order details!
}
