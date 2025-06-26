// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {V4Quoter} from "v4-periphery/src/lens/V4Quoter.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import {DarkCoWHook} from "../src/DarkCoWHook.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";


import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/StdCheats.sol";
import "forge-std/StdUtils.sol";

contract HookDeployer is Script, StdCheats {
    using CurrencyLibrary for Currency;

    IPoolManager manager;
    PoolModifyLiquidityTest lpRouter;
    PoolSwapTest swapRouter;
    V4Quoter quoter;

    Currency token0;
    Currency token1;
    Currency token2;

    DarkCoWHook hook;
    uint160 constant SQRT_PRICE_1_4 = 158456325028528675187087900672;
    uint160 constant SQRT_PRICE_1_80 = 707906546557329983810457536050;    // 1:80 ratio
    uint160 constant SQRT_PRICE_1_25 = 395742478843881893883567226157;    // 1:25 ratio
    
    // address serviceManager=0x5eb3bc0a489c5a8288765d2336659ebca68fcd00;


    function run(address serviceManager) public {
        vm.createSelectFork("http://localhost:8545");

        vm.startBroadcast();
        deployFreshManagerAndRouters();
        quoter = new V4Quoter(manager);
        deployMintAndApprove2Currencies();

        deployHookToAnvil(serviceManager);

        initPoolAndAddLiquidity();
        initToken2PoolsAndAddLiquidity();
        vm.stopBroadcast();

        // WRITE JSON DATA
        string memory parent_object = "parent object";
        string memory deployed_addresses = "addresses";
        vm.serializeAddress(
            deployed_addresses,
            "poolManager",
            address(manager)
        );
        vm.serializeAddress(deployed_addresses, "quoter", address(quoter));
        vm.serializeAddress(deployed_addresses, "lpRouter", address(lpRouter));
        vm.serializeAddress(
            deployed_addresses,
            "swapRouter",
            address(swapRouter)
        );
        vm.serializeAddress(
            deployed_addresses,
            "token0",
            Currency.unwrap(token0)
        );
        vm.serializeAddress(
            deployed_addresses,
            "token1",
            Currency.unwrap(token1)
        );
        vm.serializeAddress(
            deployed_addresses,
            "token2",
            Currency.unwrap(token2)
        );
        string memory deployed_addresses_output = vm.serializeAddress(
            deployed_addresses,
            "hook",
            address(hook)
        );

        string memory final_json = vm.serializeString(
            parent_object,
            deployed_addresses,
            deployed_addresses_output
        );
        string memory outputDir = string.concat(
            vm.projectRoot(),
            "/script/output/"
        );

        
        string memory chainDir = string.concat(vm.toString(block.chainid), "/");
        string memory outputFilePath = string.concat(
            outputDir,
            chainDir,
            "darkCoWHook",
            ".json"
        );
        vm.writeJson(final_json, outputFilePath);
    }

    function deployFreshManagerAndRouters() internal {
        manager = IPoolManager(address(new PoolManager(msg.sender)));

        lpRouter = new PoolModifyLiquidityTest(manager);
        swapRouter = new PoolSwapTest(manager);
    }

    function deployMintAndApprove2Currencies() internal {
        MockERC20 tokenA = new MockERC20("MockA", "A", 18);
        MockERC20 tokenB = new MockERC20("MockB", "B", 18);
        MockERC20 tokenC = new MockERC20("Token2", "TK2", 18);
        if (uint160(address(tokenA)) < uint160(address(tokenB))) {
            token0 = Currency.wrap(address(tokenA));
            token1 = Currency.wrap(address(tokenB));
        } else {
            token0 = Currency.wrap(address(tokenB));
            token1 = Currency.wrap(address(tokenA));
        }
        token2 = Currency.wrap(address(tokenC));

        tokenA.mint(msg.sender, 100_000 ether);
        tokenB.mint(msg.sender, 100_000 ether);
        tokenC.mint(msg.sender, 100_000 ether);

        tokenA.approve(address(lpRouter), type(uint256).max);
        tokenB.approve(address(lpRouter), type(uint256).max);
        tokenC.approve(address(lpRouter), type(uint256).max);
        tokenA.approve(address(swapRouter), type(uint256).max);
        tokenB.approve(address(swapRouter), type(uint256).max);
        tokenC.approve(address(swapRouter), type(uint256).max);
    }

    function deployHookToAnvil(address serviceManager) internal {
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );

        

        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_FACTORY,
            flags,
            type(DarkCoWHook).creationCode,
            abi.encode(address(manager) , serviceManager)
        );
        hook = new DarkCoWHook{salt: salt}(manager, serviceManager);
        require(address(hook) == hookAddress, "hook: hook address mismatch");
        
        // Set the hook address in the service manager
    }

    function initPoolAndAddLiquidity() internal {
        PoolKey memory poolKey = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 120,
            hooks: hook
        });
        manager.initialize(
            poolKey,
            SQRT_PRICE_1_4 // 1 A = 4 B roughly
        );

        lpRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(120),
                tickUpper: TickMath.maxUsableTick(120),
                liquidityDelta: 2000 ether,
                salt: bytes32(0)
            }),
            new bytes(0)
        );

        swapRouter.swap(
            poolKey,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -1 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            new bytes(0)
        );
    }

    function initToken2PoolsAndAddLiquidity() internal {
        // Initialize token2-token1 pool (ensuring correct order)
        PoolKey memory poolKey1 = PoolKey({
            currency0: uint160(Currency.unwrap(token2)) < uint160(Currency.unwrap(token1)) ? token2 : token1,
            currency1: uint160(Currency.unwrap(token2)) < uint160(Currency.unwrap(token1)) ? token1 : token2,
            fee: 3000,
            tickSpacing: 120,
            hooks: hook
        });
        manager.initialize(poolKey1, SQRT_PRICE_1_80);

        lpRouter.modifyLiquidity(
            poolKey1,
            ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(120),
                tickUpper: TickMath.maxUsableTick(120),
                liquidityDelta: 2000 ether,
                salt: bytes32(0)
            }),
            new bytes(0)
        );

        // Initialize token2-token0 pool (ensuring correct order)
        PoolKey memory poolKey2 = PoolKey({
            currency0: uint160(Currency.unwrap(token2)) < uint160(Currency.unwrap(token0)) ? token2 : token0,
            currency1: uint160(Currency.unwrap(token2)) < uint160(Currency.unwrap(token0)) ? token0 : token2,
            fee: 3000,
            tickSpacing: 120,
            hooks: hook
        });
        manager.initialize(poolKey2, SQRT_PRICE_1_25);

        lpRouter.modifyLiquidity(
            poolKey2,
            ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(120),
                tickUpper: TickMath.maxUsableTick(120),
                liquidityDelta: 2000 ether,
                salt: bytes32(0)
            }),
            new bytes(0)
        );
    }
}
