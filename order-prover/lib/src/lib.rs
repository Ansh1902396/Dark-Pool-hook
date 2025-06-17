use core::hash;

use alloy_sol_types::sol;
use alloy_sol_types::sol_data::Address;
use poseidon_rs::Poseidon;

sol! {
    /// The public values encoded as a struct that can be easily deserialized inside Solidity.
    struct PublicValuesStruct {
        uint32 n;
        uint32 a;
        uint32 b;
    }
}
pub struct Order {
    ///ERC-20 the trader will pay
    pub side: u8,

    pub token_in: Address,

    ///ERC-20 the trader will receive
    pub token_out: Address,

    ///Amount of token_in the trader will pay
    pub amount_in: u128,

    ///Amount of token_out the trader will receive
    pub amount_out: u128,

    ///Limit price for the order
    pub limit_px: u128,
}

pub fn build_wallet_tree(
    leaves: &[(Address, u128)],
    prove_token: Address,
    prove_index: u32,
) -> ([u8; 32], [[u8; 32]; 32], u128) {
    unimplemented!();
}
