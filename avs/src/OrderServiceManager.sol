// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {ECDSAServiceManagerBase} from
    "@eigenlayer-middleware/src/unaudited/ECDSAServiceManagerBase.sol";
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

    uint32 public latestTaskNum;
    address public hook;
    mapping(uint32 => bytes32) public allTaskHashes;
    mapping(uint32 => bytes) public allTaskResponses;
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

    constructor(
        address _avsDirectory,
        address _stakeRegistry,
        address _rewardsCoordinator,
        address _delegationManager,
        address _allocationManager,
        uint32 _maxResponseIntervalBlocks
    )
        ECDSAServiceManagerBase(
            _avsDirectory,
            _stakeRegistry,
            _rewardsCoordinator,
            _delegationManager,
            _allocationManager
        )
    {
        // MAX_RESPONSE_INTERVAL_BLOCKS = _maxResponseIntervalBlocks;
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
    ) external onlyHook {
        Task memory task = Task({
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
                allTaskResponses[referenceTaskIndices[i]].length == 0,
                "Task already responded"
            );
            // require(
            //     block.number <= task.taskCreatedBlock + MAX_RESPONSE_INTERVAL_BLOCKS,
            //     "Task response time has already expired"
            // );
        }

        // The message that was signed
        bytes32 messageHash = getMessageHash(tasks[0].poolId, transferBalances, swapBalances);


        // // Code to review  
        // bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        // bytes4 magicValue = IERC1271Upgradeable.isValidSignature.selector;

        // // Decode the signature data to get operators and their signatures
        // (address[] memory operators, bytes[] memory signatures, uint32[] referenceBlocks) =
        //     abi.decode(signature, (address[], bytes[], uint32));

        // // Check that referenceBlock matches task creation block
        // require(
        //     referenceBlock == task.taskCreatedBlock,
        //     "Reference block must match task creation block"
        // );

         // Verify all signatures at once if using the staking part
        // bytes4 isValidSignatureResult =
        //     ECDSAStakeRegistry(stakeRegistry).isValidSignature(ethSignedMessageHash, signature);

        // require(magicValue == isValidSignatureResult, "Invalid signature");

        address signer = ECDSAUpgradeable.recover(messageHash, signature);
        require(signer == msg.sender, "Invalid signature");


        // Store each operator's signature
        // for (uint256 i = 0; i < operators.length; i++) {
        //     // Check that this operator hasn't already responded
        //     require(
        //         allTaskResponses[operators[i]][referenceTaskIndex].length == 0,
        //         "Operator has already responded to the task"
        //     );

        //     // Store the operator's signature
        //     allTaskResponses[operators[i]][referenceTaskIndex] = signatures[i];

        //     // Emit event for this operator
        //     emit TaskResponded(referenceTaskIndex, task, operators[i]);
        // }

        // taskWasResponded[referenceTaskIndex] = true;

        // Store responses
        for (uint256 i = 0; i < referenceTaskIndices.length; i++) {
            allTaskResponses[referenceTaskIndices[i]] = signature;
        }

        // For circular matches (3 tasks), use first task's poolId to maintain token flow
        bytes32 poolIdToUse = tasks[0].poolId;
        
        // Settle all balances in one call
        IDarkCoWHook(hook).settleBalances(
            poolIdToUse,
            transferBalances,
            swapBalances
        );

        emit BatchResponse(referenceTaskIndices, msg.sender);

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
}
