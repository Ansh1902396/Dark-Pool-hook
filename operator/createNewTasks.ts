import { ethers } from "ethers";
import * as dotenv from "dotenv";
import {
  createPublicClient,
  createWalletClient,
  encodeAbiParameters,
  getContract,
  http,
  parseAbiParameters,
  toHex,
  parseEther,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { anvil, holesky } from "viem/chains";
import { SwapRouterABI } from "./abis_cp/SwapRouter";
import { waitForTransactionReceipt } from "viem/actions";
import { hookDeploymentData } from "./utils";
import { PoolKey, encodePoolKeys } from "./utils";
dotenv.config();

// Add pool configurations
const POOL_CONFIGS = {
  pool01: {
    currency0: hookDeploymentData.addresses.token0,
    currency1: hookDeploymentData.addresses.token1,
    fee: 3000,
    tickSpacing: 120,
    hooks: hookDeploymentData.addresses.hook,
  },
  pool12: {
    currency0: hookDeploymentData.addresses.token1,
    currency1: hookDeploymentData.addresses.token2,
    fee: 3000,
    tickSpacing: 120,
    hooks: hookDeploymentData.addresses.hook,
  },
  pool02: {
    currency0: hookDeploymentData.addresses.token0,
    currency1: hookDeploymentData.addresses.token2,
    fee: 3000,
    tickSpacing: 120,
    hooks: hookDeploymentData.addresses.hook,
  },
} as const;

type PoolConfig = typeof POOL_CONFIGS[keyof typeof POOL_CONFIGS];

const account = privateKeyToAccount(process.env.PRIVATE_KEY! as `0x${string}`);

const walletClient = createWalletClient({
  chain: process.env.IS_DEV === "true" ? anvil : holesky,
  transport: http(),
  account,
});

const publicClient = createPublicClient({
  chain: process.env.IS_DEV === "true" ? anvil : holesky,
  transport: http(),
});

const swapRouter = getContract({
  address: hookDeploymentData.addresses.swapRouter,
  abi: SwapRouterABI,
  client: {
    public: publicClient,
    wallet: walletClient,
  },
});


// Different test scenarios
const TEST_SCENARIOS = {
  // Scenario 1: Simple CoW match (2 tasks that can match)
  cowMatch: [
    {
      zeroForOne: true,
      amountSpecified: -parseEther("1"), // Sell 1 token0 for token1
      sqrtPriceLimitX96: BigInt("152398000000000000000000000000"),
    },
    {
      zeroForOne: false,
      amountSpecified: -parseEther("1"), // Sell 1 token1 for token0
      sqrtPriceLimitX96: BigInt("162369000000000000000000000000"),
    }
  ],

  // Scenario 2: Circular CoW (3 tasks that form a circle)
  circularCow: [
    {
      zeroForOne: true,  // Task 1: token0 -> token1 in pool01
      amountSpecified: -parseEther("1"),
      sqrtPriceLimitX96: BigInt("152398000000000000000000000000"),
    },
    {
      zeroForOne: true,  // Task 2: token1 -> token2 in pool12
      amountSpecified: -parseEther("1"),
      sqrtPriceLimitX96: BigInt("152398000000000000000000000000"),
    },
    {
      zeroForOne: false, // Task 3: token2 -> token0 in pool02 (reverse direction)
      amountSpecified: -parseEther("1"),
      sqrtPriceLimitX96: BigInt("162369000000000000000000000000"),
    }
  ],

  // Scenario 3: Mixed matching (3 circular + 2 direct + 1 AMM)
  mixedMatching: [
    // Circular match group (token0 -> token1 -> token2 -> token0)
    {
      zeroForOne: true,  // Task 1: token0 -> token1 in pool01
      amountSpecified: -parseEther("1"),
      sqrtPriceLimitX96: BigInt("152398000000000000000000000000"),
    },
    {
      zeroForOne: true,  // Task 2: token1 -> token2 in pool12
      amountSpecified: -parseEther("1"),
      sqrtPriceLimitX96: BigInt("152398000000000000000000000000"),
    },
    {
      zeroForOne: false, // Task 3: token2 -> token0 in pool02 (reverse direction)
      amountSpecified: -parseEther("1"),
      sqrtPriceLimitX96: BigInt("162369000000000000000000000000"),
    },
    // Direct CoW match group (token0 <-> token1)
    {
      zeroForOne: true,  // Task 4: token0 -> token1 in pool01
      amountSpecified: -parseEther("0.5"),
      sqrtPriceLimitX96: BigInt("152398000000000000000000000000"),
    },
    {
      zeroForOne: false, // Task 5: token1 -> token0 in pool01 (reverse direction)
      amountSpecified: -parseEther("0.5"),
      sqrtPriceLimitX96: BigInt("162369000000000000000000000000"),
    },
    // AMM swap (token1 -> token2)
    {
      zeroForOne: true,  // Task 6: token1 -> token2 in pool12
      amountSpecified: -parseEther("0.3"),
      sqrtPriceLimitX96: BigInt("152398000000000000000000000000"),
    }
  ],
} as const;

async function createTask(numTasks: number, scenario: keyof typeof TEST_SCENARIOS = "cowMatch") {
  console.log(`Creating ${numTasks} tasks for scenario: ${scenario}`);
  
  const swapParams = TEST_SCENARIOS[scenario];
  const pools = [POOL_CONFIGS.pool01, POOL_CONFIGS.pool12, POOL_CONFIGS.pool02];

  // Create each task in sequence
  for (let i = 0; i < numTasks && i < swapParams.length; i++) {
    console.log(`Creating task ${i + 1}`);
    
    // Select the correct pool based on the task
    let pool;
    if (scenario === "mixedMatching") {
      if (i < 3) {
        // First 3 tasks use circular pools sequence
        pool = pools[i];
      } else if (i < 5) {
        // Tasks 4-5 use pool01 for direct matching
        pool = pools[0];
      } else {
        // Task 6 uses pool12 for AMM swap
        pool = pools[1];
      }
    } else {
      // For other scenarios, use sequential pools
      pool = pools[i % pools.length];
    }
    
    const txHash = await swapRouter.write.swap([
      pool,
      swapParams[i],
      {
        takeClaims: false,
        settleUsingBurn: false,
      },
      encodeAbiParameters(
        parseAbiParameters("int8,address,uint8,bytes"), [
          1,  // Enable CoW
          account.address,
          pools.length,
          toHex(encodePoolKeys(pools)),
        ]
      ),
    ]);

    await waitForTransactionReceipt(publicClient, {
      hash: txHash,
    });
    console.log("Task created:", txHash);
  }
}

// Export the main function and scenarios
export { createTask, TEST_SCENARIOS };

// If running directly from command line
if (require.main === module) {
  const args = process.argv.slice(2);
  const numTasks = parseInt(args[0]) || 2;
  const scenario = (args[1] as keyof typeof TEST_SCENARIOS) || "cowMatch";
  
  if (!TEST_SCENARIOS[scenario]) {
    console.error(`Invalid scenario. Available scenarios: ${Object.keys(TEST_SCENARIOS).join(", ")}`);
    process.exit(1);
  }

  createTask(numTasks, scenario)
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}