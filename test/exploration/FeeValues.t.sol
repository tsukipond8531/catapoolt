// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

import {Strings} from "openzeppelin/utils/Strings.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
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

    PoolManager mngr;

    address alice;

    address bob;

    address carol;

    function setUp() public {
        deployFreshManagerAndRouters();

        mngr = PoolManager(address(manager));

        uint256 rootBalance = ethCurrency.balanceOf(address(this)) / 1 ether;
        console.log("address(this) \t\t", address(this));

        alice = vm.addr(1);
        console.log("alice \t\t", alice);
        bob = vm.addr(2);
        console.log("bob \t\t", bob);
        carol = vm.addr(3);
        console.log("carol \t\t", carol);

        console.log("router address \t\t", address(modifyLiquidityRouter));

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);

        token0 = new MockERC20("Test Token 1", "TST1", 18);
        tokenCurrency0 = Currency.wrap(address(token0));
        token0.mint(address(this), 10000 ether);
        token0.mint(address(1), 10000 ether);

        token0.transfer(alice, 2000 ether);
        token0.transfer(bob, 2000 ether);
        token0.transfer(carol, 2000 ether);

        token1 = new MockERC20("Test Token 2", "TST2", 18);
        tokenCurrency1 = Currency.wrap(address(token1));
        token1.mint(address(this), 10000 ether);
        token1.mint(address(1), 10000 ether);

        token1.transfer(alice, 2000 ether);
        token1.transfer(bob, 2000 ether);
        token1.transfer(carol, 2000 ether);

		rewardToken = new MockERC20("Reward Token", "REW", 18);
		rewardCurrency = Currency.wrap(address(rewardToken));
		rewardToken.mint(address(this), 10000 ether);

        uint160 flags = uint160(
            Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        (, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            0,
            type(IncentiveHook).creationCode,
            abi.encode(manager)
        );

        hook = new IncentiveHook{salt: salt}(
            manager
        );

        token0.approve(address(swapRouter), type(uint256).max);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);

        (key, ) = initPool(
            tokenCurrency0,
            tokenCurrency1,
            hook,
            3000,
            Constants.SQRT_PRICE_1_1,
            ZERO_BYTES
        );
    }

    function log_feeGrowthGlobals(PoolKey memory _key) internal {
        (, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128, ) = mngr.pools(_key.toId());
        console.log("feeGrowthGlobal0X128: %d", feeGrowthGlobal0X128);
        console.log("feeGrowthGlobal1X128: %d", feeGrowthGlobal1X128);
    }

    function log_feeGrowthInside(PoolKey memory _key, address _owner, int24 tickLower, int24 tickUpper) internal {
        Position.Info memory position = manager.getPosition(_key.toId(), _owner, tickLower, tickUpper, 0);
        console.log("feeGrowthInside0LastX128: %d", position.feeGrowthInside0LastX128);
        console.log("feeGrowthInside1LastX128: %d", position.feeGrowthInside1LastX128);
        console.log("liquidity inside: %d", position.liquidity);
    }

    function log_Slot0(PoolKey memory _key) internal {
        (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) = manager.getSlot0(_key.toId());
        console.log("sqrtPriceX96: %d", uint(sqrtPriceX96));
        console.logInt(tick);
        console.log("protocolFee: %d", protocolFee);
        console.log("lpFee: %d", lpFee);
    }

    function log_liquidity(PoolKey memory _key, address _owner, int24 tickLower, int24 tickUpper) internal {
        Position.Info memory position = manager.getPosition(_key.toId(), _owner, tickLower, tickUpper, 0);
        console.log("liquidity owner: %d", position.liquidity);
    }

    function log_liquidity(PoolKey memory _key) internal {
        uint128 liquidity = manager.getLiquidity(_key.toId());
        console.log("Pool liquidity: %d", liquidity);
    }

    function log_currentTck(PoolKey memory _key) internal {
        (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) = manager.getSlot0(_key.toId());
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
                liquidityDelta: 1 ether,
                salt: 0
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
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false}),
			ZERO_BYTES
        );

        console.log("AFTER SWAP");
        log_currentTck(key);
        
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(-60, 60, 0 ether, 0), ZERO_BYTES, true, true);

        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(-60, 60, -1 ether, 0), ZERO_BYTES, true, true);

        console.log("AFTER SWAP");
        log_currentTck(key);

        // log_liquidity(key, address(this), -60, 60);
        log_feeGrowthGlobals(key);
        log_feeGrowthInside(key, address(this), -60, 60);

        int256 delta = manager.currencyDelta(address(this), tokenCurrency0);
        console.logInt(delta);
    }


    function test_exploration_feeDistribution() public {
        // Alice adds liquidity
        vm.prank(alice);
        console.log("alice msg.sender", msg.sender);

        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 1000 ether,
                salt: 0
            }),
            ZERO_BYTES);

        // Bob adds liquidity
        vm.prank(bob);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 500 ether,
                salt: 0
            }),
            ZERO_BYTES);

        // Swap
        vm.prank(address(this));
        swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: 0.1 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false}),
			ZERO_BYTES
        );

        // Alice log
        vm.prank(alice);
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(-60, 60, 0 ether, 0), ZERO_BYTES, false, false);

        console.log("\nAlice log");
        log_feeGrowthInside(key, alice, -60, 60);

        // // Bob log
        vm.prank(bob);
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(-60, 60, 0 ether, 0), ZERO_BYTES, true, true);

        console.log("\nBob log");
        log_feeGrowthInside(key, alice, -60, 60);

        // General log
        vm.prank(address(this));

        console.log("\nGeneral log");
        log_feeGrowthGlobals(key);
    }

    function test_inCircles() public {
        // Alice -> Bob
        vm.prank(alice);
        tokenCurrency0.transfer(bob, 100 ether);
        console.log("\nAlice", tokenCurrency0.balanceOf(alice));
        console.log("Bob", tokenCurrency0.balanceOf(bob));
        console.log("Carol", tokenCurrency0.balanceOf(carol));

        // Bob -> Carol
        vm.prank(bob);
        tokenCurrency0.transfer(carol, 100 ether);
        console.log("\nAlice", tokenCurrency0.balanceOf(alice));
        console.log("Bob", tokenCurrency0.balanceOf(bob));
        console.log("Carol", tokenCurrency0.balanceOf(carol));

        // Carol -> Alice
        vm.prank(carol);
        tokenCurrency0.transfer(alice, 100 ether);
        console.log("\nAlice", tokenCurrency0.balanceOf(alice));
        console.log("Bob", tokenCurrency0.balanceOf(bob));
        console.log("Carol", tokenCurrency0.balanceOf(carol));
    }
}