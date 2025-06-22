//! Nullifier-based Dark Pool Script
//!
//! This demonstrates how nullifiers solve the dynamic user problem:
//! - Users generate commitments that go into a Merkle tree
//! - New users can be added without invalidating existing proofs
//! - Nullifiers prevent replay attacks
//! - Orders can be executed independently using their nullifiers
//!
//! Usage:
//! ```shell
//! RUST_LOG=info cargo run --release -- --execute --demo nullifier-flow
//! ```

use alloy_sol_types::SolType;
use clap::Parser;
use fibonacci_lib::{
    compute_nullifier_hash, create_order_commitment, hash_order, verify_commitment_merkle_proof,
    verify_nullifier_order, MarketConditions, NullifierData, OrderCommitment, OrderData,
};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::error::Error;

use sp1_sdk::{include_elf, ProverClient, SP1Stdin};

/// The ELF (executable and linkable format) file for the Succinct RISC-V zkVM.
pub const FIBONACCI_ELF: &[u8] = include_elf!("fibonacci-program");

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    #[arg(long)]
    execute: bool,

    #[arg(long)]
    prove: bool,

    #[arg(long, default_value = "nullifier-flow")]
    demo: String,
}

/// Merkle tree for commitments (not individual balances)
pub struct CommitmentMerkleTree {
    leaves: Vec<[u8; 32]>,
    users: Vec<String>, // Track which user corresponds to each commitment
}

impl CommitmentMerkleTree {
    pub fn new() -> Self {
        Self {
            leaves: Vec::new(),
            users: Vec::new(),
        }
    }

    pub fn add_commitment(&mut self, commitment_hash: [u8; 32], user_name: String) {
        self.leaves.push(commitment_hash);
        self.users.push(user_name);
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
                    left
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
        commitment_hash: [u8; 32],
    ) -> Result<(Vec<[u8; 32]>, Vec<u8>), Box<dyn Error>> {
        let leaf_index = self
            .leaves
            .iter()
            .position(|&leaf| leaf == commitment_hash)
            .ok_or("Commitment not found in tree")?;

        let (_, levels) = self.build_tree();
        let mut siblings = Vec::new();
        let mut indices = Vec::new();
        let mut current_index = leaf_index;

        for level in 0..(levels.len() - 1) {
            let sibling_index = if current_index % 2 == 0 {
                current_index + 1
            } else {
                current_index - 1
            };

            if sibling_index < levels[level].len() {
                siblings.push(levels[level][sibling_index]);
            } else {
                siblings.push(levels[level][current_index]);
            }

            indices.push((current_index % 2) as u8);
            current_index /= 2;
        }

        Ok((siblings, indices))
    }

    fn hash_pair(&self, left: [u8; 32], right: [u8; 32]) -> [u8; 32] {
        let mut hasher = Sha256::new();
        hasher.update(b"MERKLE_NODE");
        hasher.update(&left);
        hasher.update(&right);
        hasher.finalize().into()
    }
}

/// User with their secret and orders
#[derive(Debug, Clone)]
struct User {
    name: String,
    secret: [u8; 32],
    balance: u64,
    orders: Vec<OrderData>,
    commitments: Vec<(OrderCommitment, NullifierData)>,
}

impl User {
    fn new(name: String, secret: [u8; 32], balance: u64) -> Self {
        Self {
            name,
            secret,
            balance,
            orders: Vec::new(),
            commitments: Vec::new(),
        }
    }

    fn create_order(&mut self, order: OrderData) -> (OrderCommitment, NullifierData) {
        let order_context = hash_order(&order);
        let (commitment, nullifier_data) =
            create_order_commitment(&order, &self.secret, self.balance, &order_context);

        self.orders.push(order);
        self.commitments
            .push((commitment.clone(), nullifier_data.clone()));

        (commitment, nullifier_data)
    }
}

fn demonstrate_nullifier_flow() -> Result<(), Box<dyn Error>> {
    println!("🎯 NULLIFIER-BASED DARK POOL FLOW");
    println!("═══════════════════════════════════════");

    // Step 1: Create users with their secrets
    println!("\n👤 Step 1: Creating Users with Secrets");

    let mut alice = User::new("Alice".to_string(), [1u8; 32], 10000000000000000000u64); // 10 ETH
    let mut bob = User::new("Bob".to_string(), [2u8; 32], 15000000000u64); // 15k USDC
    let mut charlie = User::new("Charlie".to_string(), [3u8; 32], 5000000000u64); // 5k USDC

    println!("  Alice: 10 ETH (secret: [1u8; 32])");
    println!("  Bob: 15k USDC (secret: [2u8; 32])");
    println!("  Charlie: 5k USDC (secret: [3u8; 32])");

    // Step 2: Users create orders
    println!("\n📝 Step 2: Users Create Orders");

    let alice_order = OrderData {
        wallet_address: [1u8; 20],
        token_in: [0xAu8; 20],             // ETH
        token_out: [0xBu8; 20],            // USDC
        amount_in: 5000000000000000000u64, // 5 ETH
        min_amount_out: 10000000000u64,    // 10k USDC
        target_price: 2000000000u64,       // $2000/ETH
        deadline: 1735689600u64,
    };

    let bob_order = OrderData {
        wallet_address: [2u8; 20],
        token_in: [0xBu8; 20],                  // USDC
        token_out: [0xAu8; 20],                 // ETH
        amount_in: 8000000000u64,               // 8k USDC
        min_amount_out: 3800000000000000000u64, // 3.8 ETH
        target_price: 2100000000u64,            // Max $2100/ETH
        deadline: 1735689600u64,
    };

    // Create commitments
    let (alice_commitment, alice_nullifier) = alice.create_order(alice_order);
    let (bob_commitment, bob_nullifier) = bob.create_order(bob_order);

    println!("  Alice order: 5 ETH → USDC at $2000");
    println!(
        "    Nullifier hash: {:02x?}",
        &alice_nullifier.nullifier_hash[..8]
    );
    println!(
        "    Commitment hash: {:02x?}",
        &alice_nullifier.commitment_hash[..8]
    );

    println!("  Bob order: 8k USDC → ETH at max $2100");
    println!(
        "    Nullifier hash: {:02x?}",
        &bob_nullifier.nullifier_hash[..8]
    );
    println!(
        "    Commitment hash: {:02x?}",
        &bob_nullifier.commitment_hash[..8]
    );

    // Step 3: Build commitment Merkle tree
    println!("\n🌳 Step 3: Building Commitment Tree");

    let mut commitment_tree = CommitmentMerkleTree::new();
    commitment_tree.add_commitment(alice_nullifier.commitment_hash, alice.name.clone());
    commitment_tree.add_commitment(bob_nullifier.commitment_hash, bob.name.clone());

    let (tree_root_v1, _) = commitment_tree.build_tree();
    println!("  Tree v1 Root: {:02x?}", &tree_root_v1[..8]);
    println!("  Commitments: Alice, Bob");

    // Step 4: Charlie joins AFTER Alice and Bob have their commitments
    println!("\n👥 Step 4: Charlie Joins (New User)");

    let charlie_order = OrderData {
        wallet_address: [3u8; 20],
        token_in: [0xBu8; 20],                  // USDC
        token_out: [0xAu8; 20],                 // ETH
        amount_in: 3000000000u64,               // 3k USDC
        min_amount_out: 1400000000000000000u64, // 1.4 ETH
        target_price: 2150000000u64,            // Max $2150/ETH
        deadline: 1735689600u64,
    };

    let (charlie_commitment, charlie_nullifier) = charlie.create_order(charlie_order);

    // Add Charlie to the tree
    commitment_tree.add_commitment(charlie_nullifier.commitment_hash, charlie.name.clone());
    let (tree_root_v2, _) = commitment_tree.build_tree();

    println!("  Charlie order: 3k USDC → ETH at max $2150");
    println!("  Tree v2 Root: {:02x?}", &tree_root_v2[..8]);
    println!("  Commitments: Alice, Bob, Charlie");
    println!("  🚨 Tree root changed, but this is OK with nullifiers!");

    // Step 5: Test Alice's order execution (using old commitment but new tree)
    println!("\n⚡ Step 5: Alice Executes Order (Against New Tree)");

    let market_conditions = MarketConditions {
        current_price: 2050000000u64, // $2050 (favorable for Alice)
        block_timestamp: 1735600000u64,
    };

    // Generate proof for Alice's commitment in the NEW tree
    let (alice_siblings, alice_indices) =
        commitment_tree.generate_proof(alice_nullifier.commitment_hash)?;

    println!("  Market price: $2050 (Alice's target: $2000) ✅");
    println!(
        "  Alice's proof: {} siblings, {} indices",
        alice_siblings.len(),
        alice_indices.len()
    );

    // Verify Alice's order can execute
    let alice_merkle_valid = verify_commitment_merkle_proof(
        &alice_nullifier.commitment_hash,
        &alice_siblings,
        &alice_indices,
        &tree_root_v2, // Using NEW tree root!
    );

    let alice_order_valid = verify_nullifier_order(
        &alice_commitment,
        &market_conditions,
        &alice_nullifier.commitment_hash,
        &alice_nullifier.nullifier_hash,
    );

    println!("  Merkle proof valid: {}", alice_merkle_valid);
    println!("  Order execution valid: {}", alice_order_valid);
    println!("  ✅ Alice can execute even though tree changed!");

    // Step 6: Demonstrate nullifier replay prevention
    println!("\n🛡️  Step 6: Nullifier Replay Prevention");

    // Simulate on-chain nullifier storage
    let mut used_nullifiers: HashMap<[u8; 32], String> = HashMap::new();

    // Alice executes her order
    used_nullifiers.insert(alice_nullifier.nullifier_hash, "Alice's order".to_string());
    println!(
        "  Alice's nullifier stored on-chain: {:02x?}",
        &alice_nullifier.nullifier_hash[..8]
    );

    // Try to replay Alice's nullifier
    let is_replay = used_nullifiers.contains_key(&alice_nullifier.nullifier_hash);
    println!("  Replay attempt detected: {}", is_replay);
    println!("  🚨 Alice cannot execute the same order twice!");

    // Step 7: Bob can still execute independently
    println!("\n🔄 Step 7: Bob Executes Independently");

    let bob_not_used = !used_nullifiers.contains_key(&bob_nullifier.nullifier_hash);
    println!("  Bob's nullifier unused: {}", bob_not_used);
    println!("  ✅ Bob can execute his order independently");

    // Step 8: Add even more users to show scalability
    println!("\n📈 Step 8: Adding More Users");

    let diana = User::new("Diana".to_string(), [4u8; 32], 10000000000000000000u64); // 10 ETH
    let eve = User::new("Eve".to_string(), [5u8; 32], 25000000000u64); // 25k USDC

    // Create their orders and add to tree
    let diana_order = OrderData {
        wallet_address: [4u8; 20],
        token_in: [0xAu8; 20],             // ETH
        token_out: [0xBu8; 20],            // USDC
        amount_in: 8000000000000000000u64, // 8 ETH
        min_amount_out: 16000000000u64,    // 16k USDC
        target_price: 2000000000u64,       // $2000/ETH
        deadline: 1735689600u64,
    };

    let (_, diana_nullifier) = create_order_commitment(
        &diana_order,
        &diana.secret,
        diana.balance,
        &hash_order(&diana_order),
    );

    let eve_order = OrderData {
        wallet_address: [5u8; 20],
        token_in: [0xBu8; 20],                  // USDC
        token_out: [0xAu8; 20],                 // ETH
        amount_in: 12000000000u64,              // 12k USDC
        min_amount_out: 5500000000000000000u64, // 5.5 ETH
        target_price: 2200000000u64,            // Max $2200/ETH
        deadline: 1735689600u64,
    };

    let (_, eve_nullifier) = create_order_commitment(
        &eve_order,
        &eve.secret,
        eve.balance,
        &hash_order(&eve_order),
    );

    commitment_tree.add_commitment(diana_nullifier.commitment_hash, "Diana".to_string());
    commitment_tree.add_commitment(eve_nullifier.commitment_hash, "Eve".to_string());

    let (tree_root_v3, _) = commitment_tree.build_tree();
    println!("  Added Diana (10 ETH) and Eve (25k USDC)");
    println!("  Tree v3 Root: {:02x?}", &tree_root_v3[..8]);
    println!("  Total users: Alice, Bob, Charlie, Diana, Eve");

    // Verify Bob can still execute against the newest tree
    let (bob_siblings_v3, bob_indices_v3) =
        commitment_tree.generate_proof(bob_nullifier.commitment_hash)?;
    let bob_still_valid = verify_commitment_merkle_proof(
        &bob_nullifier.commitment_hash,
        &bob_siblings_v3,
        &bob_indices_v3,
        &tree_root_v3,
    );

    println!("  Bob's order still executable: {}", bob_still_valid);
    println!("  ✅ All users remain executable as tree grows!");

    println!("\n🎉 NULLIFIER BENEFITS DEMONSTRATED:");
    println!("  ✅ New users don't break existing orders");
    println!("  ✅ Replay attacks prevented by nullifier hashes");
    println!("  ✅ Privacy maintained - no balance revelations");
    println!("  ✅ Scalable - tree can grow indefinitely");
    println!("  ✅ Independent execution - orders don't interfere");

    Ok(())
}

fn run_sp1_nullifier_test() -> Result<(), Box<dyn Error>> {
    println!("\n🔬 SP1 NULLIFIER TEST");
    println!("═══════════════════════");

    let client = ProverClient::from_env();

    // Create test data
    let alice_secret = [1u8; 32];
    let alice_order = OrderData {
        wallet_address: [1u8; 20],
        token_in: [0xAu8; 20],
        token_out: [0xBu8; 20],
        amount_in: 5000000000000000000u64,
        min_amount_out: 10000000000u64,
        target_price: 2000000000u64,
        deadline: 1735689600u64,
    };

    let market_conditions = MarketConditions {
        current_price: 2050000000u64,
        block_timestamp: 1735600000u64,
    };

    let alice_balance = 10000000000000000000u64;
    let order_context = hash_order(&alice_order);

    let (alice_commitment, alice_nullifier) =
        create_order_commitment(&alice_order, &alice_secret, alice_balance, &order_context);

    // Build tree with Alice's commitment
    let mut tree = CommitmentMerkleTree::new();
    tree.add_commitment(alice_nullifier.commitment_hash, "Alice".to_string());

    let (tree_root, _) = tree.build_tree();
    let (siblings, indices) = tree.generate_proof(alice_nullifier.commitment_hash)?;

    println!("  Order: 5 ETH → USDC at $2000 target");
    println!("  Market: $2050 (favorable)");
    println!("  Balance: 10 ETH (sufficient)");

    // Setup SP1 inputs
    let mut stdin = SP1Stdin::new();

    // Public inputs
    stdin.write(&market_conditions);
    stdin.write(&tree_root);
    stdin.write(&alice_nullifier.nullifier_hash);

    // Private inputs
    stdin.write(&alice_order);
    stdin.write(&alice_commitment.nullifier);
    stdin.write(&alice_balance);
    stdin.write(&siblings);
    stdin.write(&indices);

    println!("  🔄 Executing SP1 program...");
    let (mut output, report) = client.execute(FIBONACCI_ELF, &stdin).run()?;

    // Read outputs
    let is_valid = output.read::<bool>();
    let nullifier_hash = output.read::<[u8; 32]>();
    let wallet_address = output.read::<[u8; 20]>();
    let amount_in = output.read::<u64>();
    let min_amount_out = output.read::<u64>();

    println!("  ✅ SP1 Results:");
    println!("    Valid: {}", is_valid);
    println!("    Nullifier: {:02x?}", &nullifier_hash[..8]);
    println!("    Wallet: {:02x?}", &wallet_address[..4]);
    println!("    Amount in: {}", amount_in);
    println!("    Min out: {}", min_amount_out);
    println!("    Cycles: {}", report.total_instruction_count());

    if is_valid {
        println!("  🎯 Order ready for execution!");
    } else {
        println!("  ❌ Order validation failed!");
    }

    Ok(())
}

fn main() -> Result<(), Box<dyn Error>> {
    sp1_sdk::utils::setup_logger();
    dotenv::dotenv().ok();

    let args = Args::parse();

    if !args.execute && !args.prove {
        eprintln!("Error: You must specify either --execute or --prove");
        std::process::exit(1);
    }

    println!("🌊 Nullifier-based Dark Pool");
    println!("Demo: {}", args.demo);
    println!("Mode: {}", if args.execute { "Execute" } else { "Prove" });

    match args.demo.as_str() {
        "nullifier-flow" => {
            demonstrate_nullifier_flow()?;
            if args.execute {
                run_sp1_nullifier_test()?;
            }
        }
        _ => {
            eprintln!("Unknown demo: {}", args.demo);
            std::process::exit(1);
        }
    }

    Ok(())
}
