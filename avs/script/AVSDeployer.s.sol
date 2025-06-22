// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// import {Script} from "forge-std/Script.sol";
// import {console2} from "forge-std/Test.sol";
// import {AVSDeploymentLib} from "./utils/AVSDeploymentLib.sol";
// import {CoreDeployLib, CoreDeploymentParsingLib} from "./utils/CoreDeploymentParsingLib.sol";
// import {UpgradeableProxyLib} from "./utils/UpgradeableProxyLib.sol";
// import {StrategyBase} from "@eigenlayer/contracts/strategies/StrategyBase.sol";
// import {ERC20Mock} from "../test/ERC20Mock.sol";
// import {TransparentUpgradeableProxy} from
//     "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
// import {StrategyFactory} from "@eigenlayer/contracts/strategies/StrategyFactory.sol";
// import {StrategyManager} from "@eigenlayer/contracts/core/StrategyManager.sol";
// import {IRewardsCoordinator} from "@eigenlayer/contracts/interfaces/IRewardsCoordinator.sol";
// import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";

// import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
// import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
// import "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
// import "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
// import {EmptyContract} from "@eigenlayer/test/mocks/EmptyContract.sol";

// import {OrderServiceManager, IOrderServiceManager} from "../src/OrderServiceManager.sol";
// import {ECDSAStakeRegistry} from "@eigenlayer-middleware/src/unaudited/ECDSAStakeRegistry.sol";

// import { StakeRegistry } from "@eigenlayer-middleware/src/StakeRegistry.sol";

// import {
//     IECDSAStakeRegistryTypes,
//     IStrategy
// } from "@eigenlayer-middleware/src/interfaces/IECDSAStakeRegistry.sol";

// import {StrategyBaseTVLLimits} from "@eigenlayer/contracts/strategies/StrategyBaseTVLLimits.sol";

// import "forge-std/Test.sol";

// contract AVSDeployer is Script, Test {
//     using CoreDeployLib for *;
//     using UpgradeableProxyLib for address;

//     StrategyBaseTVLLimits public erc20MockStrategy;

//     address private deployer;
//     address rewardsOwner;
//     address rewardsInitiator;
//     ERC20Mock public erc20Mock;
//     IStrategy avsStrategy;
//     CoreDeployLib.DeploymentData coreDeployment;
//     AVSDeploymentLib.DeploymentData avsDeployment;
//     AVSDeploymentLib.DeploymentConfigData avsConfig;
//     IECDSAStakeRegistryTypes.Quorum internal Quorum;
//     IECDSAStakeRegistryTypes.StrategyParams internal StrategyParams;

//     ERC20Mock token;

//     // address proxyAdmin = 0x5fbdb2315678afecb367f032d93f642f64180aa3
//     ProxyAdmin public avsProxyAdmin = new ProxyAdmin();
//     PauserRegistry public avsPauserRegistry;
    

//     ECDSAStakeRegistry public stakeRegistryProxy;
//     ECDSAStakeRegistry public stakeRegistryImpl;

//     OrderServiceManager public serviceManagerProxy;
//     OrderServiceManager public serviceManagerImpl;
//     function setUp() public virtual {
//         deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
//         vm.label(deployer, "Deployer");

//         avsConfig =
//             AVSDeploymentLib.readDeploymentConfigValues("config/avs/", block.chainid);

//         coreDeployment =
//             CoreDeploymentParsingLib.readDeploymentJson("deployments/core/", block.chainid);
//     }

//     function run() external {
//         vm.createSelectFork("http://localhost:8545");

//         // Eigenlayer contracts
//         IStrategyManager strategyManager = IStrategyManager(
//             coreDeployment.strategyManager
//         );

//         IDelegationManager delegationManager = IDelegationManager(
//             coreDeployment.delegationManager
//         );

        
//         IAVSDirectory avsDirectory = IAVSDirectory(
//             coreDeployment.avsDirectory
//         );
//         ProxyAdmin eigenLayerProxyAdmin = ProxyAdmin(
//             avsProxyAdmin
//         );
//         PauserRegistry eigenLayerPauserReg = PauserRegistry(
//             coreDeployment.pauserRegistry
//         );
//         StrategyBaseTVLLimits baseStrategyImplementation = StrategyBaseTVLLimits(
//             coreDeployment.strategyManager,
//             coreDeployment.pauserRegistry,
//             "^0.8.0"
//         );

//         address avsCommunityMultisig = msg.sender;
//         address avsPauser = msg.sender;

//         vm.startBroadcast();
//         _deployErc20AndStrategyAndWhitelistStrategy(
//             eigenLayerProxyAdmin,
//             eigenLayerPauserReg,
//             baseStrategyImplementation,
//             strategyManager
//         );
//         _deployAvsContracts(
//             delegationManager,
//             avsDirectory,
//             erc20MockStrategy,
//             avsCommunityMultisig,
//             avsPauser
//         );
//         vm.stopBroadcast();
//     }

//     function _deployErc20AndStrategyAndWhitelistStrategy(
//             ProxyAdmin eigenLayerProxyAdmin,
//             PauserRegistry eigenLayerPauserReg,
//             StrategyBaseTVLLimits baseStrategyImplementation,
//             IStrategyManager strategyManager
//     ) internal {
//             token = new ERC20Mock();
//             // TODO(samlaf): any reason why we are using the strategybase with tvl limits instead of just using strategybase?
//             // the maxPerDeposit and maxDeposits below are just arbitrary values.
//             erc20MockStrategy = StrategyBaseTVLLimits(
//                 address(
//                     new TransparentUpgradeableProxy(
//                         address(baseStrategyImplementation),
//                         address(eigenLayerProxyAdmin),
//                         abi.encodeWithSelector(
//                             StrategyBaseTVLLimits.initialize.selector,
//                             1 ether, // maxPerDeposit
//                             100 ether, // maxDeposits
//                             address(token),
//                             eigenLayerPauserReg
//                         )
//                     )
//                 )
//             );
//             IStrategy[] memory strats = new IStrategy[](1);
//             strats[0] = erc20MockStrategy;
//             strategyManager.addStrategiesToDepositWhitelist(
//                 strats
//             );
//     }

//     function _deployAvsContracts(
//         IDelegationManager delegationManager,
//         IAVSDirectory avsDirectory,
//         IStrategy strat,
//         address avsCommunityMultisig,
//         address avsPauser
//     ) internal {
//         // Adding this as a temporary fix to make the rest of the script work with a single strategy
//         // since it was originally written to work with an array of strategies
//         IStrategy[1] memory deployedStrategyArray = [strat];
//         uint numStrategies = deployedStrategyArray.length;

//         // deploy proxy admin for ability to upgrade proxy contracts
//         avsProxyAdmin = new ProxyAdmin();

//         // deploy pauser registry
//         {
//             address[] memory pausers = new address[](2);
//             pausers[0] = avsPauser;
//             pausers[1] = avsCommunityMultisig;
//             avsPauserRegistry = new PauserRegistry(
//                 pausers,
//                 avsCommunityMultisig
//             );
//         }

//         EmptyContract emptyContract = new EmptyContract();

//         // hard-coded inputs

//         /**
//          * First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
//          * not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
//          */
//         serviceManagerProxy = OrderServiceManager(
//             address(
//                 new TransparentUpgradeableProxy(
//                     address(emptyContract),
//                     address(avsProxyAdmin),
//                     ""
//                 )
//             )
//         );
//         stakeRegistryProxy = ECDSAStakeRegistry(
//             address(
//                 new TransparentUpgradeableProxy(
//                     address(emptyContract),
//                     address(avsProxyAdmin),
//                     ""
//                 )
//             )
//         );

//         // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
//         {
//             stakeRegistryImpl = new ECDSAStakeRegistry(delegationManager);

//             avsProxyAdmin.upgrade(
//                 TransparentUpgradeableProxy(
//                     payable(address(stakeRegistryProxy))
//                 ),
//                 address(stakeRegistryImpl)
//             );
//         }

//         {
//             IECDSAStakeRegistryTypes.StrategyParams[]
//                 memory quorumsStrategyParams = new IECDSAStakeRegistryTypes.StrategyParams[](
//                     numStrategies
//                 );

//             for (uint j = 0; j < numStrategies; j++) {
//                 quorumsStrategyParams[j] = IECDSAStakeRegistryTypes.StrategyParams({
//                     strategy: deployedStrategyArray[j],
//                     multiplier: 10_000
//                 });
//             }

//             IECDSAStakeRegistryTypes.Quorum memory quorum = IECDSAStakeRegistryTypes.Quorum(quorumsStrategyParams);

//             avsProxyAdmin.upgradeAndCall(
//                 TransparentUpgradeableProxy(
//                     payable(address(stakeRegistryProxy))
//                 ),
//                 address(stakeRegistryImpl),
//                 abi.encodeWithSelector(
//                     ECDSAStakeRegistry.initialize.selector,
//                     address(serviceManagerProxy),
//                     1,
//                     quorum
//                 )
//             );
//         }

//         serviceManagerImpl = new OrderServiceManager(
//             address(avsDirectory),
//             address(stakeRegistryProxy),
//             address(delegationManager)
//         );
//         // Third, upgrade the proxy contracts to use the correct implementation contracts and initialize them.
//         avsProxyAdmin.upgrade(
//             TransparentUpgradeableProxy(payable(address(serviceManagerProxy))),
//             address(serviceManagerImpl)
//         );

//         // WRITE JSON DATA
//         string memory parent_object = "parent object";

//         string memory deployed_addresses = "addresses";
//         vm.serializeAddress(
//             deployed_addresses,
//             "token",
//             address(token)
//         );
//         vm.serializeAddress(
//             deployed_addresses,
//             "erc20MockStrategy",
//             address(erc20MockStrategy)
//         );
//         vm.serializeAddress(
//             deployed_addresses,
//             "serviceManagerProxy",
//             address(serviceManagerProxy)
//         );
//         vm.serializeAddress(
//             deployed_addresses,
//             "serviceManagerImpl",
//             address(serviceManagerImpl)
//         );
//         vm.serializeAddress(
//             deployed_addresses,
//             "stakeRegistryProxy",
//             address(stakeRegistryProxy)
//         );

//         string memory deployed_addresses_output = vm.serializeAddress(
//             deployed_addresses,
//             "stakeRegistryImpl",
//             address(stakeRegistryImpl)
//         );

//         // serialize all the data
//         string memory finalJson = vm.serializeString(
//             parent_object,
//             deployed_addresses,
//             deployed_addresses_output
//         );

//         // Write the deployment output to a file
//         vm.writeFile("deployments/avs/31337.json", finalJson);
//     }

//     function verifyDeployment() internal view {
//         require(
//             avsDeployment.stakeRegistry != address(0), "StakeRegistry address cannot be zero"
//         );
//         require(
//             avsDeployment.orderServiceManager != address(0),
//             "HelloWorldServiceManager address cannot be zero"
//         );
//         require(avsDeployment.strategy != address(0), "Strategy address cannot be zero");
//         require(avsProxyAdmin != address(0), "ProxyAdmin address cannot be zero");
//         require(
//             coreDeployment.delegationManager != address(0),
//             "DelegationManager address cannot be zero"
//         );
//         require(coreDeployment.avsDirectory != address(0), "AVSDirectory address cannot be zero");
//     }
// }


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


        // StrategyManager stm = StrategyManager(coreDeployment.strategyManager);
        // stm.initialize(coreDeployment.strategyManager,coreDeployment.strategyFactory , 0);


        token = new ERC20Mock();
        // NOTE: if this fails, it's because the initialStrategyWhitelister is not set to be the StrategyFactory

        avsStrategy =
            IStrategy(StrategyFactory(coreDeployment.strategyFactory).deployNewStrategy(token));

        quorum.strategies.push(
            IECDSAStakeRegistryTypes.StrategyParams({
                strategy: avsStrategy,
                multiplier: 10_000
            })
        );

        token.mint(deployer, 2000);
        token.increaseAllowance(address(coreDeployment.strategyManager), 1000);
        StrategyManager(coreDeployment.strategyManager).depositIntoStrategy(
            avsStrategy, token, 1000
        );

        proxyAdmin = UpgradeableProxyLib.deployProxyAdmin();

        avsDeployment = AVSDeploymentLib.deployContracts(
            proxyAdmin, coreDeployment, quorum, rewardsInitiator, rewardsOwner
        );

        avsDeployment.strategy = address(avsStrategy);
        avsDeployment.token = address(token);

        vm.stopBroadcast();
        verifyDeployment();
        AVSDeploymentLib.writeDeploymentJson(avsDeployment);
    }

    function verifyDeployment() internal view {
        require(
            avsDeployment.stakeRegistry != address(0), "StakeRegistry address cannot be zero"
        );
        require(
            avsDeployment.orderServiceManager != address(0),
            "avsServiceManager address cannot be zero"
        );
        require(avsDeployment.strategy != address(0), "Strategy address cannot be zero");
        require(proxyAdmin != address(0), "ProxyAdmin address cannot be zero");
        require(
            coreDeployment.delegationManager != address(0),
            "DelegationManager address cannot be zero"
        );
        require(coreDeployment.avsDirectory != address(0), "avsDirectory address cannot be zero");
    }
}
