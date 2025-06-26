// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {ECDSAServiceManagerBase} from "@eigenlayer-middleware/src/unaudited/ECDSAServiceManagerBase.sol";
import {ECDSAStakeRegistry} from "@eigenlayer-middleware/src/unaudited/ECDSAStakeRegistry.sol";
import {IServiceManager} from "@eigenlayer-middleware/src/interfaces/IServiceManager.sol";
import {ECDSAUpgradeable} from
    "@openzeppelin-upgrades/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import {IERC1271Upgradeable} from
    "@openzeppelin-upgrades/contracts/interfaces/IERC1271Upgradeable.sol";
import {IOrderServiceManager} from "./IOrderServiceManager.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@eigenlayer/contracts/interfaces/IRewardsCoordinator.sol";
import {IAllocationManager} from "@eigenlayer/contracts/interfaces/IAllocationManager.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {ISP1Verifier} from "sp1-contracts/src/ISP1Verifier.sol";



interface IDarkCoWHook {
    struct TransferBalance {
        uint256 amount;
        address currency;
        address sender;
    }

    struct SwapBalance {
        int256 amountSpecified;
        bool zeroForOne;
        uint160 sqrtPriceLimitX96;
    }

    function settleBalances(
        bytes32 key,
        TransferBalance[] memory transferBalances,
        SwapBalance[] memory swapBalances
    ) external;
}

contract OrderServiceManager is ECDSAServiceManagerBase, IOrderServiceManager {
    using ECDSAUpgradeable for bytes32;

    event TaskResponded(uint32 indexed taskIndex, Task task, address operator);
    event ProveRequest(
        uint32 indexed taskIndex,
        address indexed operator,
        bytes32 marketCurrentPrice,
        uint256 marketBlockTimestamp,
        bytes32 treeRoot,
        bytes32 nullifierHash,
        address walletAddress,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 targetPrice,
        uint256 deadline,
        bytes32 commitmentNullifier,
        uint256 balance,
        bytes32[] siblings,
        uint32[] indices
    );

    uint32 public latestTaskNum;
    address public hook;
    mapping(uint32 => bytes32) public allTaskHashes;
    mapping(address => mapping(uint32 => bytes)) public allTaskResponses;
    address public verifier;
    bytes32 public orderProgramVKey;

    // uint32 public immutable MAX_RESPONSE_INTERVAL_BLOCKS;

    modifier onlyOperator() {
        require(
            ECDSAStakeRegistry(stakeRegistry).operatorRegistered(msg.sender),
            "Operator must be the caller"
        );
        _;
    }

    modifier onlyHook() {
        require(msg.sender == hook, "Only hook can call this function");
        _;
    }
    
    struct PublicValuesStruct {
        uint32 n;
        uint32 a;
        uint32 b;
    }

    struct ProveRequestData {
        bytes32 marketCurrentPrice;
        uint256 marketBlockTimestamp;
        bytes32 treeRoot;
        bytes32 nullifierHash;
        address walletAddress;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 targetPrice;
        uint256 deadline;
        bytes32 commitmentNullifier;
        uint256 balance;
        bytes32[] siblings;
        uint32[] indices;
    }

    ProveRequestData proveData;

    constructor(
        address _avsDirectory,
        address _stakeRegistry,
        address _rewardsCoordinator,
        address _delegationManager,
        address _allocationManager,
        address _verifier, 
        bytes32 _orderProgramVKey
    )
        ECDSAServiceManagerBase(
            _avsDirectory,
            _stakeRegistry,
            _rewardsCoordinator,
            _delegationManager,
            _allocationManager
        )
    {
        verifier = _verifier;
        orderProgramVKey = _orderProgramVKey;
        // Initialize hardcoded prove data from RequestBody.json
        proveData = ProveRequestData({
            marketCurrentPrice: bytes32(uint256(2050000000)),
            marketBlockTimestamp: 1735600000,
            treeRoot: 0x1111111111111111111111111111111111111111111111111111111111111111,
            nullifierHash: 0x2222222222222222222222222222222222222222222222222222222222222222,
            walletAddress: 0x0000000000000000000000000000000000000001,
            tokenIn: 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa,
            tokenOut: 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB,
            amountIn: 5000000000000000000,
            minAmountOut: 10000000000,
            targetPrice: 2000000000,
            deadline: 1735689600,
            commitmentNullifier: 0x3333333333333333333333333333333333333333333333333333333333333333,
            balance: 10000000000000000000,
            siblings: new bytes32[](2),
            indices: new uint32[](2)
        });
        proveData.siblings[0] = 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;
        proveData.siblings[1] = 0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb;
        proveData.indices[0] = 0;
        proveData.indices[1] = 1;
    }

    function initialize(address initialOwner, address _rewardsInitiator) external initializer {
        __ServiceManagerBase_init(initialOwner, _rewardsInitiator);
    }

    

    // These are just to comply with IServiceManager interface
    function addPendingAdmin(
        address admin
    ) external onlyOwner {}

    function removePendingAdmin(
        address pendingAdmin
    ) external onlyOwner {}

    function removeAdmin(
        address admin
    ) external onlyOwner {}

    function setAppointee(address appointee, address target, bytes4 selector) external onlyOwner {}

    function removeAppointee(
        address appointee,
        address target,
        bytes4 selector
    ) external onlyOwner {}

    function deregisterOperatorFromOperatorSets(
        address operator,
        uint32[] memory operatorSetIds
    ) external {
        // unused
    }

    /* FUNCTIONS */
    // NOTE: this function creates new task, assigns it a taskId
    function createNewTask(
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        address sender,
        bytes32 poolId
    ) external onlyHook returns (Task memory task){
        task = Task({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: sqrtPriceLimitX96,
            sender: sender,
            poolId: poolId,
            taskCreatedBlock: uint32(block.number),
            taskId: latestTaskNum
        });
        allTaskHashes[latestTaskNum] = keccak256(abi.encode(task));
        emit NewTaskCreated(latestTaskNum, task);
        latestTaskNum++;
    }

    //operators to respond to tasks, batch of orders (order = a single a task)
    //Firstly, Verification using the sp1-contracts
    function respondToBatch(
        Task[] calldata tasks,
        uint32[] memory referenceTaskIndices,
        IDarkCoWHook.TransferBalance[] memory transferBalances,
        IDarkCoWHook.SwapBalance[] memory swapBalances,
        bytes memory signature
    ) external {
        // check that the task is valid, hasn't been responded yet, and is being responded in time
        for(uint256 i = 0;i<referenceTaskIndices.length; i++){
            require(
                keccak256(abi.encode(tasks[i])) == allTaskHashes[referenceTaskIndices[i]],
                "supplied task does not match the one recorded in the contract"
            );
            require(
                allTaskResponses[msg.sender][referenceTaskIndices[i]].length == 0,
                "Task already responded"
            );
        }

        // The message that was signed
        bytes32 messageHash = getMessageHash(tasks[0].poolId, transferBalances, swapBalances);


        address signer = ECDSAUpgradeable.recover(messageHash, signature);
        require(signer == msg.sender, "Invalid signature");

        // Store responses
        for (uint256 i = 0; i < referenceTaskIndices.length; i++) {
            allTaskResponses[msg.sender][referenceTaskIndices[i]] = signature;
        }

        // For circular matches (3 tasks), use first task's poolId to maintain token flow
        bytes32 poolIdToUse = tasks[0].poolId;

        // Create public values for proof verification
        bytes memory publicValues = abi.encode(PublicValuesStruct({
            n: uint32(proveData.indices.length),
            a: uint32(proveData.amountIn),
            b: uint32(proveData.minAmountOut)
        }));

        // Verify the order proof - convert memory to calldata-compatible format
        verifyOrderProofInternal(publicValues, signature);
        
        // Emit prove request event for off-chain processing
        emit ProveRequest(
            referenceTaskIndices[0],
            msg.sender,
            proveData.marketCurrentPrice,
            proveData.marketBlockTimestamp,
            proveData.treeRoot,
            proveData.nullifierHash,
            proveData.walletAddress,
            proveData.tokenIn,
            proveData.tokenOut,
            proveData.amountIn,
            proveData.minAmountOut,
            proveData.targetPrice,
            proveData.deadline,
            proveData.commitmentNullifier,
            proveData.balance,
            proveData.siblings,
            proveData.indices
        );
        
        // Settle all balances in one call
        IDarkCoWHook(hook).settleBalances(
            poolIdToUse,
            transferBalances,
            swapBalances
        );

        emit BatchResponse(referenceTaskIndices, msg.sender);

    }

    // Internal function to handle memory to calldata conversion
    function verifyOrderProofInternal(bytes memory _publicValues, bytes memory _proofBytes)
        internal
        view
        returns (uint32, uint32, uint32)
    {
        ISP1Verifier(verifier).verifyProof(orderProgramVKey, _publicValues, _proofBytes);
        PublicValuesStruct memory publicValues = abi.decode(_publicValues, (PublicValuesStruct));
        return (publicValues.n, publicValues.a, publicValues.b);
    }

    // Public function for external calls with proper calldata parameters
    function verifyOrderProof(bytes calldata _publicValues, bytes calldata _proofBytes)
        public
        view
        returns (uint32, uint32, uint32)
    {
        ISP1Verifier(verifier).verifyProof(orderProgramVKey, _publicValues, _proofBytes);
        PublicValuesStruct memory publicValues = abi.decode(_publicValues, (PublicValuesStruct));
        return (publicValues.n, publicValues.a, publicValues.b);
    }

    function getMessageHash(
        bytes32 poolId,
        IDarkCoWHook.TransferBalance[] memory transferBalances,
        IDarkCoWHook.SwapBalance[] memory swapBalances
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(poolId, transferBalances, swapBalances));
    }

    function slashOperator(
        Task calldata task,
        uint32 referenceTaskIndex,
        address operator
    ) external {
        // // check that the task is valid, hasn't been responsed yet
        // require(
        //     keccak256(abi.encode(task)) == allTaskHashes[referenceTaskIndex],
        //     "supplied task does not match the one recorded in the contract"
        // );
        // require(!taskWasResponded[referenceTaskIndex], "Task has already been responded to");
        // require(
        //     allTaskResponses[operator][referenceTaskIndex].length == 0,
        //     "Operator has already responded to the task"
        // );
        // require(
        //     block.number > task.taskCreatedBlock + MAX_RESPONSE_INTERVAL_BLOCKS,
        //     "Task response time has not expired yet"
        // );
        // // check operator was registered when task was created
        // uint256 operatorWeight = ECDSAStakeRegistry(stakeRegistry).getOperatorWeightAtBlock(
        //     operator, task.taskCreatedBlock
        // );
        // require(operatorWeight > 0, "Operator was not registered when task was created");

        // // we update the storage with a sentinel value
        // allTaskResponses[operator][referenceTaskIndex] = "slashed";

        // // TODO: slash operator
    }

    function setHook(address _hook) external {
        hook = _hook;
    }

    function getHook() external view returns (address) {
        return hook;
    }

    // Single task response function required by IOrderServiceManager interface
    function respondToTask(
        Task calldata task,
        uint32 referenceTaskIndex,
        bytes calldata signature
    ) external {
        // check that the task is valid, hasn't been responded yet
        require(
            keccak256(abi.encode(task)) == allTaskHashes[referenceTaskIndex],
            "supplied task does not match the one recorded in the contract"
        );
        require(
            allTaskResponses[msg.sender][referenceTaskIndex].length == 0,
            "Operator has already responded to the task"
        );

        // Store the operator's signature
        allTaskResponses[msg.sender][referenceTaskIndex] = signature;

        // Emit event for this operator
        emit TaskResponded(referenceTaskIndex, task, msg.sender);
    }
}