#![no_main]
sp1_zkvm::entrypoint!(main);

use fibonacci_lib::{
    compute_commitment_hash, compute_nullifier_hash, validate_order,
    verify_commitment_merkle_proof, verify_nullifier_order, MarketConditions, OrderCommitment,
    OrderData,
};

pub fn main() {
    // === PUBLIC INPUTS ===
    let market_conditions = sp1_zkvm::io::read::<MarketConditions>();
    let merkle_root = sp1_zkvm::io::read::<[u8; 32]>(); // Public Merkle root
    let expected_nullifier_hash = sp1_zkvm::io::read::<[u8; 32]>(); // Public nullifier hash

    // === PRIVATE INPUTS ===
    let order_data = sp1_zkvm::io::read::<OrderData>();
    let nullifier = sp1_zkvm::io::read::<[u8; 32]>(); // Private nullifier secret
    let user_balance = sp1_zkvm::io::read::<u64>(); // Private balance
    let merkle_siblings = sp1_zkvm::io::read::<Vec<[u8; 32]>>(); // Private Merkle proof
    let merkle_indices = sp1_zkvm::io::read::<Vec<u8>>(); // Private Merkle path

    // === NULLIFIER VERIFICATION ===

    // 1. Verify nullifier hash matches expected (prevents replay attacks)
    let computed_nullifier_hash = compute_nullifier_hash(&nullifier);
    let nullifier_hash_valid = computed_nullifier_hash == expected_nullifier_hash;

    // 2. Compute commitment hash from private inputs
    let commitment_hash = compute_commitment_hash(&order_data, &nullifier, user_balance);

    // 3. Create commitment struct for verification
    let commitment = OrderCommitment {
        order_data: order_data.clone(),
        nullifier,
        balance: user_balance,
    };

    // === MERKLE TREE VERIFICATION ===

    // 4. Verify commitment is in the Merkle tree
    let merkle_valid = verify_commitment_merkle_proof(
        &commitment_hash,
        &merkle_siblings,
        &merkle_indices,
        &merkle_root,
    );

    // === ORDER VALIDATION ===

    // 5. Verify order execution conditions
    let order_executable = verify_nullifier_order(
        &commitment,
        &market_conditions,
        &commitment_hash,
        &expected_nullifier_hash,
    );

    // === FINAL VERIFICATION ===

    let final_validity = nullifier_hash_valid && merkle_valid && order_executable;

    // === PUBLIC OUTPUTS ===

    // Commit the validity result
    sp1_zkvm::io::commit(&final_validity);

    // Commit the nullifier hash (to be stored on-chain for replay prevention)
    sp1_zkvm::io::commit(&computed_nullifier_hash);

    // Commit the wallet address (for order execution)
    sp1_zkvm::io::commit(&order_data.wallet_address);

    // Commit order amounts (for swap execution)
    sp1_zkvm::io::commit(&order_data.amount_in);
    sp1_zkvm::io::commit(&order_data.min_amount_out);
}
