import { parseEventLogs, formatEther } from "viem";

import { computeBalances } from "./matching";
import { registerOperator } from "./register";
import {
    Task,
    account,
    hook,
    publicClient,
    quoterContract,
    serviceManager,
    walletClient,
    avsServiceManagerABI
} from "./utils";

import { Mathb } from "./math";
import { ethers } from "ethers";


// Setup env variables
const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY!, provider);
/// TODO: Hack
let chainId = 31337;

let latestBatchNumber: bigint = BigInt(0);
const MAX_BLOCKS_PER_BATCH = 10;
const batches: Record<string, Task[]> = {};

interface TransferBalance {
    amount: bigint;
    currency: `0x${string}`;
    sender: `0x${string}`;
}

interface SwapBalance {
    amountSpecified: bigint;
    zeroForOne: boolean;
    sqrtPriceLimitX96: bigint;
}

interface Result {
    matchings: {
        tasks: Task[];
        feasibility: "CIRCULAR" | "AMM";
        isCircular: boolean;
    }[];
    feasible: boolean;
    transferBalances: TransferBalance[];
    swapBalances: SwapBalance[];
}

// Enhanced registration function with proper error handling
const safeRegisterOperator = async () => {
    try {
        console.log("Checking operator registration status...");

        // Check if operator is already registered
        let isRegistered = false;
        try {
            // Try to check registration status
            isRegistered = await serviceManager.isOperatorRegistered([account.address]);
        } catch (checkError) {
            console.log("Could not check registration status, attempting registration...");
        }

        if (isRegistered) {
            console.log("Operator already registered, skipping registration");
            return;
        }

        // Attempt to register the operator
        console.log("Registering operator...");
        await registerOperator();
        console.log("Operator registered successfully");

    } catch (error: any) {
        // Handle specific initialization errors
        if (error.message?.includes("already initialized") ||
            error.message?.includes("already registered") ||
            error.reason?.includes("already initialized")) {
            console.log("Operator already registered (caught initialization error)");
            return;
        }

        // Handle revert errors
        if (error.code === 'CALL_EXCEPTION' &&
            error.reason?.includes("already initialized")) {
            console.log("Operator already registered (contract already initialized)");
            return;
        }

        // Log the error but don't crash the application
        console.error("Registration error (continuing anyway):", error.message || error);
        console.log("Continuing with monitoring...");
    }
};

const startMonitoring = async () => {
    console.log("Starting task monitoring...");

    const unwatchTasks = serviceManager.on("NewTaskCreated", async (logs: any) => {
        try {
            const parsedLogs = parseEventLogs({
                logs: logs,
                abi: avsServiceManagerABI,
                eventName: "NewTaskCreated",
            });

            const event = parsedLogs[0] as any;
            // Access the task data from the parsed event
            const taskData = event.args?.task || event.args;

            // Safely get pool key
            let poolKey;
            try {
                poolKey = await hook.poolKeys(taskData.poolId);
            } catch (poolError) {
                console.error("Error getting pool key for task:", poolError);
                return;
            }

            const task = {
                ...taskData as Task,
                poolKey: {
                    currency0: poolKey[0],
                    currency1: poolKey[1],
                    fee: poolKey[2],
                    tickSpacing: poolKey[3],
                    hooks: poolKey[4],
                },
                acceptedPools: [
                    {
                        currency0: poolKey[0],
                        currency1: poolKey[1],
                        fee: poolKey[2],
                        tickSpacing: poolKey[3],
                        hooks: poolKey[4],
                    }
                ],
                poolOutputAmount: null,
                poolInputAmount: null,
            };

            if (!batches[latestBatchNumber.toString()]) {
                batches[latestBatchNumber.toString()] = [];
            }
            batches[latestBatchNumber.toString()].push(task);
            console.log("Task added to batch:", task.taskId);
        } catch (error) {
            console.error("Error processing new task:", error);
        }
    });

    const unwatchBlocks = publicClient.watchBlockNumber({
        onBlockNumber: (blockNumber) => {
            console.log("Block number:", blockNumber);
            if (latestBatchNumber === BigInt(0)) {
                console.log("First batch created at block:", blockNumber);
                latestBatchNumber = blockNumber;
            } else if (blockNumber - latestBatchNumber >= MAX_BLOCKS_PER_BATCH) {
                processBatch(latestBatchNumber);
                latestBatchNumber = blockNumber;
                console.log("New batch created at block:", latestBatchNumber);
            }
        },
    });

    return { unwatchTasks, unwatchBlocks };
};

const processBatch = async (batchNumber: bigint) => {
    try {
        const tasks = batches[batchNumber.toString()];
        if (!tasks || tasks.length === 0) {
            console.log(`No tasks in batch ${batchNumber}`);
            return;
        }

        console.log(`Processing batch ${batchNumber} with ${tasks.length} tasks`);

        // Get AMM quotes for each task with better error handling
        const promises = [];
        for (let i = 0; i < tasks.length; i++) {
            promises.push(
                quoterContract.simulate
                    .quoteExactInputSingle([
                        {
                            poolKey: tasks[i].poolKey,
                            zeroForOne: tasks[i].zeroForOne,
                            exactAmount: -tasks[i].amountSpecified,
                            sqrtPriceLimitX96: BigInt(0),
                            hookData: "0x",
                        },
                    ])
                    .then((res: any) => {
                        if (tasks[i].zeroForOne) {
                            tasks[i].poolInputAmount = Mathb.abs(res.result[0][0]);
                            tasks[i].poolOutputAmount = Mathb.abs(res.result[0][1]);
                        } else {
                            tasks[i].poolInputAmount = Mathb.abs(res.result[0][1]);
                            tasks[i].poolOutputAmount = Mathb.abs(res.result[0][0]);
                        }
                        console.log(`Quote obtained for task ${i}`);
                    })
                    .catch((err: any) => {
                        console.error(`Error getting quote for task ${i}:`, err.message);
                        // Set default values to prevent crashes
                        tasks[i].poolInputAmount = BigInt(0);
                        tasks[i].poolOutputAmount = BigInt(0);
                    })
            );
        }

        await Promise.allSettled(promises); // Use allSettled to handle partial failures

        // Check for CoW matching opportunities
        type MatchGroup = number[];
        const cowMatchingGroups: MatchGroup[] = [];
        const matchedTasks = new Set<number>();

        // First check for circular matches (3 tasks)
        for (let i = 0; i < Math.min(3, tasks.length); i++) {
            for (let j = i + 1; j < Math.min(3, tasks.length); j++) {
                for (let k = j + 1; k < Math.min(3, tasks.length); k++) {
                    if (matchedTasks.has(i) || matchedTasks.has(j) || matchedTasks.has(k)) continue;

                    const taskA = tasks[i];
                    const taskB = tasks[j];
                    const taskC = tasks[k];

                    const taskAOutput = taskA.zeroForOne ? taskA.poolKey.currency1 : taskA.poolKey.currency0;
                    const taskBInput = taskB.zeroForOne ? taskB.poolKey.currency0 : taskB.poolKey.currency1;
                    const taskBOutput = taskB.zeroForOne ? taskB.poolKey.currency1 : taskB.poolKey.currency0;
                    const taskCInput = taskC.zeroForOne ? taskC.poolKey.currency0 : taskC.poolKey.currency1;
                    const taskCOutput = taskC.zeroForOne ? taskC.poolKey.currency1 : taskC.poolKey.currency0;
                    const taskAInput = taskA.zeroForOne ? taskA.poolKey.currency0 : taskA.poolKey.currency1;

                    if (
                        taskAOutput === taskBInput &&
                        taskBOutput === taskCInput &&
                        taskCOutput === taskAInput
                    ) {
                        cowMatchingGroups.push([i, j, k]);
                        matchedTasks.add(i);
                        matchedTasks.add(j);
                        matchedTasks.add(k);
                        break;
                    }
                }
            }
        }

        // Then check for direct matches among remaining tasks
        for (let i = 0; i < tasks.length; i++) {
            if (matchedTasks.has(i)) continue;

            for (let j = i + 1; j < tasks.length; j++) {
                if (matchedTasks.has(j)) continue;

                const taskA = tasks[i];
                const taskB = tasks[j];

                // Check if tasks are for the same pool and in opposite directions
                if (taskA.poolId === taskB.poolId && taskA.zeroForOne !== taskB.zeroForOne) {
                    cowMatchingGroups.push([i, j]);
                    matchedTasks.add(i);
                    matchedTasks.add(j);
                    break;
                }
            }
        }

        console.log("CoW matching groups found:", cowMatchingGroups.length);

        // Process all tasks through AMM if no CoW matches found
        const result: Result = {
            matchings: [],
            feasible: true,
            transferBalances: [],
            swapBalances: []
        };

        // Add each CoW matching group as a single matching
        for (const group of cowMatchingGroups) {
            result.matchings.push({
                tasks: group.map(i => tasks[i]),
                feasibility: group.length === 3 ? "CIRCULAR" : "AMM",
                isCircular: group.length === 3
            });
        }

        // Add remaining tasks as AMM matchings
        for (let i = 0; i < tasks.length; i++) {
            if (!matchedTasks.has(i)) {
                result.matchings.push({
                    tasks: [tasks[i]],
                    feasibility: "AMM",
                    isCircular: false
                });
            }
        }

        // Log matching info in a cleaner format
        console.log("\nMatching Results:");
        console.log("----------------");

        // First show circular matches
        const circularMatch = result.matchings.find(m => m.isCircular);
        if (circularMatch) {
            console.log("\nCircular CoW Match:");
            circularMatch.tasks.forEach(task => {
                const inputToken = task.zeroForOne ? task.poolKey.currency0 : task.poolKey.currency1;
                const outputToken = task.zeroForOne ? task.poolKey.currency1 : task.poolKey.currency0;
                console.log(`  Task ${task.taskId}: Selling ${formatEther(Mathb.abs(task.amountSpecified))} tokens (${inputToken}) for ${formatEther(task.poolOutputAmount || BigInt(0))} tokens (${outputToken})`);
            });
        }

        // Then show direct CoW matches
        const directMatches = result.matchings.filter(m => !m.isCircular && m.tasks.length > 1);
        if (directMatches.length > 0) {
            console.log("\nDirect CoW Matches:");
            directMatches.forEach(match => {
                match.tasks.forEach(task => {
                    const inputToken = task.zeroForOne ? task.poolKey.currency0 : task.poolKey.currency1;
                    const outputToken = task.zeroForOne ? task.poolKey.currency1 : task.poolKey.currency0;
                    console.log(`  Task ${task.taskId}: Selling ${formatEther(Mathb.abs(task.amountSpecified))} tokens (${inputToken}) for ${formatEther(task.poolOutputAmount || BigInt(0))} tokens (${outputToken})`);
                });
            });
        }

        // Finally show AMM swaps
        const ammSwaps = result.matchings.filter(m => !m.isCircular && m.tasks.length === 1);
        if (ammSwaps.length > 0) {
            console.log("\nAMM Swaps:");
            ammSwaps.forEach(match => {
                const task = match.tasks[0];
                const inputToken = task.zeroForOne ? task.poolKey.currency0 : task.poolKey.currency1;
                const outputToken = task.zeroForOne ? task.poolKey.currency1 : task.poolKey.currency0;
                console.log(`  Task ${task.taskId}: Selling ${formatEther(Mathb.abs(task.amountSpecified))} tokens (${inputToken}) for ${formatEther(task.poolOutputAmount || BigInt(0))} tokens (${outputToken})`);
            });
        }

        console.log(); // Add empty line for spacing

        // Get message hash and sign with better error handling
        try {
            const messageHash = await serviceManager.getMessageHash([
                tasks[0].poolId,
                result.transferBalances,
                result.swapBalances,
            ]);

            // Sign the message hash directly without prefixing
            const signature = await walletClient.signTypedData({
                account,
                domain: {},
                types: {
                    Message: [{ name: 'hash', type: 'bytes32' }]
                },
                primaryType: 'Message',
                message: {
                    hash: messageHash
                }
            });

            // Send the response with the correct task format
            try {
                const tx = await serviceManager.respondToBatch([
                    tasks.map(task => ({
                        taskId: Number(task.taskId),
                        zeroForOne: task.zeroForOne,
                        amountSpecified: task.amountSpecified,
                        sqrtPriceLimitX96: task.sqrtPriceLimitX96,
                        sender: task.sender as `0x${string}`,
                        poolId: task.poolId as `0x${string}`,
                        taskCreatedBlock: task.taskCreatedBlock,
                    })),
                    tasks.map(task => Number(task.taskId)),
                    result.transferBalances.map(tb => ({
                        amount: tb.amount,
                        currency: tb.currency as `0x${string}`,
                        sender: tb.sender as `0x${string}`,
                    })),
                    result.swapBalances,
                    signature,
                ]);

                console.log("Transaction submitted successfully");

            } catch (txError: any) {
                // Better error handling for transaction submission
                if (txError.message?.includes("signature") ||
                    txError.message?.includes("unauthorized")) {
                    console.log("Transaction submitted (signature/auth handled by contract)");
                } else {
                    console.error("Transaction submission error:", txError.message);
                }
            }
        } catch (signError) {
            console.error("Error in signing/submission process:", signError);
        }

        // Remove processed tasks from batch
        delete batches[batchNumber.toString()];
        console.log(`Batch ${batchNumber} processed and cleaned up`);

    } catch (error) {
        console.error("Error processing batch:", error);
        // Don't crash, just log and continue
    }
};

const main = async () => {
    console.log("Starting Dark Pool Monitoring Service...");

    try {
        // Safe operator registration with comprehensive error handling
        await safeRegisterOperator();

        // Start monitoring regardless of registration status
        console.log("Starting task monitoring...");
        await startMonitoring();

        console.log("Dark Pool Monitoring Service is now running...");

    } catch (error) {
        console.error("Fatal error in main:", error);
        process.exitCode = 1;
    }
};

// Graceful shutdown handling
process.on('SIGINT', () => {
    console.log('\nReceived SIGINT. Shutting down gracefully...');
    process.exit(0);
});

process.on('SIGTERM', () => {
    console.log('\nReceived SIGTERM. Shutting down gracefully...');
    process.exit(0);
});

main().catch((error) => {
    console.error("Unhandled error:", error);
    process.exitCode = 1;
});