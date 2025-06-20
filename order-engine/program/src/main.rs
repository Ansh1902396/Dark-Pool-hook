#![no_main]
sp1_zkvm::entrypoint!(main);

use fibonacci_lib::{validate_order, verify_merkle_proof, MarketConditions, OrderData};

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
