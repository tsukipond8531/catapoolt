// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import {IncentiveHook} from "../src/IncentiveHook.sol";
import {HookMiner} from "./utils/HookMiner.sol";

contract TestIncentiveHook is Test, Deployers {
    using CurrencyLibrary for Currency;

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
                withdrawTokens: true,
                settleUsingTransfer: true,
                currencyAlreadySent: false
            }),
			ZERO_BYTES
        );
    }

    function test_updateRewards_shouldHaveUpdatedRecords() public {
        // increase allowance of rewardToken to hook
        rewardToken.approve(address(hook), type(uint256).max);

        // pick currency0, currency1, and rewardToken
        // update rewards to 100 ether for 500 blocks
        hook.updateRewards(tokenCurrency0, tokenCurrency1, rewardToken, 100 ether, 500);

        // check rewards record for this pair in both directions
        (uint256 amount1, uint256 period1) = hook.getRewards(tokenCurrency0, tokenCurrency1, rewardToken);
        assertEq(amount1, 100 ether);
        assertEq(period1, 500);

        (uint256 amount2, uint256 period2) = hook.getRewards(tokenCurrency1, tokenCurrency0, rewardToken);
        assertEq(amount2, 100 ether);
        assertEq(period2, 500);
    }

    function test_updateRewards_shouldHaveUpdatedBalances() public {
        // increase allowance of rewardToken to hook
        rewardToken.approve(address(hook), type(uint256).max);

        hook.updateRewards(tokenCurrency0, tokenCurrency1, rewardToken, 100 ether, 500);

        // check this contract balance of rewardToken
        uint256 balance = rewardToken.balanceOf(address(this));
        assertEq(balance, 900 ether);

        // check hook's balance of rewardToken
        uint256 hookBalance = rewardToken.balanceOf(address(hook));
        assertEq(hookBalance, 100 ether);
    }

    function test_updateRewards_decreaseAmount() public {
        rewardToken.approve(address(hook), type(uint256).max);

        hook.updateRewards(tokenCurrency0, tokenCurrency1, rewardToken, 300 ether, 500);
        hook.updateRewards(tokenCurrency0, tokenCurrency1, rewardToken, 200 ether, 500);

        (uint256 amount1, uint256 period1) = hook.getRewards(tokenCurrency0, tokenCurrency1, rewardToken);
        assertEq(amount1, 200 ether);
        assertEq(period1, 500);

        // check caller's balance of rewardToken
        uint256 balance = rewardToken.balanceOf(address(this));
        assertEq(balance, 800 ether);

        // check hook's balance of rewardToken
        uint256 hookBalance = rewardToken.balanceOf(address(hook));
        assertEq(hookBalance, 200 ether);
    }

    function test_updateRewards_withdrawAllRewards() public {
        rewardToken.approve(address(hook), type(uint256).max);

        hook.updateRewards(tokenCurrency0, tokenCurrency1, rewardToken, 100 ether, 500);

        // withdraw all rewards
        hook.updateRewards(tokenCurrency0, tokenCurrency1, rewardToken, 0, 0);

        // check rewards record for this pair in both directions
        (uint256 amount1, uint256 period1) = hook.getRewards(tokenCurrency0, tokenCurrency1, rewardToken);
        assertEq(amount1, 0);
        assertEq(period1, 0);

        (uint256 amount2, uint256 period2) = hook.getRewards(tokenCurrency1, tokenCurrency0, rewardToken);
        assertEq(amount2, 0);
        assertEq(period2, 0);

        // check caller's balance of rewardToken
        uint256 balance = rewardToken.balanceOf(address(this));
        assertEq(balance, 1000 ether);

        // check hook's balance of rewardToken
        uint256 hookBalance = rewardToken.balanceOf(address(hook));
        assertEq(hookBalance, 0);
    }

	function test_distribution() public {
		// add rewards
		hook.updateRewards(ethCurrency, tokenCurrency0, rewardToken, 100 ether, 100);

		// add liquidity
        modifyLiquidityRouter.modifyLiquidity{value: 0.003 ether}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 1 ether
            }),
			ZERO_BYTES
        );

		// wait for a block
        vm.roll(2);
        console.log("Block number: %d", block.number);

		// check rewards of this account
        uint256 rewards = hook.getRewards(rewardToken, address(this));
        assertEq(rewards, 1 ether);
	}
}
