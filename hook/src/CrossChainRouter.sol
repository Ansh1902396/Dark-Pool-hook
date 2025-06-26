//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {TransientStateLibrary} from "v4-core/libraries/TransientStateLibrary.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";



interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    
    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

// Sample crosschain order
struct CrossChainOrder {
    address routerContract;
    address swapper;
    address relayer;
    address recipient;
    address inputToken;
    address outputToken;
    uint256 inputAmount;
    uint256 relayerBondAmount;
    uint256 outputAmount;
    uint256 destinationChainId;
    uint256 nonce;
    uint256 deadline;
}

// Across SpokePool Interface
interface AcrossV3SpokePool {
    function depositV3(
        // address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        // uint256 inputAmount,
        // uint256 outputAmount,
        uint256 destinationChainId,
        // address exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityDeadline,
        bytes calldata message
    ) external;
}

// string constant ORDER_WITNESS_TYPESTRING = "CrossChainOrder witness)CrossChainOrder(address rfqContract,address swapper,address relayer,address recipient,address inputToken,address outputToken,uint256 inputAmount,uint256 relayerBondAmount,uint256 outputAmount,uint256 destinationChainId,uint256 nonce,uint256 deadline)";


 // Aim: Create a swap to call the across, and bridge the funds from it !!!
contract CrossChainRouter is Ownable{
    // How does the across help us

    error CallerNotManager();

    using SafeERC20 for IERC20;

    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using TransientStateLibrary for IPoolManager;

    AcrossV3SpokePool public immutable spokePool;



    IPoolManager public immutable manager;    // Custom manager to call the swap,

    struct CallbackData {
        address sender;
        SwapSettings settings;
        PoolKey key;
        SwapParams params;
        bytes hookData;
    }

    struct SwapSettings {
        bool bridgeTokens;
        address recipientAddress;
    }

    constructor (
        address _spokePool,
        IPoolManager _manager
    ) {
        manager = _manager;
        spokePool = AcrossV3SpokePool(_spokePool);
    }

    //1. Bridging funds to to the users on the other chain.

    function swap (
        PoolKey memory key,
        SwapParams memory params,
        SwapSettings memory settings,
        bytes memory hookData        
    ) external payable returns (BalanceDelta delta) {
        // Unlock the pool manager which will trigger a callback
        delta = abi.decode(
            manager.unlock(
                abi.encode(
                    CallbackData(msg.sender, settings, key, params, hookData)
                )
            ),
            (BalanceDelta)
        );

        // Send any ETH left over to the sender
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0)
            CurrencyLibrary.ADDRESS_ZERO.transfer(msg.sender, ethBalance);
    }


    function unlockCallback(
        bytes calldata rawData
    ) external returns (bytes memory) {
        if (msg.sender != address(manager)) revert CallerNotManager();
        CallbackData memory data = abi.decode(rawData, (CallbackData));

        // Call swap on the PM
        BalanceDelta delta = manager.swap(data.key, data.params, data.hookData);

        if (delta.amount0() < 0) {
            data.key.currency0.settle(
                manager,
                data.sender,
                uint256(int256(-delta.amount0())),
                false
            );
        }

        if (delta.amount1() < 0) {
            data.key.currency1.settle(
                manager,
                data.sender,
                uint256(int256(-delta.amount1())),
                false
            );
        }

        if (delta.amount0() > 0) {
            _take(
                data.key.currency0,
                data.key.currency1,
                data.settings.recipientAddress,
                uint256(int256(delta.amount0())),
                data.settings.bridgeTokens
            );
        }

        if (delta.amount1() > 0) {
            _take(
                data.key.currency1,
                data.key.currency0,
                data.settings.recipientAddress,
                uint256(int256(delta.amount1())),
                data.settings.bridgeTokens
            );
        }

        return abi.encode(delta);
    }

    function _take(
        Currency In_currency,
        Currency Out_currency,
        address recipient,
        uint256 amount,
        bool bridging
    ) internal {
        // If not bridging, just send the tokens to the swapper
        if (!bridging) {
            In_currency.take(manager, recipient, amount, false);
        } else {
            // If we are bridging, take tokens to the router and then bridge to the recipient address on the L2
            In_currency.take(manager, address(this), amount, false);

                address l1Token = Currency.unwrap(In_currency);
                address l2Token = Currency.unwrap(Out_currency);

                IERC20Minimal(l1Token).approve(
                    address(spokePool),
                    amount
                );
                // l1StandardBridge.depositERC20To(
                //     l1Token,
                //     l2Token,
                //     recipient,
                //     amount,
                //     0,
                //     ""
                // );

            // Fill deadline is arbitrarily set to 1 hour after initiation.
            uint256 fillDeadline = block.timestamp + 3600;


            // Call deposit to pass the order off to Across Settlement.
            // spokePool.depositV3(
            //     // order.swapper,
            //     recipient,
            //     In_currency,
            //     Out_currency,
            //     // order.inputAmount,
            //     // order.outputAmount,
            //     31337,
            //     // order.relayer,
            //     block.timestamp,
            //     fillDeadline, // 1 hour deadline
            //     fillDeadline, // Exclusivity for the entire fill period
            //     "" // No message
            // );
        }
    }
}