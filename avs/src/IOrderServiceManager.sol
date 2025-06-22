// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IOrderServiceManager {
    struct Task {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
        address sender;
        bytes32 poolId;
        uint32 taskCreatedBlock;
        uint32 taskId;
    }

    event NewTaskCreated(uint32 indexed taskIndex, Task task);
    event BatchResponse(uint32[] indexed referenceTaskIndices, address sender);


    function latestTaskNum() external view returns (uint32);

    function allTaskHashes(
        uint32 taskIndex
    ) external view returns (bytes32);

    // function allTaskResponses(
    //     address operator,
    //     uint32 taskIndex
    // ) external view returns (bytes memory);

    // function createNewTask(
    //     string memory name
    // ) external returns (Task memory);

    // function respondToTask(
    //     Task calldata task,
    //     uint32 referenceTaskIndex,
    //     bytes calldata signature
    // ) external;

    function slashOperator(
        Task calldata task,
        uint32 referenceTaskIndex,
        address operator
    ) external;

    function createNewTask(
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        address sender,
        bytes32 poolId
    ) external returns (Task memory task);
}
