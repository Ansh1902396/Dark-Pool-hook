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
import {StrategyFactory} from "@eigenlayer/contracts/strategies/StrategyFactory.sol";
import {StrategyManager} from "@eigenlayer/contracts/core/StrategyManager.sol";
import {IRewardsCoordinator} from "@eigenlayer/contracts/interfaces/IRewardsCoordinator.sol";

import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";

import {
    IECDSAStakeRegistryTypes,
    IStrategy
} from "@eigenlayer-middleware/src/interfaces/IECDSAStakeRegistry.sol";

import {StrategyBaseTVLLimits} from "@eigenlayer/contracts/strategies/StrategyBaseTVLLimits.sol";

import "forge-std/Test.sol";

contract AVSDeployer is Script, Test {
    using CoreDeployLib for *;
    using UpgradeableProxyLib for address;

    StrategyBaseTVLLimits public erc20MockStrategy;

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


    ProxyAdmin public avsProxyAdmin;
    PauserRegistry public avsPauserRegistry;

    // ECDSAStakeRegistry public stakeRegistryProxy;
    // ECDSAStakeRegistry public stakeRegistryImpl;

    // UniCowServiceManager public serviceManagerProxy;
    // UniCowServiceManager public serviceManagerImpl;

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

        //  // Eigenlayer contract

        token = new ERC20Mock();
        console.log(address(token));

        
        IERC20 eigenToken = IERC20(address(token));
        avsStrategy = StrategyFactory(coreDeployment.strategyFactory).deployedStrategies(eigenToken);
        // avsStrategy =
        //     IStrategy(StrategyFactory(coreDeployment.strategyFactory).deployedStrategies(IERC20(address(token))));

        quorum.strategies.push(
            IECDSAStakeRegistryTypes.StrategyParams({
                strategy: avsStrategy,
                multiplier: 10_000
            })
        );
        

        // proxyAdmin = UpgradeableProxyLib.deployProxyAdmin();

        

        // // NOTE: if this fails, it's because the initialStrategyWhitelister is not set to be the StrategyFactory
        // // Whitelisting the strategyFactory:

        // _deployErc20AndStrategyAndWhitelistStrategy(
        //     avsProxyAdmin,
        //     PauserRegistry(coreDeployment.pauserRegistry),
        //     erc20MockStrategy,
        //     IStrategyManager(coreDeployment.strategyManager)
        // );

        

        

        token.mint(deployer, 2000);
        token.increaseAllowance(address(coreDeployment.strategyManager), 1000);
        StrategyManager(coreDeployment.strategyManager).depositIntoStrategy(
            avsStrategy, token, 1000
        );

        avsDeployment = AVSDeploymentLib.deployContracts(
            proxyAdmin, coreDeployment, quorum, rewardsInitiator, rewardsOwner
        );
        
        avsDeployment.strategy = address(avsStrategy);
        avsDeployment.token = address(token);

        vm.stopBroadcast();
        verifyDeployment();
        AVSDeploymentLib.writeDeploymentJson(avsDeployment);
    }

        // function _deployErc20AndStrategyAndWhitelistStrategy(
        //     ProxyAdmin eigenLayerProxyAdmin,
        //     PauserRegistry eigenLayerPauserReg,
        //     StrategyBaseTVLLimits baseStrategyImplementation,
        //     IStrategyManager strategyManager
        // ) internal {
        //     token = new ERC20Mock();
        //     // TODO(samlaf): any reason why we are using the strategybase with tvl limits instead of just using strategybase?
        //     // the maxPerDeposit and maxDeposits below are just arbitrary values.
        //     erc20MockStrategy = StrategyBaseTVLLimits(
        //         address(
        //             new TransparentUpgradeableProxy(
        //                 address(baseStrategyImplementation),
        //                 address(eigenLayerProxyAdmin),
        //                 abi.encodeWithSelector(
        //                     StrategyBaseTVLLimits.initialize.selector,
        //                     1 ether, // maxPerDeposit
        //                     100 ether, // maxDeposits
        //                     address(token),
        //                     eigenLayerPauserReg
        //                 )
        //             )
        //         )
        //     );
        //     IStrategy[] memory strats = new IStrategy[](1);
        //     strats[0] = erc20MockStrategy;
        //     strategyManager.addStrategiesToDepositWhitelist(
        //         strats
        //     );
        // }

    function verifyDeployment() internal view {
        require(
            avsDeployment.stakeRegistry != address(0), "StakeRegistry address cannot be zero"
        );
        require(
            avsDeployment.orderServiceManager != address(0),
            "HelloWorldServiceManager address cannot be zero"
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
