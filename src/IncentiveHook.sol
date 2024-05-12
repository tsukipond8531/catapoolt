// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Position} from "v4-core/libraries/Position.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";

import {FixedPoint128} from "v4-core/libraries/FixedPoint128.sol";

import "forge-std/console.sol";

contract IncentiveHook is BaseHook {
    using CurrencyLibrary for Currency;
 
    using BalanceDeltaLibrary for BalanceDelta;

    constructor(
        IPoolManager _manager,
        string memory _name,
        string memory _symbol
    ) BaseHook(_manager) {}

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: true,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function beforeInitialize(
        address,
        PoolKey calldata,
        uint160,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.beforeInitialize.selector;
    }

    function afterInitialize(
        address,
        PoolKey calldata poolKey,
        uint160,
        int24,
        bytes calldata
    ) external override returns (bytes4) {
        poolKeys[poolKey.toId()] = poolKey;
        return this.afterInitialize.selector;
    }

    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.beforeAddLiquidity.selector;
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.beforeRemoveLiquidity.selector;
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata poolKey,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta delta,
        bytes calldata
    ) external override returns (bytes4, BalanceDelta) {
        userPools[msg.sender].push(poolKey.toId());
        return (this.afterAddLiquidity.selector, delta);
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta delta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        return (this.afterRemoveLiquidity.selector, delta);
    }

    function beforeSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        bytes calldata
    ) external pure override returns (bytes4, int128) {
        return (this.beforeSwap.selector, 0);
    }

    function afterSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, int128) {
        return (this.afterSwap.selector, 0);
    }

    function beforeDonate(
        address,
        PoolKey calldata,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.beforeDonate.selector;
    }

    function afterDonate(
        address,
        PoolKey calldata,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.afterDonate.selector;
    }

    ////////////////////////////////
    using PoolIdLibrary for PoolKey;

    mapping(PoolId => PoolKey) public poolKeys;

    mapping(PoolId => mapping(ERC20 => Values)) public rewards;

    mapping(address => PoolId[]) public userPools;

    struct Values {
        uint256 amount;
        uint256 period;
    }

    function updateRewards(
        PoolId poolId,
        ERC20 rewardToken,
        uint256 newAmount,
        uint256 period
    ) external {
        // TODO check that the pool has this hook attached
        // require(address(poolKeys[poolId].hooks) == address(this), "Hook not attached to pool");
        
        uint256 currentBalance = rewards[poolId][rewardToken].amount;

        if (currentBalance < newAmount) {
            uint256 needed = newAmount - currentBalance;
            require(rewardToken.allowance(msg.sender, address(this)) >= needed, "Insufficient allowance");
            rewardToken.transferFrom(msg.sender, address(this), needed);
        } else if (currentBalance > newAmount) {
            uint256 excess = currentBalance - newAmount;
            rewardToken.transfer(msg.sender, excess);
        }

        rewards[poolId][rewardToken] = Values(newAmount, period);
    }

    function getRewards(
        PoolId poolId,
        ERC20 rewardToken
    ) external view returns (uint256, uint256) {
        return (rewards[poolId][rewardToken].amount, rewards[poolId][rewardToken].period);
    }

    function calculateRewards(
        PoolId poolId,
        address owner,
        int24 tickLower, 
        int24 tickUpper,
        bytes32 salt,
        ERC20 rewardToken
    ) external view returns (uint256 userRewards) {
        // TODO
        uint256 feeGrowthInside0X128LastWithdrawal = 0;
        // TODO
        uint256 feeGrowthInside1X128LastWithdrawal = 0;

        // fees accrued by the user since the last reward withdrawal
        (uint256 fees0, uint256 fees1) = getFeesAccrued(poolId, owner, tickLower, tickUpper, salt, feeGrowthInside0X128LastWithdrawal, feeGrowthInside1X128LastWithdrawal);

        // fees accrued by all the users since the last reward withdrawal
        uint256 feesAccruedTotal = 1;

        // amount of total rewards since the last withdrawal of the user (nr of blocks * reward per block)
        uint256 blocksPassed = 1;
        uint256 rewardPerBlock = 1;
        uint256 totalRewards = blocksPassed * rewardPerBlock;

        // amount of rewards the user can claim
        // userRewards = FullMath.mulDiv(feesAccruedUser, totalRewards, feesAccruedTotal);

        // update variables
        // feesAccruedUser = 1;
        feesAccruedTotal = 1;
        blocksPassed = 1;
    }

    function getFeesAccrued(
        PoolId poolId,
        address owner,
        int24 tickLower, 
        int24 tickUpper,
        bytes32 salt,
        uint256 feeGrowthInside0X128LastWithdrawal,
        uint256 feeGrowthInside1X128LastWithdrawal
    ) public view returns (uint256 fees0, uint256 fees1) {
        Position.Info memory position = poolManager.getPosition(poolId, owner, tickLower, tickUpper, 0);

        unchecked {
            fees0 = FullMath.mulDiv(position.feeGrowthInside0LastX128 - feeGrowthInside0X128LastWithdrawal, position.liquidity, FixedPoint128.Q128);
            fees1 = FullMath.mulDiv(position.feeGrowthInside1LastX128 - feeGrowthInside1X128LastWithdrawal, position.liquidity, FixedPoint128.Q128);
        }
    }
}
