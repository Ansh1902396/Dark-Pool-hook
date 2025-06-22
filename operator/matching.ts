import { Mathb } from "./math";
import { Feasibility, Matching, PossibleResult, Task } from "./utils";


export function generateTaskCombinations(tasks: Task[]): Task[][] {
    // Single task combinations (AMM)
    const singleTasks = tasks.map(task => [task]);

    // Find circular matches (3 or more tasks)
    const circularMatches = findCircularMatches(tasks);

    return [...singleTasks, ...circularMatches];
}

function findCircularMatches(tasks: Task[]): Task[][] {
    const matches: Task[][] = [];
    if (tasks.length < 3) return matches;

    // Try each task as starting point
    for (let i = 0; i < tasks.length; i++) {
        const path: Task[] = [tasks[i]];
        const used = new Set([i]);
        findCircularPath(tasks, path, used, matches);
    }

    return matches;
}

function findCircularPath(tasks: Task[], path: Task[], used: Set<number>, matches: Task[][]) {
    const firstTask = path[0];
    const lastTask = path[path.length - 1];

    // Check if we can close the circle
    if (path.length >= 3) {
        const lastOutputToken = lastTask.zeroForOne ? lastTask.poolKey.currency1 : lastTask.poolKey.currency0;
        const firstInputToken = firstTask.zeroForOne ? firstTask.poolKey.currency0 : firstTask.poolKey.currency1;
        if (lastOutputToken === firstInputToken) {
            matches.push([...path]);
            return;
        }
    }

    // Try to extend the path
    for (let i = 0; i < tasks.length; i++) {
        if (used.has(i)) continue;

        const nextTask = tasks[i];
        const lastOutputToken = lastTask.zeroForOne ? lastTask.poolKey.currency1 : lastTask.poolKey.currency0;
        const nextInputToken = nextTask.zeroForOne ? nextTask.poolKey.currency0 : nextTask.poolKey.currency1;

        if (lastOutputToken === nextInputToken) {
            path.push(nextTask);
            used.add(i);
            findCircularPath(tasks, path, used, matches);
            path.pop();
            used.delete(i);
        }
    }
}



export function isCombinationPossible(tasks: Task[]): boolean {
    // Single task is always possible through AMM
    if (tasks.length === 1) return true;

    // For circular match, verify the circle is complete
    if (tasks.length >= 3) {
        const firstTask = tasks[0];
        const lastTask = tasks[tasks.length - 1];

        const firstInputToken = firstTask.zeroForOne ? firstTask.poolKey.currency0 : firstTask.poolKey.currency1;
        const lastOutputToken = lastTask.zeroForOne ? lastTask.poolKey.currency1 : lastTask.poolKey.currency0;

        if (firstInputToken === lastOutputToken) {
            // Verify the path is connected
            for (let i = 0; i < tasks.length - 1; i++) {
                const currentTask = tasks[i];
                const nextTask = tasks[i + 1];

                const currentOutputToken = currentTask.zeroForOne ? currentTask.poolKey.currency1 : currentTask.poolKey.currency0;
                const nextInputToken = nextTask.zeroForOne ? nextTask.poolKey.currency0 : nextTask.poolKey.currency1;

                if (currentOutputToken !== nextInputToken) return false;
            }
            return true;
        }
    }

    return false;
}

export function computePossibleResult(tasks: Task[]): PossibleResult {
    // Single task - use AMM
    if (tasks.length === 1) {
        return {
            matchings: [{
                tasks: tasks,
                feasibility: Feasibility.AMM,
                isCircular: false
            }],
            feasible: true,
            transferBalances: [],
            swapBalances: []
        };
    }

    // Circular match
    if (tasks.length >= 3 && isCombinationPossible(tasks)) {
        return {
            matchings: [{
                tasks: tasks,
                feasibility: Feasibility.CIRCULAR,
                isCircular: true
            }],
            feasible: true,
            transferBalances: [],
            swapBalances: []
        };
    }

    return {
        matchings: [{
            tasks: tasks,
            feasibility: Feasibility.NONE,
            isCircular: false
        }],
        feasible: false,
        transferBalances: [],
        swapBalances: []
    };
}


export function computeBestResult(results: PossibleResult[]): PossibleResult | null {
    // Prioritize circular matches over AMM
    const circularMatches = results.filter(r => r.feasible && r.matchings[0].feasibility === Feasibility.CIRCULAR);
    if (circularMatches.length > 0) return circularMatches[0];

    // Fallback to AMM
    const ammMatches = results.filter(r => r.feasible && r.matchings[0].feasibility === Feasibility.AMM);
    if (ammMatches.length > 0) return ammMatches[0];

    return null;
}

export function computeBalances(result: PossibleResult) {
    const transferBalances = [];
    const swapBalances = [];

    for (const matching of result.matchings) {
        if (matching.feasibility === Feasibility.AMM) {
            // AMM - each task gets its own swap
            for (const task of matching.tasks) {
                transferBalances.push({
                    amount: Mathb.abs(task.amountSpecified),
                    currency: task.zeroForOne ? task.poolKey.currency0 : task.poolKey.currency1,
                    sender: task.sender
                });

                swapBalances.push({
                    amountSpecified: task.amountSpecified,
                    zeroForOne: task.zeroForOne,
                    sqrtPriceLimitX96: task.sqrtPriceLimitX96
                });
            }
        } else if (matching.feasibility === Feasibility.CIRCULAR) {
            // Circular - each task gets output from next task
            for (let i = 0; i < matching.tasks.length; i++) {
                const task = matching.tasks[i];
                const nextTask = matching.tasks[(i + 1) % matching.tasks.length];

                transferBalances.push({
                    amount: task.poolOutputAmount!,
                    currency: task.zeroForOne ? task.poolKey.currency1 : task.poolKey.currency0,
                    sender: nextTask.sender
                });
            }
        }
    }

    return {
        transferBalances,
        swapBalances
    };
}