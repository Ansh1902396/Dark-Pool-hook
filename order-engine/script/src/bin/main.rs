//! An end-to-end example of using the SP1 SDK to generate a proof of a program that can be executed
//! or have a core proof generated.
//!
//! You can run this script using the following command:
//! ```shell
//! RUST_LOG=info cargo run --release -- --execute
//! ```
//! or
//! ```shell
//! RUST_LOG=info cargo run --release -- --prove
//! ```

use alloy_sol_types::SolType;
use clap::Parser;
use fibonacci_lib::{
    hash_order, validate_order, verify_merkle_proof, MarketConditions, OrderData,
    PublicValuesStruct,
};
use sha2::{Digest, Sha256};
use std::error::Error;

use sp1_sdk::{include_elf, ProverClient, SP1Stdin};

/// The ELF (executable and linkable format) file for the Succinct RISC-V zkVM.
pub const FIBONACCI_ELF: &[u8] = include_elf!("fibonacci-program");

/// The arguments for the command.
#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    #[arg(long)]
    execute: bool,

    #[arg(long)]
    prove: bool,
}

pub struct MerkleTreeBuilder {
    leaves: Vec<[u8; 32]>,
}

impl MerkleTreeBuilder {
    pub fn new() -> Self {
        Self { leaves: Vec::new() }
    }

    pub fn add_balance_leaf(&mut self, wallet: [u8; 20], balance: u64) {
        let leaf = self.compute_balance_leaf(wallet, balance);
        self.leaves.push(leaf);
    }

    fn compute_balance_leaf(&self, wallet: [u8; 20], balance: u64) -> [u8; 32] {
        // This matches your library's leaf computation: H(address || balance)
        let mut hasher = Sha256::new();
        hasher.update(&wallet);
        hasher.update(&balance.to_le_bytes());
        hasher.finalize().into()
    }

    pub fn build_tree(&self) -> ([u8; 32], Vec<Vec<[u8; 32]>>) {
        if self.leaves.is_empty() {
            return ([0u8; 32], vec![]);
        }

        let mut levels = vec![self.leaves.clone()];
        let mut current_level = self.leaves.clone();

        while current_level.len() > 1 {
            let mut next_level = Vec::new();

            for i in (0..current_level.len()).step_by(2) {
                let left = current_level[i];
                let right = if i + 1 < current_level.len() {
                    current_level[i + 1]
                } else {
                    left // Duplicate if odd number of nodes
                };

                let parent = self.hash_pair(left, right);
                next_level.push(parent);
            }

            levels.push(next_level.clone());
            current_level = next_level;
        }

        let root = current_level[0];
        (root, levels)
    }

    pub fn generate_proof(
        &self,
        wallet: [u8; 20],
        balance: u64,
    ) -> Result<([u8; 32], Vec<[u8; 32]>, Vec<u8>), Box<dyn Error>> {
        let target_leaf = self.compute_balance_leaf(wallet, balance);
        let leaf_index = self
            .leaves
            .iter()
            .position(|&leaf| leaf == target_leaf)
            .ok_or("Leaf not found in tree")?;

        let (root, levels) = self.build_tree();
        let mut siblings = Vec::new();
        let mut indices = Vec::new();
        let mut current_index = leaf_index;

        // Generate siblings and indices for each level (except root)
        for level in 0..(levels.len() - 1) {
            let sibling_index = if current_index % 2 == 0 {
                current_index + 1
            } else {
                current_index - 1
            };

            if sibling_index < levels[level].len() {
                siblings.push(levels[level][sibling_index]);
            } else {
                siblings.push(levels[level][current_index]); // Duplicate for odd case
            }

            // Index indicates whether the current node is left (0) or right (1)
            indices.push((current_index % 2) as u8);
            current_index /= 2;
        }

        Ok((root, siblings, indices))
    }

    fn hash_pair(&self, left: [u8; 32], right: [u8; 32]) -> [u8; 32] {
        let mut hasher = Sha256::new();
        hasher.update(&left);
        hasher.update(&right);
        hasher.finalize().into()
    }
}

fn main() {
    // Setup the logger.
    sp1_sdk::utils::setup_logger();
    dotenv::dotenv().ok();

    let alice_wallet = [1u8; 20];
    let eth_token = [2u8; 20];
    let usdc_token = [3u8; 20];
    let user_balance = 1000000000000000000u64; // 1 ETH in wei

    let order = OrderData {
        wallet_address: alice_wallet,
        token_in: eth_token,
        token_out: usdc_token,
        amount_in: 5000000000000000000u64, // 5 ETH in wei
        min_amount_out: 10000000000u64,    // 10,000 USDC (6 decimals)
        target_price: 2000000000u64,       // $2,000 per ETH
        deadline: 1735689600u64,           // Future timestamp
    };

    let market_conditions = MarketConditions {
        current_price: 2050000000u64, // Current price: $2,050 (favorable for Alice)
        block_timestamp: 1735600000u64,
    };
    // Parse the command line arguments.
    let args = Args::parse();

    if args.execute == args.prove {
        eprintln!("Error: You must specify either --execute or --prove");
        std::process::exit(1);
    }

    // Setup the prover client.
    let client = ProverClient::from_env();

    let expected_order_hash = hash_order(&order);

    let mut merkle_tree_builder = MerkleTreeBuilder::new();
    merkle_tree_builder.add_balance_leaf(alice_wallet, user_balance);
    let (merkle_root, merkle_siblings, merkle_indices) = merkle_tree_builder
        .generate_proof(alice_wallet, user_balance)
        .unwrap();

    // Setup the inputs.
    let mut stdin = SP1Stdin::new();
    stdin.write(&order);
    stdin.write(&market_conditions);
    stdin.write(&expected_order_hash);
    stdin.write(&merkle_root);
    stdin.write(&merkle_siblings);
    stdin.write(&merkle_indices);
    stdin.write(&user_balance);

    if args.execute {
        // Execute the program
        let (output, report) = client.execute(FIBONACCI_ELF, &stdin).run().unwrap();
        println!("Program executed successfully.");

        // Read the output.
        let order_valid = validate_order(&order, &market_conditions, &expected_order_hash);
        let merkle_valid = verify_merkle_proof(
            &order.wallet_address,
            user_balance,
            &merkle_siblings,
            &merkle_indices,
            &merkle_root,
        );

        println!("Order valid: {}", order_valid);
        println!("Merkle valid: {}", merkle_valid);
        println!("User balance: {}", user_balance);
        println!("Merkle root: {}", hex::encode(merkle_root));
        println!("Merkle siblings: {:?}", merkle_siblings);
        println!("Merkle indices: {:?}", merkle_indices);

        // Record the number of cycles executed.
        println!("Number of cycles: {}", report.total_instruction_count());
    } else {
        // Setup the program for proving.
        let (pk, vk) = client.setup(FIBONACCI_ELF);

        // Generate the proof
        let proof = client
            .prove(&pk, &stdin)
            .run()
            .expect("failed to generate proof");

        println!("Successfully generated proof!");

        // Verify the proof.
        client.verify(&proof, &vk).expect("failed to verify proof");
        println!("Proof: {:?}", proof);
        println!("Successfully verified proof!");
    }
}
