// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {OrderServiceManager} from "../src/OrderServiceManager.sol";
import {MockAVSDeployer} from "@eigenlayer-middleware/test/utils/MockAVSDeployer.sol";
import {ECDSAStakeRegistry} from "@eigenlayer-middleware/src/unaudited/ECDSAStakeRegistry.sol";
import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/Test.sol";
import {AVSDeploymentLib} from "../script/utils/AVSDeploymentLib.sol";
import {
    CoreDeployLib, CoreDeploymentParsingLib
} from "../script/utils/CoreDeploymentParsingLib.sol";
import {UpgradeableProxyLib} from "../script/utils/UpgradeableProxyLib.sol";
import {ERC20Mock} from "./ERC20Mock.sol";
import {IERC20, StrategyFactory} from "@eigenlayer/contracts/strategies/StrategyFactory.sol";

import {
    IECDSAStakeRegistryTypes,
    IStrategy
} from "@eigenlayer-middleware/src/interfaces/IECDSAStakeRegistry.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {
    IDelegationManager,
    IDelegationManagerTypes
} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {DelegationManager} from "@eigenlayer/contracts/core/DelegationManager.sol";
import {StrategyManager} from "@eigenlayer/contracts/core/StrategyManager.sol";
import {ISignatureUtilsMixinTypes} from "@eigenlayer/contracts/interfaces/ISignatureUtilsMixin.sol";
import {AVSDirectory} from "@eigenlayer/contracts/core/AVSDirectory.sol";
import {IAVSDirectoryTypes} from "@eigenlayer/contracts/interfaces/IAVSDirectory.sol";
import {Test, console2 as console} from "forge-std/Test.sol";
import {IOrderServiceManager} from "../src/IOrderServiceManager.sol";
import {ECDSAUpgradeable} from
    "@openzeppelin-upgrades/contracts/utils/cryptography/ECDSAUpgradeable.sol";

contract OrderTaskManagerSetup is Test {
    // used for `toEthSignedMessageHash`
    using ECDSAUpgradeable for bytes32;

    IECDSAStakeRegistryTypes.Quorum internal quorum;

    struct Operator {
        Vm.Wallet key;
        Vm.Wallet signingKey;
    }

    struct TrafficGenerator {
        Vm.Wallet key;
    }

    struct AVSOwner {
        Vm.Wallet key;
    }

    Operator[] internal operators;
    TrafficGenerator internal generator;
    AVSOwner internal owner;

    AVSDeploymentLib.DeploymentData internal AVSDeployment;
    CoreDeployLib.DeploymentData internal coreDeployment;
    CoreDeployLib.DeploymentConfigData coreConfigData;

    address proxyAdmin;

    ERC20Mock public mockToken;

    mapping(address => IStrategy) public tokenToStrategy;

    function setUp() public virtual {
        generator = TrafficGenerator({key: vm.createWallet("generator_wallet")});
        owner = AVSOwner({key: vm.createWallet("owner_wallet")});

        proxyAdmin = UpgradeableProxyLib.deployProxyAdmin();

        coreConfigData =
            CoreDeploymentParsingLib.readDeploymentConfigValues("test/mockData/config/core/", 1337);
        coreDeployment = CoreDeployLib.deployContracts(proxyAdmin, coreConfigData);

        vm.prank(coreConfigData.strategyManager.initialOwner);
        StrategyManager(coreDeployment.strategyManager).setStrategyWhitelister(
            coreDeployment.strategyFactory
        );

        mockToken = new ERC20Mock();

        IStrategy strategy = addStrategy(address(mockToken));
        quorum.strategies.push(
            IECDSAStakeRegistryTypes.StrategyParams({strategy: strategy, multiplier: 10_000})
        );

        AVSDeployment = AVSDeploymentLib.deployContracts(
            proxyAdmin, coreDeployment, quorum, owner.key.addr, owner.key.addr
        );
        AVSDeployment.strategy = address(strategy);
        AVSDeployment.token = address(mockToken);
        labelContracts(coreDeployment, AVSDeployment);
    }

    function addStrategy(
        address token
    ) public returns (IStrategy) {
        if (tokenToStrategy[token] != IStrategy(address(0))) {
            return tokenToStrategy[token];
        }

        StrategyFactory strategyFactory = StrategyFactory(coreDeployment.strategyFactory);
        IStrategy newStrategy = strategyFactory.deployNewStrategy(IERC20(token));
        tokenToStrategy[token] = newStrategy;
        return newStrategy;
    }

    function labelContracts(
        CoreDeployLib.DeploymentData memory _coreDeployment,
        AVSDeploymentLib.DeploymentData memory _avsDeployment
    ) internal {
        vm.label(_coreDeployment.delegationManager, "DelegationManager");
        vm.label(_coreDeployment.avsDirectory, "AVSDirectory");
        vm.label(_coreDeployment.strategyManager, "StrategyManager");
        vm.label(_coreDeployment.eigenPodManager, "EigenPodManager");
        vm.label(_coreDeployment.rewardsCoordinator, "RewardsCoordinator");
        vm.label(_coreDeployment.eigenPodBeacon, "EigenPodBeacon");
        vm.label(_coreDeployment.pauserRegistry, "PauserRegistry");
        vm.label(_coreDeployment.strategyFactory, "StrategyFactory");
        vm.label(_coreDeployment.strategyBeacon, "StrategyBeacon");
        vm.label(_avsDeployment.orderServiceManager, "OrderServiceManager");
        vm.label(_avsDeployment.stakeRegistry, "StakeRegistry");
    }

    function signWithOperatorKey(
        Operator memory operator,
        bytes32 digest
    ) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator.key.privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function signWithSigningKey(
        Operator memory operator,
        bytes32 digest
    ) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator.signingKey.privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function mintMockTokens(Operator memory operator, uint256 amount) internal {
        mockToken.mint(operator.key.addr, amount);
    }

    function depositTokenIntoStrategy(
        Operator memory operator,
        address token,
        uint256 amount
    ) internal returns (uint256) {
        IStrategy strategy = IStrategy(tokenToStrategy[token]);
        require(address(strategy) != address(0), "Strategy was not found");
        IStrategyManager strategyManager = IStrategyManager(coreDeployment.strategyManager);

        vm.startPrank(operator.key.addr);
        mockToken.approve(address(strategyManager), amount);
        uint256 shares = strategyManager.depositIntoStrategy(strategy, IERC20(token), amount);
        vm.stopPrank();

        return shares;
    }

    function registerAsOperator(
        Operator memory operator
    ) internal {
        IDelegationManager delegationManager = IDelegationManager(coreDeployment.delegationManager);

        vm.prank(operator.key.addr);
        delegationManager.registerAsOperator(address(0), 0, "");
    }

    function registerOperatorToAVS(
        Operator memory operator
    ) internal {
        ECDSAStakeRegistry stakeRegistry = ECDSAStakeRegistry(AVSDeployment.stakeRegistry);
        AVSDirectory avsDirectory = AVSDirectory(coreDeployment.avsDirectory);

        bytes32 salt = keccak256(abi.encodePacked(block.timestamp, operator.key.addr));
        uint256 expiry = block.timestamp + 1 hours;

        bytes32 operatorRegistrationDigestHash = avsDirectory
            .calculateOperatorAVSRegistrationDigestHash(
            operator.key.addr, address(AVSDeployment.orderServiceManager), salt, expiry
        );

        bytes memory signature = signWithOperatorKey(operator, operatorRegistrationDigestHash);

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature =
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry({
            signature: signature,
            salt: salt,
            expiry: expiry
        });

        vm.prank(address(operator.key.addr));
        stakeRegistry.registerOperatorWithSignature(operatorSignature, operator.signingKey.addr);
    }

    function deregisterOperatorFromAVS(
        Operator memory operator
    ) internal {
        ECDSAStakeRegistry stakeRegistry = ECDSAStakeRegistry(AVSDeployment.stakeRegistry);

        vm.prank(operator.key.addr);
        stakeRegistry.deregisterOperator();
    }

    function createAndAddOperator() internal returns (Operator memory) {
        Vm.Wallet memory operatorKey =
            vm.createWallet(string.concat("operator", vm.toString(operators.length)));
        Vm.Wallet memory signingKey =
            vm.createWallet(string.concat("signing", vm.toString(operators.length)));

        Operator memory newOperator = Operator({key: operatorKey, signingKey: signingKey});

        operators.push(newOperator);
        return newOperator;
    }

    // function updateOperatorWeights(
    //     Operator[] memory _operators
    // ) internal {
    //     ECDSAStakeRegistry stakeRegistry = ECDSAStakeRegistry(helloWorldDeployment.stakeRegistry);

    //     address[] memory operatorAddresses = new address[](_operators.length);
    //     for (uint256 i = 0; i < _operators.length; i++) {
    //         operatorAddresses[i] = _operators[i].key.addr;
    //     }

    //     stakeRegistry.updateOperators(operatorAddresses);
    // }

    function getOperators(
        uint256 numOperators
    ) internal view returns (Operator[] memory) {
        require(numOperators <= operators.length, "Not enough operators");

        Operator[] memory operatorsMem = new Operator[](numOperators);
        for (uint256 i = 0; i < numOperators; i++) {
            operatorsMem[i] = operators[i];
        }
        // Sort the operators by address
        for (uint256 i = 0; i < numOperators - 1; i++) {
            uint256 minIndex = i;
            // Find the minimum operator by address
            for (uint256 j = i + 1; j < numOperators; j++) {
                if (operatorsMem[minIndex].key.addr > operatorsMem[j].key.addr) {
                    minIndex = j;
                }
            }
            // Swap the minimum operator with the ith operator
            Operator memory temp = operatorsMem[i];
            operatorsMem[i] = operatorsMem[minIndex];
            operatorsMem[minIndex] = temp;
        }
        return operatorsMem;
    }

    function createTask(
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        address sender,
        bytes32 poolId
    ) internal returns (IOrderServiceManager.Task memory task, uint32 taskIndex) {
        IOrderServiceManager orderServiceManager =
            IOrderServiceManager(AVSDeployment.orderServiceManager);

        vm.prank(generator.key.addr);
        taskIndex = orderServiceManager.latestTaskNum();
        task = orderServiceManager.createNewTask(
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96,
            sender,
            poolId
        );
        return (task, taskIndex);
    }

    function respondToTask(
        Operator[] memory operatorsMem,
        IOrderServiceManager.Task memory task,
        uint32[] storage referenceTaskIndices
    ) internal {
        bytes memory signedResponse = makeTaskResponse(operatorsMem, task);
        

        // If the interface expects a single uint32 instead of a uint32[] storage, use referenceTaskIndices[0]
       
        // Update the function call to match the actual interface definition of IOrderServiceManager
        IOrderServiceManager(AVSDeployment.orderServiceManager).respondToTask(
            task, referenceTaskIndices[0], signedResponse
        );
        // If the function does not exist or has a different signature, update the call to match the correct function name and parameters as defined in IOrderServiceManager.
    }

    function makeTaskResponse(
        Operator[] memory operatorsMem,
        IOrderServiceManager.Task memory task
    ) internal view returns (bytes memory) {
        // bytes32 messageHash = keccak256(abi.encodePacked("Hello, ", task.name));
        bytes32 messageHash = keccak256(abi.encodePacked(
            true,
            uint256(1 ether),
            uint256(152398000000000000000000000000),
            address(this)
        ));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();

        address[] memory operatorAddrs = new address[](operatorsMem.length);
        for (uint256 i = 0; i < operatorsMem.length; i++) {
            operatorAddrs[i] = operatorsMem[i].key.addr;
        }
        bytes[] memory signatures = new bytes[](operatorsMem.length);
        for (uint256 i = 0; i < operatorsMem.length; i++) {
            signatures[i] = signWithSigningKey(operatorsMem[i], ethSignedMessageHash);
        }

        bytes memory signedTask = abi.encode(operatorAddrs, signatures, task.taskCreatedBlock);

        return signedTask;
    }

    function slashOperator(
        IOrderServiceManager.Task memory task,
        uint32 referenceTaskIndex,
        address operator
    ) internal {
        IOrderServiceManager(AVSDeployment.orderServiceManager).slashOperator(
            task, referenceTaskIndex, operator
        );
    }
}

contract OrderServiceManagerInitialization is OrderTaskManagerSetup {
    function testInitialization() public view {
        ECDSAStakeRegistry stakeRegistry = ECDSAStakeRegistry(AVSDeployment.stakeRegistry);

        IECDSAStakeRegistryTypes.Quorum memory quorum = stakeRegistry.quorum();

        assertGt(quorum.strategies.length, 0, "No strategies in quorum");
        assertEq(
            address(quorum.strategies[0].strategy),
            address(tokenToStrategy[address(mockToken)]),
            "First strategy doesn't match mock token strategy"
        );

        assertTrue(AVSDeployment.stakeRegistry != address(0), "StakeRegistry not deployed");
        assertTrue(
            AVSDeployment.orderServiceManager != address(0),
            "HelloWorldServiceManager not deployed"
        );
        assertTrue(coreDeployment.delegationManager != address(0), "DelegationManager not deployed");
        assertTrue(coreDeployment.avsDirectory != address(0), "AVSDirectory not deployed");
        assertTrue(coreDeployment.strategyManager != address(0), "StrategyManager not deployed");
        assertTrue(coreDeployment.eigenPodManager != address(0), "EigenPodManager not deployed");
        assertTrue(coreDeployment.strategyFactory != address(0), "StrategyFactory not deployed");
        assertTrue(coreDeployment.strategyBeacon != address(0), "StrategyBeacon not deployed");
    }
}

contract RegisterOperator is OrderTaskManagerSetup {
    uint256 internal constant INITIAL_BALANCE = 100 ether;
    uint256 internal constant DEPOSIT_AMOUNT = 1 ether;
    uint256 internal constant OPERATOR_COUNT = 4;

    DelegationManager internal delegationManager;
    AVSDirectory internal avsDirectory;
    IOrderServiceManager internal sm;
    ECDSAStakeRegistry internal stakeRegistry;

    function setUp() public virtual override {
        super.setUp();
        /// Setting to internal state for convenience
        delegationManager = DelegationManager(coreDeployment.delegationManager);
        avsDirectory = AVSDirectory(coreDeployment.avsDirectory);
        sm = IOrderServiceManager(AVSDeployment.orderServiceManager);
        stakeRegistry = ECDSAStakeRegistry(AVSDeployment.stakeRegistry);

        addStrategy(address(mockToken));

        while (operators.length < OPERATOR_COUNT) {
            createAndAddOperator();
        }

        for (uint256 i = 0; i < OPERATOR_COUNT; i++) {
            mintMockTokens(operators[i], INITIAL_BALANCE);

            depositTokenIntoStrategy(operators[i], address(mockToken), DEPOSIT_AMOUNT);

            registerAsOperator(operators[i]);
        }
    }

    function testVerifyOperatorStates() public view {
        for (uint256 i = 0; i < OPERATOR_COUNT; i++) {
            address operatorAddr = operators[i].key.addr;

            uint256 operatorShares =
                delegationManager.operatorShares(operatorAddr, tokenToStrategy[address(mockToken)]);
            assertEq(
                operatorShares, DEPOSIT_AMOUNT, "Operator shares in DelegationManager incorrect"
            );
        }
    }

    function test_RegisterOperatorToAVS() public {
        address operatorAddr = operators[0].key.addr;
        registerOperatorToAVS(operators[0]);
        assertTrue(
            avsDirectory.avsOperatorStatus(address(sm), operatorAddr)
                == IAVSDirectoryTypes.OperatorAVSRegistrationStatus.REGISTERED,
            "Operator not registered in AVSDirectory"
        );

        address signingKey = stakeRegistry.getLatestOperatorSigningKey(operatorAddr);
        assertTrue(signingKey != address(0), "Operator signing key not set in ECDSAStakeRegistry");

        uint256 operatorWeight = stakeRegistry.getLastCheckpointOperatorWeight(operatorAddr);
        assertTrue(operatorWeight > 0, "Operator weight not set in ECDSAStakeRegistry");
    }
}

contract CreateTask is OrderTaskManagerSetup {
    IOrderServiceManager internal sm;

    function setUp() public override {
        super.setUp();
        sm = IOrderServiceManager(AVSDeployment.orderServiceManager);
    }

    function testCreateTask() public {
        IOrderServiceManager.Task memory task = IOrderServiceManager.Task(
            true, // zeroForOne
            1 ether, // amountSpecified
            152398000000000000000000000000, // sqrtPriceLimitX96
            address(this), // sender
            keccak256(abi.encodePacked("Pool1")), // poolId
            uint32(0), // taskCreatedBlock, set to 0 or appropriate value if needed
            0 // <--- Add the missing 7th argument, set to 0 or appropriate value
        );

        vm.prank(generator.key.addr);
        IOrderServiceManager.Task memory newTask = sm.createNewTask(
            true,  // zeroForOne
            1 ether, // amountSpecified
            152398000000000000000000000000, // sqrtPriceLimitX96
            address(this), // sender
            keccak256(abi.encodePacked("Pool1")) // poolId
        );

        require(
            sha256(
                abi.encodePacked(
                    task.zeroForOne,
                    task.amountSpecified,
                    task.sqrtPriceLimitX96,
                    task.sender,
                    task.poolId,
                    task.taskCreatedBlock,
                    uint32(0) // Replace with the actual 7th field name if different
                )
            ) == sha256(
                abi.encodePacked(
                    newTask.zeroForOne,
                    newTask.amountSpecified,
                    newTask.sqrtPriceLimitX96,
                    newTask.sender,
                    newTask.poolId,
                    newTask.taskCreatedBlock,
                    uint32(0) // Replace with the actual 7th field name if different
                )
            ),
            "Task name not set correctly"
        );
        require(
            newTask.taskCreatedBlock == uint32(block.number), "Task created block not set correctly"
        );
    }
}

contract RespondToTask is OrderTaskManagerSetup {
    uint256 internal constant INITIAL_BALANCE = 100 ether;
    uint256 internal constant DEPOSIT_AMOUNT = 1 ether;
    uint256 internal constant OPERATOR_COUNT = 4;

    IDelegationManager internal delegationManager;
    AVSDirectory internal avsDirectory;
    IOrderServiceManager internal sm;
    ECDSAStakeRegistry internal stakeRegistry;

    function setUp() public override {
        super.setUp();

        delegationManager = IDelegationManager(coreDeployment.delegationManager);
        avsDirectory = AVSDirectory(coreDeployment.avsDirectory);
        sm = IOrderServiceManager(AVSDeployment.orderServiceManager);
        stakeRegistry = ECDSAStakeRegistry(AVSDeployment.stakeRegistry);

        addStrategy(address(mockToken));

        while (operators.length < OPERATOR_COUNT) {
            createAndAddOperator();
        }

        for (uint256 i = 0; i < OPERATOR_COUNT; i++) {
            mintMockTokens(operators[i], INITIAL_BALANCE);

            depositTokenIntoStrategy(operators[i], address(mockToken), DEPOSIT_AMOUNT);

            registerAsOperator(operators[i]);

            registerOperatorToAVS(operators[i]);
        }
    }

    function testRespondToTask() public {
        (IOrderServiceManager.Task memory newTask, uint32 taskIndex) = createTask(
            true, 
            1,
            1 ether,
            address(this),
            keccak256(abi.encodePacked("Pool1"))
        );

        Operator[] memory operatorsMem = getOperators(1);
        bytes memory signedResponse = makeTaskResponse(operatorsMem, newTask);

        vm.roll(block.number + 1);
        sm.respondToTask(newTask, taskIndex, signedResponse);
    }

    function testRespondToTaskWith2OperatorsAggregatedSignature() public {
        (IOrderServiceManager.Task memory newTask, uint32 taskIndex) =
            createTask(
                true, // zeroForOne
                1, // amountSpecified
                1 ether, // sqrtPriceLimitX96
                address(this), // sender
                keccak256(abi.encodePacked("TestTask2Aggregated")) // poolId
            );

        // Generate aggregated response with two operators
        Operator[] memory operatorsMem = getOperators(2);
        bytes memory signedResponse = makeTaskResponse(operatorsMem, newTask);

        vm.roll(block.number + 1);
        sm.respondToTask(newTask, taskIndex, signedResponse);
    }

    function testRespondToTaskWith3OperatorsAggregatedSignature() public {
        (IOrderServiceManager.Task memory newTask, uint32 taskIndex) =
            createTask(
                true, // zeroForOne
                1, // amountSpecified
                1 ether, // sqrtPriceLimitX96
                address(this), // sender
                keccak256(abi.encodePacked("TestTask3Aggregated")) // poolId
            );

        // Generate aggregated response with three operators
        Operator[] memory operatorsMem = getOperators(3);
        bytes memory signedResponse = makeTaskResponse(operatorsMem, newTask);

        vm.roll(block.number + 1);
        sm.respondToTask(newTask, taskIndex, signedResponse);
    }
}

// contract SlashOperator is OrderTaskManagerSetup {
//     uint256 internal constant INITIAL_BALANCE = 100 ether;
//     uint256 internal constant DEPOSIT_AMOUNT = 1 ether;
//     uint256 internal constant OPERATOR_COUNT = 4;

//     IDelegationManager internal delegationManager;
//     AVSDirectory internal avsDirectory;
//     IOrderServiceManager internal sm;
//     ECDSAStakeRegistry internal stakeRegistry;

//     function setUp() public override {
//         super.setUp();

//         delegationManager = IDelegationManager(coreDeployment.delegationManager);
//         avsDirectory = AVSDirectory(coreDeployment.avsDirectory);
//         sm = IOrderServiceManager(AVSDeployment.orderServiceManager);
//         stakeRegistry = ECDSAStakeRegistry(AVSDeployment.stakeRegistry);

//         addStrategy(address(mockToken));

//         while (operators.length < OPERATOR_COUNT) {
//             createAndAddOperator();
//         }

//         for (uint256 i = 0; i < OPERATOR_COUNT; i++) {
//             mintMockTokens(operators[i], INITIAL_BALANCE);

//             depositTokenIntoStrategy(operators[i], address(mockToken), DEPOSIT_AMOUNT);

//             registerAsOperator(operators[i]);

//             registerOperatorToAVS(operators[i]);
//         }
//     }

    // function testValidResponseIsNotSlashable() public {
    //     (IOrderServiceManager.Task memory newTask, uint32 taskIndex) =
    //         createTask("TestValidResponseIsNotSlashable");

    //     Operator[] memory operatorsMem = getOperators(1);

    //     vm.roll(block.number + 1);
    //     respondToTask(operatorsMem, newTask, taskIndex);

    //     vm.expectRevert("Task has already been responded to");
    //     slashOperator(newTask, taskIndex, operatorsMem[0].key.addr);

    //     // TODO: check the operator's balance was not reduced
    // }

    // function testNoResponseIsSlashable() public {
    //     (IOrderServiceManager.Task memory newTask, uint32 taskIndex) =
    //         createTask("TestNoResponseIsSlashable");

    //     Operator[] memory operatorsMem = getOperators(1);

    //     uint32 maxResponseIntervalBlocks =
    //         HelloWorldServiceManager(address(sm)).MAX_RESPONSE_INTERVAL_BLOCKS();
    //     vm.roll(block.number + maxResponseIntervalBlocks + 1);

    //     slashOperator(newTask, taskIndex, operatorsMem[0].key.addr);

    //     // TODO: check the operator's balance was reduced
    // }

    // function testMultipleSlashings() public {
    //     (IOrderServiceManager.Task memory newTask, uint32 taskIndex) =
    //         createTask("TestMultipleSlashings");

    //     Operator[] memory operatorsMem = getOperators(3);

    //     uint32 maxResponseIntervalBlocks =
    //         OrderServiceManager(address(sm)).MAX_RESPONSE_INTERVAL_BLOCKS();
    //     vm.roll(block.number + maxResponseIntervalBlocks + 1);

    //     slashOperator(newTask, taskIndex, operatorsMem[0].key.addr);
    //     slashOperator(newTask, taskIndex, operatorsMem[1].key.addr);
    //     slashOperator(newTask, taskIndex, operatorsMem[2].key.addr);

    //     // TODO: check the operator's balance was reduced
    // }
// }
