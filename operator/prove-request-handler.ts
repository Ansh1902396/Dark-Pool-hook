import { ethers } from 'ethers';
import axios from 'axios';

// ABI for the ProveRequest event
const PROVE_REQUEST_ABI = [
    "event ProveRequest(uint32 indexed taskIndex, address indexed operator, bytes32 marketCurrentPrice, uint256 marketBlockTimestamp, bytes32 treeRoot, bytes32 nullifierHash, address walletAddress, address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, uint256 targetPrice, uint256 deadline, bytes32 commitmentNullifier, uint256 balance, bytes32[] siblings, uint32[] indices)"
];
import { avsServiceManagerAddress } from './utils';


// Contract address and RPC URL - these should be configured based on your deployment
const CONTRACT_ADDRESS = avsServiceManagerAddress; // Replace with actual contract address
const RPC_URL = 'http://localhost:8545'; // Replace with actual RPC URL
const PROVE_API_ENDPOINT = 'http://localhost:3000/prove'; // Replace with actual API endpoint

interface ProveRequestData {
    market: {
        current_price: string;
        block_timestamp: number;
    };
    tree_root: string;
    nullifier_hash: string;
    order: {
        wallet_address: string;
        token_in: string;
        token_out: string;
        amount_in: string;
        min_amount_out: string;
        target_price: string;
        deadline: number;
    };
    commitment_nullifier: string;
    balance: string;
    siblings: string[];
    indices: number[];
}

class ProveRequestHandler {
    private provider: ethers.providers.JsonRpcProvider;
    private contract: ethers.Contract;

    constructor() {
        this.provider = new ethers.providers.JsonRpcProvider(RPC_URL);
        this.contract = new ethers.Contract(CONTRACT_ADDRESS, PROVE_REQUEST_ABI, this.provider);
    }

    async startListening() {
        console.log('Starting to listen for ProveRequest events...');

        this.contract.on('ProveRequest', async (
            taskIndex: number,
            operator: string,
            marketCurrentPrice: string,
            marketBlockTimestamp: number,
            treeRoot: string,
            nullifierHash: string,
            walletAddress: string,
            tokenIn: string,
            tokenOut: string,
            amountIn: string,
            minAmountOut: string,
            targetPrice: string,
            deadline: number,
            commitmentNullifier: string,
            balance: string,
            siblings: string[],
            indices: number[]
        ) => {
            console.log(`Received ProveRequest event for task ${taskIndex} from operator ${operator}`);

            try {
                await this.sendProveRequest({
                    market: {
                        current_price: marketCurrentPrice,
                        block_timestamp: marketBlockTimestamp
                    },
                    tree_root: treeRoot,
                    nullifier_hash: nullifierHash,
                    order: {
                        wallet_address: walletAddress,
                        token_in: tokenIn,
                        token_out: tokenOut,
                        amount_in: amountIn,
                        min_amount_out: minAmountOut,
                        target_price: targetPrice,
                        deadline: deadline
                    },
                    commitment_nullifier: commitmentNullifier,
                    balance: balance,
                    siblings: siblings,
                    indices: indices
                });
            } catch (error) {
                console.error('Error processing ProveRequest:', error);
            }
        });
    }

    async sendProveRequest(data: ProveRequestData) {
        try {
            console.log('Sending POST request to /prove endpoint with data:', JSON.stringify(data, null, 2));

            const response = await axios.post(PROVE_API_ENDPOINT, data, {
                headers: {
                    'Content-Type': 'application/json'
                },
                timeout: 30000 // 30 second timeout
            });

            console.log('Prove request successful:', response.status, response.data);
        } catch (error) {
            console.error('Failed to send prove request:', error);
            if (axios.isAxiosError(error)) {
                console.error('Response data:', error.response?.data);
                console.error('Response status:', error.response?.status);
            }
        }
    }

    async stopListening() {
        this.contract.removeAllListeners('ProveRequest');
        console.log('Stopped listening for ProveRequest events');
    }
}

// Main execution
async function main() {
    const handler = new ProveRequestHandler();

    // Handle graceful shutdown
    process.on('SIGINT', async () => {
        console.log('\nReceived SIGINT, shutting down gracefully...');
        await handler.stopListening();
        process.exit(0);
    });

    process.on('SIGTERM', async () => {
        console.log('\nReceived SIGTERM, shutting down gracefully...');
        await handler.stopListening();
        process.exit(0);
    });

    await handler.startListening();
}

// Run the main function
if (require.main === module) {
    main().catch((error) => {
        console.error('Error in main:', error);
        process.exit(1);
    });
}

export { ProveRequestHandler, ProveRequestData };