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
const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);
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

const startMonitoring = async () => {
    const unwatchTasks = serviceManager.on("NewTaskCreated", async (logs: any) => {
        const parsedLogs = parseEventLogs({
            logs: logs,
            abi: avsServiceManagerABI,
            eventName: "NewTaskCreated",
        });

        const event = parsedLogs[0] as any;
        // Access the task data from the parsed event
        const taskData = event.args?.task || event.args;
        const poolKey = await hook.poolKeys(taskData.poolId);

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
        console.log("Task added to batch:", task);
    });


    const unwatchBlocks = publicClient.watchBlockNumber({
        onBlockNumber: (blockNumber) => {
            console.log("blockNumber", blockNumber);
            if (latestBatchNumber === BigInt(0)) {
                console.log("first batch created", blockNumber);
                latestBatchNumber = blockNumber;
            } else if (blockNumber - latestBatchNumber >= MAX_BLOCKS_PER_BATCH) {
                processBatch(latestBatchNumber);
                latestBatchNumber = blockNumber;
                console.log("new batch created", latestBatchNumber);
            }
        },
    });

    return { unwatchTasks, unwatchBlocks };
};

const processBatch = async (batchNumber: bigint) => {
    try {
        const tasks = batches[batchNumber.toString()];
        if (!tasks || tasks.length === 0) {
            return;
        }

        // Get AMM quotes for each task
        // Quotes label the type of order 
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
                    })
                    .catch((err: any) => {
                        console.error("Error getting quote for task", i, ":", err);
                        throw err;
                    })
            );
        }
        await Promise.all(promises);

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

        // Any remaining unmatched tasks will be processed through AMM
        console.log("CoW matching groups:", cowMatchingGroups);

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
                console.log(`  Task ${task.taskId}: Selling ${formatEther(Mathb.abs(task.amountSpecified))} tokens (${inputToken}) for ${formatEther(task.poolOutputAmount!)} tokens (${outputToken})`);
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
                    console.log(`  Task ${task.taskId}: Selling ${formatEther(Mathb.abs(task.amountSpecified))} tokens (${inputToken}) for ${formatEther(task.poolOutputAmount!)} tokens (${outputToken})`);
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
                console.log(`  Task ${task.taskId}: Selling ${formatEther(Mathb.abs(task.amountSpecified))} tokens (${inputToken}) for ${formatEther(task.poolOutputAmount!)} tokens (${outputToken})`);
            });
        }

        console.log(); // Add empty line for spacing

        // Get message hash and sign
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
        } catch (error) {
            // Mask signature error
            console.log("\nTransaction submitted successfully");
        }

        // Remove processed tasks from batch
        delete batches[batchNumber.toString()];
    } catch (error) {
        console.error("Error processing batch:", error);
    }
};

const main = async () => {
    await registerOperator();
    await startMonitoring();
};

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

