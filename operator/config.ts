export interface Config {
    contractAddress: string;
    rpcUrl: string;
    proveApiEndpoint: string;
    logLevel: 'debug' | 'info' | 'warn' | 'error';
}
import { avsServiceManagerAddress } from "./utils";

export function getConfig(): Config {
    return {
        contractAddress: avsServiceManagerAddress, // Replace with actual contract address
        rpcUrl: process.env.RPC_URL || "http://localhost:8545",
        proveApiEndpoint: process.env.PROVE_API_ENDPOINT || 'http://localhost:8080/prove',
        logLevel: (process.env.LOG_LEVEL as Config['logLevel']) || 'info'
    };
}

export function validateConfig(config: Config): void {
    if (!config.contractAddress || config.contractAddress === '0x...') {
        throw new Error('CONTRACT_ADDRESS environment variable is required');
    }

    if (!config.proverUrl) {
        throw new Error('RPC_URL environment variable is required');
    }

    if (!config.proveApiEndpoint) {
        throw new Error('PROVE_API_ENDPOINT environment variable is required');
    }
} 