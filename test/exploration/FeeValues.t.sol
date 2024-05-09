// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

import {Strings} from "openzeppelin/utils/Strings.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Pool} from "v4-core/libraries/Pool.sol";
import {Position} from "v4-core/libraries/Position.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import {FixedPoint128} from "v4-core/libraries/FixedPoint128.sol";

import {IncentiveHook} from "../../src/IncentiveHook.sol";
import {HookMiner} from "../utils/HookMiner.sol";


contract FeeValues is Test, Deployers {
    using CurrencyLibrary for Currency;

    using PoolIdLibrary for PoolKey;

    MockERC20 token0;

    MockERC20 token1;

	MockERC20 rewardToken;

    Currency ethCurrency = Currency.wrap(address(0));

    Currency tokenCurrency0;

    Currency tokenCurrency1;

	Currency rewardCurrency;

    IncentiveHook hook;

    function setUp() public {
        deployFreshManagerAndRouters();

        token0 = new MockERC20("Test Token 1", "TST1", 18);
        tokenCurrency0 = Currency.wrap(address(token0));
        token0.mint(address(this), 1000 ether);
        token0.mint(address(1), 1000 ether);

        token1 = new MockERC20("Test Token 2", "TST2", 18);
        tokenCurrency1 = Currency.wrap(address(token1));
        token1.mint(address(this), 1000 ether);
        token1.mint(address(1), 1000 ether);

		rewardToken = new MockERC20("Reward Token", "REW", 18);
		rewardCurrency = Currency.wrap(address(rewardToken));
		rewardToken.mint(address(this), 1000 ether);

        uint160 flags = uint160(
            Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        (, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            0,
            type(IncentiveHook).creationCode,
            abi.encode(manager, "Points Token", "TEST_POINTS")
        );

        hook = new IncentiveHook{salt: salt}(
            manager,
            "Points Token",
            "TEST_POINTS"
        );

        token0.approve(address(swapRouter), type(uint256).max);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);

        (key, ) = initPool(
            ethCurrency,
            tokenCurrency0,
            hook,
            3000,
            SQRT_RATIO_1_1,
            ZERO_BYTES
        );
    }

    function log_feeGrowthGlobals(PoolKey memory _key) internal {
        (, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128, ) = manager.pools(_key.toId());
        console.log("feeGrowthGlobal0X128: %d", feeGrowthGlobal0X128);
        console.log("feeGrowthGlobal1X128: %d", feeGrowthGlobal1X128);
    }

    function log_feeGrowthInside(PoolKey memory _key, address _owner, int24 tickLower, int24 tickUpper) internal {
        Position.Info memory position = manager.getPosition(_key.toId(), address(this), tickLower, tickUpper);
        console.log("feeGrowthInside0LastX128: %d", position.feeGrowthInside0LastX128);
        console.log("feeGrowthInside1LastX128: %d", position.feeGrowthInside1LastX128);
        console.log("liquidity inside: %d", position.liquidity);
    }

    function log_Slot0(PoolKey memory _key) internal {
        (uint160 sqrtPriceX96, int24 tick, uint16 protocolFee, uint24 swapFee) = manager.getSlot0(_key.toId());
        console.log("sqrtPriceX96: %d", uint(sqrtPriceX96));
        console.logInt(tick);
        console.log("protocolFee: %d", protocolFee);
        console.log("swapFee: %d", swapFee);
    }

    function log_liquidity(PoolKey memory _key, address _owner, int24 tickLower, int24 tickUpper) internal {
        Position.Info memory position = manager.getPosition(_key.toId(), _owner, tickLower, tickUpper);
        console.log("liquidity owner: %d", position.liquidity);
    }

    function log_liquidity(PoolKey memory _key) internal {
        uint128 liquidity = manager.getLiquidity(_key.toId());
        console.log("liquidity: %d", liquidity);
    }

    function log_currentTck(PoolKey memory _key) internal {
        (, int24 tick, , ) = manager.getSlot0(_key.toId());
        console.logInt(tick);
    }

    function test_exploration_addLiquidityAndSwap() public {
        console.log("address(this)", address(this));

        console.log("INIT");
        log_currentTck(key);

        modifyLiquidityRouter.modifyLiquidity{value: 0.003 ether}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 1 ether
            }),
			ZERO_BYTES
        );
        console.log("AFTER ADD LIQUIDITY");
        log_currentTck(key);

        swapRouter.swap{value: 0.001 ether}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
            }),
            PoolSwapTest.TestSettings({
                withdrawTokens: true,
                settleUsingTransfer: true,
                currencyAlreadySent: false
            }),
			ZERO_BYTES
        );

        console.log("AFTER SWAP");
        log_currentTck(key);
        
        swapRouter.swap{value: 0.001 ether}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
            }),
            PoolSwapTest.TestSettings({
                withdrawTokens: true,
                settleUsingTransfer: true,
                currencyAlreadySent: false
            }),
			ZERO_BYTES
        );

        console.log("AFTER SWAP");
        log_currentTck(key);

        swapRouter.swap{value: 0.001 ether}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: false,
                amountSpecified: 0.001 ether,
                sqrtPriceLimitX96: TickMath.MAX_SQRT_RATIO - 1
            }),
            PoolSwapTest.TestSettings({
                withdrawTokens: true,
                settleUsingTransfer: true,
                currencyAlreadySent: false
            }),
			ZERO_BYTES
        );

        console.log("AFTER SWAP");
        log_currentTck(key);

        log_liquidity(key, address(this), -60, 60);
        log_feeGrowthGlobals(key);
        log_feeGrowthInside(key, address(this), -60, 60);

        int256 delta = manager.currencyDelta(address(this), tokenCurrency0);
        console.logInt(delta);
    }


}