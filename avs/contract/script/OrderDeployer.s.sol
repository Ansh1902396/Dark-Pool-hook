// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/Test.sol";
import {OrderDeploymentLib} from "./utils/OrderDeploymentLib.sol";
import {CoreDeployLib, CoreDeploymentParsingLib} from "./utils/CoreDeploymentParsingLib.sol";
import {UpgradeableProxyLib} from "./utils/UpgradeableProxyLib.sol";
import {StrategyBase} from "@eigenlayer/contracts/strategies/StrategyBase.sol";
import {ERC20Mock} from "@eigenlayer-middleware/test/mocks/ERC20Mock.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {StrategyFactory} from "@eigenlayer/contracts/strategies/StrategyFactory.sol";
import {StrategyManager} from "@eigenlayer/contracts/core/StrategyManager.sol";
import {IRewardsCoordinator} from "@eigenlayer/contracts/interfaces/IRewardsCoordinator.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {OrderServiceManager} from "../src/OrderServiceManager.sol";

import {
    IECDSAStakeRegistryTypes,
    IStrategy
} from "@eigenlayer-middleware/src/interfaces/IECDSAStakeRegistry.sol";

import "forge-std/Test.sol";

contract OrderDeployer is Script, Test {
    using CoreDeployLib for *;
    using UpgradeableProxyLib for address;

    address private deployer;
    address proxyAdmin;
    address rewardsOwner;
    address rewardsInitiator;
    IStrategy orderStrategy;
    CoreDeployLib.DeploymentData coreDeployment;
    OrderDeploymentLib.DeploymentData orderDeployment;
    OrderDeploymentLib.DeploymentConfigData orderConfig;
    IECDSAStakeRegistryTypes.Quorum internal quorum;
    ERC20Mock token;

    function setUp() public virtual {
        deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        vm.label(deployer, "Deployer");

        orderConfig =
            OrderDeploymentLib.readDeploymentConfigValues("config/avs/", block.chainid);

        coreDeployment =
            CoreDeploymentParsingLib.readDeploymentJson("config/core/", block.chainid);
    }

    function run() external {
        vm.startBroadcast(deployer);
        rewardsOwner = orderConfig.rewardsOwner;
        rewardsInitiator = orderConfig.rewardsInitiator;

        token = new ERC20Mock();
        // NOTE: if this fails, it's because the initialStrategyWhitelister is not set to be the StrategyFactory
        orderStrategy =
            IStrategy(StrategyFactory(coreDeployment.strategyFactory).deployNewStrategy(token));

        quorum.strategies.push(
            IECDSAStakeRegistryTypes.StrategyParams({
                strategy: orderStrategy,
                multiplier: 10_000
            })
        );

        token.mint(deployer, 2000);
        token.increaseAllowance(address(coreDeployment.strategyManager), 1000);
        StrategyManager(coreDeployment.strategyManager).depositIntoStrategy(
            orderStrategy, token, 1000
        );

        proxyAdmin = UpgradeableProxyLib.deployProxyAdmin();

        orderDeployment = OrderDeploymentLib.deployContracts(
            proxyAdmin, 
            coreDeployment, 
            quorum, 
            rewardsInitiator, 
            rewardsOwner
        );

        orderDeployment.strategy = address(orderStrategy);
        orderDeployment.token = address(token);

        // Set hook after deployment if needed
        // OrderServiceManager(orderDeployment.orderServiceManager).setHook(hookAddress);

        vm.stopBroadcast();
        verifyDeployment();
        OrderDeploymentLib.writeDeploymentJson(orderDeployment);
    }

    // Alternative run function that accepts hook address as parameter
    function runWithHook(address hookAddress) external {
        vm.startBroadcast(deployer);
        rewardsOwner = orderConfig.rewardsOwner;
        rewardsInitiator = orderConfig.rewardsInitiator;

        token = new ERC20Mock();
        orderStrategy =
            IStrategy(StrategyFactory(coreDeployment.strategyFactory).deployNewStrategy(token));

        quorum.strategies.push(
            IECDSAStakeRegistryTypes.StrategyParams({
                strategy: orderStrategy,
                multiplier: 10_000
            })
        );

        token.mint(deployer, 2000);
        token.increaseAllowance(address(coreDeployment.strategyManager), 1000);
        StrategyManager(coreDeployment.strategyManager).depositIntoStrategy(
            orderStrategy, token, 1000
        );

        proxyAdmin = UpgradeableProxyLib.deployProxyAdmin();

        orderDeployment = OrderDeploymentLib.deployContracts(
            proxyAdmin, 
            coreDeployment, 
            quorum, 
            rewardsInitiator, 
            rewardsOwner
        );

        orderDeployment.strategy = address(orderStrategy);
        orderDeployment.token = address(token);

        // Set the hook address
        OrderServiceManager(orderDeployment.orderServiceManager).setHook(hookAddress);

        vm.stopBroadcast();
        verifyDeployment();
        OrderDeploymentLib.writeDeploymentJson(orderDeployment);
    }

    function verifyDeployment() internal view {
        require(
            orderDeployment.stakeRegistry != address(0), "StakeRegistry address cannot be zero"
        );
        require(
            orderDeployment.orderServiceManager != address(0),
            "OrderServiceManager address cannot be zero"
        );
        require(orderDeployment.strategy != address(0), "Strategy address cannot be zero");
        require(proxyAdmin != address(0), "ProxyAdmin address cannot be zero");
        require(
            coreDeployment.delegationManager != address(0),
            "DelegationManager address cannot be zero"
        );
        require(coreDeployment.avsDirectory != address(0), "AVSDirectory address cannot be zero");
        
        console2.log("=== OrderServiceManager Deployment Successful ===");
        console2.log("OrderServiceManager:", orderDeployment.orderServiceManager);
        console2.log("StakeRegistry:", orderDeployment.stakeRegistry);
        console2.log("Strategy:", orderDeployment.strategy);
        console2.log("Token:", orderDeployment.token);
        console2.log("ProxyAdmin:", proxyAdmin);
    }
}