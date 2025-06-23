// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/Test.sol";
import {AVSDeploymentLib} from "./utils/AVSDeploymentLib.sol";
import {CoreDeployLib, CoreDeploymentParsingLib} from "./utils/CoreDeploymentParsingLib.sol";
import {UpgradeableProxyLib} from "./utils/UpgradeableProxyLib.sol";
import {StrategyBase} from "@eigenlayer/contracts/strategies/StrategyBase.sol";
import {ERC20Mock} from "../test/ERC20Mock.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {StrategyFactory} from "@eigenlayer/contracts/strategies/StrategyFactory.sol";
import {StrategyManager} from "@eigenlayer/contracts/core/StrategyManager.sol";
import {IRewardsCoordinator} from "@eigenlayer/contracts/interfaces/IRewardsCoordinator.sol";
import {OrderServiceManager} from "../src/OrderServiceManager.sol";
import {IStrategyManager} from "@eigenlayer/contracts/interfaces/IStrategyManager.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {IPauserRegistry} from "@eigenlayer/contracts/interfaces/IPauserRegistry.sol";

import {
    IECDSAStakeRegistryTypes,
    IStrategy
} from "@eigenlayer-middleware/src/interfaces/IECDSAStakeRegistry.sol";

import "forge-std/Test.sol";

contract AVSDeployer is Script, Test {
    using CoreDeployLib for *;
    using UpgradeableProxyLib for address;

    address private deployer;
    address proxyAdmin;
    address rewardsOwner;
    address rewardsInitiator;
    IStrategy avsStrategy;
    CoreDeployLib.DeploymentData coreDeployment;
    AVSDeploymentLib.DeploymentData avsDeployment;
    AVSDeploymentLib.DeploymentConfigData avsConfig;
    IECDSAStakeRegistryTypes.Quorum internal quorum;
    ERC20Mock token;

    function setUp() public virtual {
        deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        vm.label(deployer, "Deployer");

        avsConfig =
            AVSDeploymentLib.readDeploymentConfigValues("config/avs/", block.chainid);

        coreDeployment =
            CoreDeploymentParsingLib.readDeploymentJson("deployments/core/", block.chainid);
    }

    function run() external {
        vm.startBroadcast(deployer);
        rewardsOwner = avsConfig.rewardsOwner;
        rewardsInitiator = avsConfig.rewardsInitiator;

        // Deploy proxy admin first
        proxyAdmin = UpgradeableProxyLib.deployProxyAdmin();
        console2.log("ProxyAdmin deployed:", proxyAdmin);

        // Deploy token
        token = new ERC20Mock();
        console2.log("Token deployed:", address(token));

        // Deploy strategy manually to avoid StrategyFactory permission issues
        avsStrategy = _deployStrategy();
        console2.log("Strategy deployed:", address(avsStrategy));

        // Set up quorum with the strategy
        quorum.strategies.push(
            IECDSAStakeRegistryTypes.StrategyParams({
                strategy: avsStrategy,
                multiplier: 10_000
            })
        );

        // Mint tokens for future use (but skip deposit for now)
        token.mint(deployer, 2000);
        console2.log("Minted 2000 tokens");

        // Deploy AVS contracts without requiring a deposit
        console2.log("Deploying AVS contracts...");

        // Deploy AVS contracts
        avsDeployment = AVSDeploymentLib.deployContracts(
            proxyAdmin, coreDeployment, quorum, rewardsInitiator, rewardsOwner
        );

        // Store strategy and token addresses in deployment data
        avsDeployment.strategy = address(avsStrategy);
        avsDeployment.token = address(token);

        vm.stopBroadcast();
        
        verifyDeployment();
        AVSDeploymentLib.writeDeploymentJson(avsDeployment);
        
        // Log deployment addresses
        console2.log("=== OrderServiceManager AVS Deployment Successful ===");
        console2.log("OrderServiceManager:", avsDeployment.orderServiceManager);
        console2.log("StakeRegistry:", avsDeployment.stakeRegistry);
        console2.log("Strategy:", avsDeployment.strategy);
        console2.log("Token:", avsDeployment.token);
        console2.log("ProxyAdmin:", proxyAdmin);
    }

    function _deployStrategy() internal returns (IStrategy) {
        console2.log("Deploying strategy manually...");
        
        // Deploy a simple StrategyBase implementation directly
        // This avoids beacon complexity and just creates a working strategy
        StrategyBase strategyImpl = new StrategyBase(
            IStrategyManager(coreDeployment.strategyManager),
            IPauserRegistry(coreDeployment.pauserRegistry),
            "OrderAVSStrategy"
        );
        
        console2.log("Deployed StrategyBase implementation:", address(strategyImpl));
        
        // Deploy proxy pointing to our implementation
        address strategyProxy = address(new TransparentUpgradeableProxy(
            address(strategyImpl),
            proxyAdmin,
            abi.encodeWithSelector(
                StrategyBase.initialize.selector,
                token,
                coreDeployment.pauserRegistry
            )
        ));
        
        console2.log("Deployed strategy proxy:", strategyProxy);
        return IStrategy(strategyProxy);
    }

    function _ensureStrategyWhitelisted() internal {
        IStrategyManager strategyManager = IStrategyManager(coreDeployment.strategyManager);
        
        console2.log("Checking strategy whitelist status...");
        
        // Skip whitelist check and try to whitelist directly
        // Some StrategyManager implementations may not have the check function
        console2.log("Attempting to whitelist strategy...");
        
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = avsStrategy;
        
        try strategyManager.addStrategiesToDepositWhitelist(strategies) {
            console2.log("Strategy whitelisted successfully");
        } catch Error(string memory reason) {
            console2.log("Whitelist failed with reason:", reason);
            console2.log("Strategy may already be whitelisted or you may not have permissions");
        } catch {
            console2.log("Whitelist failed, strategy may already be whitelisted or you may not have permissions");
        }
    }

    // Alternative run function that sets hook after deployment
    function runWithHook(address hookAddress) external {
        vm.startBroadcast(deployer);
        rewardsOwner = avsConfig.rewardsOwner;
        rewardsInitiator = avsConfig.rewardsInitiator;

        // Deploy proxy admin first
        proxyAdmin = UpgradeableProxyLib.deployProxyAdmin();

        // Deploy token and strategy
        token = new ERC20Mock();
        avsStrategy = _deployStrategy();

        // Set up quorum with the strategy
        quorum.strategies.push(
            IECDSAStakeRegistryTypes.StrategyParams({
                strategy: avsStrategy,
                multiplier: 10_000
            })
        );

        // Mint tokens and deposit into strategy
        token.mint(deployer, 2000);
        token.increaseAllowance(address(coreDeployment.strategyManager), 1000);
        
        // Try to deposit directly, skip whitelist check for now
        console2.log("Attempting to deposit into strategy...");
        try StrategyManager(coreDeployment.strategyManager).depositIntoStrategy(
            avsStrategy, token, 1000
        ) returns (uint256 shares) {
            console2.log("Deposited into strategy, received shares:", shares);
        } catch Error(string memory reason) {
            console2.log("Deposit failed with reason:", reason);
            console2.log("Continuing deployment without deposit...");
        } catch {
            console2.log("Deposit failed, continuing deployment without deposit...");
        }

        // Deploy AVS contracts
        avsDeployment = AVSDeploymentLib.deployContracts(
            proxyAdmin, coreDeployment, quorum, rewardsInitiator, rewardsOwner
        );

        // Store strategy and token addresses in deployment data
        avsDeployment.strategy = address(avsStrategy);
        avsDeployment.token = address(token);

        // Set the hook address
        OrderServiceManager(avsDeployment.orderServiceManager).setHook(hookAddress);

        vm.stopBroadcast();
        
        verifyDeployment();
        AVSDeploymentLib.writeDeploymentJson(avsDeployment);
        
        // Log deployment addresses
        console2.log("=== OrderServiceManager AVS Deployment Successful (with Hook) ===");
        console2.log("OrderServiceManager:", avsDeployment.orderServiceManager);
        console2.log("StakeRegistry:", avsDeployment.stakeRegistry);
        console2.log("Strategy:", avsDeployment.strategy);
        console2.log("Token:", avsDeployment.token);
        console2.log("ProxyAdmin:", proxyAdmin);
        console2.log("Hook:", hookAddress);
    }

    function verifyDeployment() internal view {
        require(
            avsDeployment.stakeRegistry != address(0), "StakeRegistry address cannot be zero"
        );
        require(
            avsDeployment.orderServiceManager != address(0),
            "OrderServiceManager address cannot be zero"
        );
        require(avsDeployment.strategy != address(0), "Strategy address cannot be zero");
        require(proxyAdmin != address(0), "ProxyAdmin address cannot be zero");
        require(
            coreDeployment.delegationManager != address(0),
            "DelegationManager address cannot be zero"
        );
        require(coreDeployment.avsDirectory != address(0), "AVSDirectory address cannot be zero");
    }
}