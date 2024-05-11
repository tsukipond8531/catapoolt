// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
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

contract TestIncentiveHook is Test, Deployers {
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

    function setUp() public {
        deployFreshManagerAndRouters();

        mngr = PoolManager(address(manager));

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

        (poolKey2, ) = initPool(
            tokenCurrency0,
            tokenCurrency1,
            hook,
            3000,
            SQRT_RATIO_1_1,
            ZERO_BYTES
        );
    }

    function test_addLiquidityAndSwap() public {
        modifyLiquidityRouter.modifyLiquidity{value: 0.003 ether}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 1 ether
            }),
			ZERO_BYTES
        );

        swapRouter.swap{value: 0.001 ether}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
            }),
            PoolSwapTest.TestSettings({
                // withdrawTokens: true,
                // settleUsingTransfer: true,
                // currencyAlreadySent: false
                settleUsingBurn: false,
                takeClaims: false
            }),
			ZERO_BYTES
        );
    }

    // TODO
    // function test_updateRewards_wrongHookAddress() public {
    //     PoolKey memory wrongHook = PoolKey({
    //         currency0: key.currency0,
    //         currency1: key.currency1,
    //         fee: key.fee,
    //         tickSpacing: key.tickSpacing,
    //         hooks: IHooks(address(123))
    //     });

    //     try
    //         hook.updateRewards(wrongHook.toId(), rewardToken, 100 ether, 500)
    //     {
    //         fail();
    //     } catch Error(string memory reason) {
    //         assertEq(reason, "Hook not attached to pool");
    //     }
    // }

    function test_updateRewards_shouldHaveUpdatedRecords() public {
        // increase allowance of rewardToken to hook
        rewardToken.approve(address(hook), type(uint256).max);

        // pick currency0, currency1, and rewardToken
        // update rewards to 100 ether for 500 blocks
        hook.updateRewards(key.toId(), rewardToken, 100 ether, 500);

        // check rewards record for this pool
        (uint256 amount, uint256 period) = hook.getRewards(key.toId(), rewardToken);
        assertEq(amount, 100 ether);
        assertEq(period, 500);
    }

    function test_updateRewards_shouldHaveUpdatedBalances() public {
        // increase allowance of rewardToken to hook
        rewardToken.approve(address(hook), type(uint256).max);

        hook.updateRewards(key.toId(), rewardToken, 100 ether, 500);

        // check this contract balance of rewardToken
        uint256 balance = rewardToken.balanceOf(address(this));
        assertEq(balance, 900 ether);

        // check hook's balance of rewardToken
        uint256 hookBalance = rewardToken.balanceOf(address(hook));
        assertEq(hookBalance, 100 ether);
    }

    function test_updateRewards_decreaseAmount() public {
        rewardToken.approve(address(hook), type(uint256).max);

        hook.updateRewards(key.toId(), rewardToken, 300 ether, 500);
        hook.updateRewards(key.toId(), rewardToken, 200 ether, 500);

        (uint256 amount, uint256 period) = hook.getRewards(key.toId(), rewardToken);
        assertEq(amount, 200 ether);
        assertEq(period, 500);

        // check caller's balance of rewardToken
        uint256 balance = rewardToken.balanceOf(address(this));
        assertEq(balance, 800 ether);

        // check hook's balance of rewardToken
        uint256 hookBalance = rewardToken.balanceOf(address(hook));
        assertEq(hookBalance, 200 ether);
    }

    function test_updateRewards_withdrawAllRewards() public {
        rewardToken.approve(address(hook), type(uint256).max);

        hook.updateRewards(key.toId(), rewardToken, 100 ether, 500);

        // withdraw all rewards
        hook.updateRewards(key.toId(), rewardToken, 0, 0);

        // check rewards record for this pair in both directions
        (uint256 amount, uint256 period) = hook.getRewards(key.toId(), rewardToken);
        assertEq(amount, 0);
        assertEq(period, 0);

        // check caller's balance of rewardToken
        uint256 balance = rewardToken.balanceOf(address(this));
        assertEq(balance, 1000 ether);

        // check hook's balance of rewardToken
        uint256 hookBalance = rewardToken.balanceOf(address(hook));
        assertEq(hookBalance, 0);
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

    function test_feesAccruedUser_1Position_NoWithdraws_NoPositionChanges_NoFees() public {
        // few blocks passed after pool init
        vm.roll(10);

        // add liquidity
        modifyLiquidityRouter.modifyLiquidity(poolKey2, IPoolManager.ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1 ether
        }), ZERO_BYTES);

        // get fees accrued by user
        uint256 feesAccruedUser = hook.getFeesAccrued(address(this), poolKey2.toId(), rewardToken);
        assertEq(feesAccruedUser, 0);
    }

    function test_feesAccruedUser_1Position_NoWithdraws_NoPositionChanges_SomeFees() public {
        // few blocks passed after pool init
        vm.roll(10);

        // add liquidity
        modifyLiquidityRouter.modifyLiquidity(poolKey2, IPoolManager.ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1 ether
        }), ZERO_BYTES);

        // swap generating fees
        swapRouter.swap(poolKey2, IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -0.1 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
        }), PoolSwapTest.TestSettings({
            settleUsingBurn: false,
            takeClaims: false
        }), ZERO_BYTES);

        log_feeGrowthGlobals(poolKey2);

        // get fees accrued by user
        uint256 feesAccruedUser = hook.getFeesAccrued(address(this), poolKey2.toId(), rewardToken);
        assertNotEq(feesAccruedUser, 0);
    }

    function test_feesAccruedUser_1Position_OneWithdraw_NoPositionChanges() public {}

    function test_feesAccruedUser_1Position_NoWithdraw_OnePositionChange() public {}

    function test_feesAccruedUser_1Position_OneWithdraw_OnePositionChange() public {}

}
