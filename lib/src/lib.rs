use alloy_sol_types::sol;
use serde::{Deserialize, Serialize};

sol! {
    /// The public values encoded as a struct that can be easily deserialized inside Solidity.
    struct PublicValuesStruct {
        uint32 n;
        uint32 a;
        uint32 b;
    }
}

#[derive(Serialize, Deserialize)]
pub struct Order {
    pub side:      u8,        // 0 = buy , 1 = sell
    pub token_in:  [u8; 20],
    pub token_out: [u8; 20],
    pub qty:       u128,      // amount of token_in
    pub limit_px:  u128,      // price * 1e18
    pub deadline:  u64,
    pub nonce:     u32,
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