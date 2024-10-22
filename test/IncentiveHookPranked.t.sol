// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import {IncentiveHook} from "../src/IncentiveHook.sol";
import {HookMiner} from "./utils/HookMiner.sol";

contract TestIncentiveHookPranked is Test, Deployers {
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

    PoolKey poolKey2;

    address alice;

    address bob;

    address carol;

    function setUp() public {
        deployFreshManagerAndRouters();

        mngr = PoolManager(address(manager));

        alice = vm.addr(1);
        console.log("alice: ", alice);
        bob = vm.addr(2);
        console.log("bob:   ", bob);
        carol = vm.addr(3);
        console.log("carol: ", carol);

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);

        token0 = new MockERC20("Test Token 1", "TST1", 18);
        tokenCurrency0 = Currency.wrap(address(token0));
        token0.mint(address(this), 1_000_000 ether);

        token0.transfer(alice, 2000 ether);
        token0.transfer(bob, 2000 ether);
        token0.transfer(carol, 2000 ether);

        token1 = new MockERC20("Test Token 2", "TST2", 18);
        tokenCurrency1 = Currency.wrap(address(token1));
        token1.mint(address(this), 1_000_000 ether);

        token1.transfer(alice, 2000 ether);
        token1.transfer(bob, 2000 ether);
        token1.transfer(carol, 2000 ether);

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
            ethCurrency,
            tokenCurrency0,
            hook,
            3000,
            Constants.SQRT_PRICE_1_1,
            ZERO_BYTES
        );

        (poolKey2, ) = initPool(
            tokenCurrency0,
            tokenCurrency1,
            hook,
            3000,
            Constants.SQRT_PRICE_1_1,
            ZERO_BYTES
        );
    }

    ///////////////
    //// UTILS ///
    //////////////

    function log_feeGrowthGlobals(PoolKey memory _key) internal {
        (, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128, ) = mngr.pools(_key.toId());
        console.log("feeGrowthGlobal0X128: %d", feeGrowthGlobal0X128);
        console.log("feeGrowthGlobal1X128: %d", feeGrowthGlobal1X128);
    }

    ///////////////
    //// TESTS ///
    //////////////

    function test_feesAccruedUser_NoPosition() public {}

    function test_pranked_feesAccruedUser_1Position_NoWithdraws_NoPositionChanges_NoFees() public {
        // few blocks passed after pool init
        vm.roll(10);

        // add liquidity
        modifyLiquidityRouter.modifyLiquidity(poolKey2, IPoolManager.ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1 ether,
            salt: 0
        }), ZERO_BYTES);

        // get fees accrued by user
        // uint256 feesAccruedUser = hook.getFeesAccrued(poolKey2.toId(), address(this), -60, 60);
        // assertEq(feesAccruedUser, 0);
    }

    function test_pranked_feesAccruedUser_1Position_NoWithdraws_NoPositionChanges_SomeFees() public {
        // few blocks passed after pool init
        vm.roll(10);

        // add liquidity
        vm.prank(alice);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);
        modifyLiquidityRouter.modifyLiquidity(poolKey2, IPoolManager.ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1 ether,
            salt: 0
        }), ZERO_BYTES);

        // swap generating fees
        vm.prank(address(this));
        swapRouter.swap(poolKey2, IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -0.1 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        }), PoolSwapTest.TestSettings({
            settleUsingBurn: false,
            takeClaims: false
        }), ZERO_BYTES);

        log_feeGrowthGlobals(poolKey2);

        // get fees accrued by user
        vm.prank(alice);
        modifyLiquidityRouter.modifyLiquidity(poolKey2, IPoolManager.ModifyLiquidityParams(-60, 60, 0 ether, 0), ZERO_BYTES, false, false);
        (uint256 fees0, uint256 fees1) = hook.getFeesAccrued(poolKey2.toId(), alice, -60, 60, 0, 0, 0);
        console.log("fees0: %d", fees0);
        console.log("fees1: %d", fees1);
    }

    function test_feesAccruedUser_1Position_OneWithdraw_NoPositionChanges() public {}

    function test_feesAccruedUser_1Position_NoWithdraw_OnePositionChange() public {}

    function test_feesAccruedUser_1Position_OneWithdraw_OnePositionChange() public {}

}
