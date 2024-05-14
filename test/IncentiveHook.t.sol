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

contract TestIncentiveHook is Test, Deployers {
    using CurrencyLibrary for Currency;

    using PoolIdLibrary for PoolKey;

    MockERC20 token0;

    MockERC20 token1;

	MockERC20 rewardToken;

    Currency tokenCurrency0;

    Currency tokenCurrency1;

	Currency rewardCurrency;

    IncentiveHook hook;

    PoolManager mngr;

    PoolKey poolKey;

    PoolId poolId;

    function setUp() public {
        deployFreshManagerAndRouters();

        console.log("This test              address: %s", address(this));
        console.log("Manager                address: %s", address(manager));
        console.log("SwapRouter             address: %s", address(swapRouter));
        console.log("ModifyLiquidityRouter  address: %s", address(modifyLiquidityRouter));

        mngr = PoolManager(address(manager));

        token0 = new MockERC20("Test Token 1", "TST1", 18);
        tokenCurrency0 = Currency.wrap(address(token0));
        token0.mint(address(this), 1_000_000 ether);

        token1 = new MockERC20("Test Token 2", "TST2", 18);
        tokenCurrency1 = Currency.wrap(address(token1));
        token1.mint(address(this), 1_000_000 ether);

		rewardToken = new MockERC20("Reward Token", "REW", 18);
		rewardCurrency = Currency.wrap(address(rewardToken));
		rewardToken.mint(address(this), 50_000_000 ether);

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

        hook = new IncentiveHook{salt: salt}(manager);

        token0.approve(address(swapRouter), type(uint256).max);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);

        (poolKey, poolId) = initPool(
            tokenCurrency0,
            tokenCurrency1,
            hook,
            3000,
            Constants.SQRT_PRICE_1_1,
            ZERO_BYTES
        );
    }

    function test_updateRewards_shouldHaveUpdatedRecords() public {
        // increase allowance of rewardToken to hook
        rewardToken.approve(address(hook), type(uint256).max);

        // pick currency0, currency1, and rewardToken
        // update rewards to 100 ether for 500 blocks
        hook.updateRewards(poolId, rewardToken, 0.01 ether, 500);

        // check rewards record for this pool
        (uint256 amount, uint256 period) = hook.getRewards(poolId, rewardToken);
        assertEq(amount, 0.01 ether);
        assertEq(period, 500);
    }

    function test_updateRewards_shouldHaveUpdatedBalances() public {
        uint256 initialBalance = rewardToken.balanceOf(address(this));

        // increase allowance of rewardToken to hook
        rewardToken.approve(address(hook), type(uint256).max);

        hook.updateRewards(poolId, rewardToken, 0.01 ether, 500);

        // check this contract balance of rewardToken
        uint256 balance = rewardToken.balanceOf(address(this));
        assertEq(balance, initialBalance - 5 ether);

        // check hook's balance of rewardToken
        uint256 hookBalance = rewardToken.balanceOf(address(hook));
        assertEq(hookBalance, 5 ether);
    }

    function test_updateRewards_decreaseAmountPerBlock() public {
        uint256 initialBalance = rewardToken.balanceOf(address(this));

        rewardToken.approve(address(hook), type(uint256).max);

        hook.updateRewards(poolId, rewardToken, 0.003 ether, 1000);
        hook.updateRewards(poolId, rewardToken, 0.002 ether, 1000);

        (uint256 amountPerBlock, uint256 nrOfBlocks) = hook.getRewards(poolId, rewardToken);
        assertEq(amountPerBlock, 0.002 ether);
        assertEq(nrOfBlocks, 1000);

        // check caller's balance of rewardToken
        uint256 balance = rewardToken.balanceOf(address(this));
        assertEq(balance, initialBalance - 2 ether);

        // check hook's balance of rewardToken
        uint256 hookBalance = rewardToken.balanceOf(address(hook));
        assertEq(hookBalance, 2 ether);
    }

    function test_updateRewards_withdrawAllRewards() public {
        uint256 initialBalance = rewardToken.balanceOf(address(this));

        rewardToken.approve(address(hook), type(uint256).max);

        hook.updateRewards(poolId, rewardToken, 100 ether, 500);

        // withdraw all rewards
        hook.updateRewards(poolId, rewardToken, 0, 0);

        // check rewards record for this pair in both directions
        (uint256 amount, uint256 period) = hook.getRewards(poolId, rewardToken);
        assertEq(amount, 0);
        assertEq(period, 0);

        // check caller's balance of rewardToken
        uint256 balance = rewardToken.balanceOf(address(this));
        assertEq(balance, initialBalance);

        // check hook's balance of rewardToken
        uint256 hookBalance = rewardToken.balanceOf(address(hook));
        assertEq(hookBalance, 0);
    }

    ///////////////
    //// UTILS ///
    //////////////

    function log_feeGrowthGlobals(PoolKey memory _key) internal {
        (, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128, ) = mngr.pools(poolId);
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
        modifyLiquidityRouter.modifyLiquidity(poolKey, IPoolManager.ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1 ether,
            salt: 0
        }), ZERO_BYTES);

        // get fees accrued by user
        // uint256 feesAccruedUser = hook.getFeesAccrued(poolKey2.toId(), address(this), -60, 60);
        // assertEq(feesAccruedUser, 0);
    }

    function test_feesAccruedUser_1Position_NoWithdraws_NoPositionChanges_SomeFees() public {
        // Add some rewards
        rewardToken.approve(address(hook), type(uint256).max);
        hook.updateRewards(poolId, rewardToken, 0.001 ether, 1000);

        // few blocks passed after pool init
        vm.roll(10);

        // add liquidity
        modifyLiquidityRouter.modifyLiquidity(poolKey, IPoolManager.ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1 ether,
            salt: 0
        }), ZERO_BYTES);

        // swap generating fees
        swapRouter.swap(poolKey, IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -0.1 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        }), PoolSwapTest.TestSettings({
            settleUsingBurn: false,
            takeClaims: false
        }), ZERO_BYTES);

        // get fees accrued by user
        modifyLiquidityRouter.modifyLiquidity(poolKey, IPoolManager.ModifyLiquidityParams(-60, 60, 0 ether, 0), ZERO_BYTES, false, false);

        (uint256 fees0, uint256 fees1) = hook.getFeesAccrued(poolId, address(modifyLiquidityRouter), -60, 60, 0, 0, 0);
        console.log("fees0: %d", fees0);
        console.log("fees1: %d", fees1);

        (uint256 feesGlobal0, uint256 feesGlobal1) = hook.getFeesAccruedGlobal(poolId, 0, 0);
        console.log("feesGlobal0: %d", feesGlobal0);
        console.log("feesGlobal1: %d", feesGlobal1);

        IncentiveHook.PositionParams memory params = IncentiveHook.PositionParams({
            poolId: poolId,
            owner: address(modifyLiquidityRouter),
            tickLower: -60,
            tickUpper: 60,
            salt: 0
        });

        (uint256 rewards0, uint256 rewards1) = hook.calculateRewards(params, rewardToken);
        console.log("rewards0: %d", rewards0);
        console.log("rewards1: %d", rewards1);
    }

    function test_feesAccruedUser_1Position_OneWithdraw_NoPositionChanges() public {}

    function test_feesAccruedUser_1Position_NoWithdraw_OnePositionChange() public {}

    function test_feesAccruedUser_1Position_OneWithdraw_OnePositionChange() public {}

}
