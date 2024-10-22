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
        IPoolManager _manager
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

    mapping(bytes32 => WithdrawalSnapshot) public lastWithdrawals;

    struct Values {
        uint256 amountPerBlock;
        uint256 nrOfBlocks;
    }

    struct WithdrawalSnapshot {
        uint256 feeGrowthInside0X128;
        uint256 feeGrowthInside1X128;
        uint256 feesGrowthGlobal0X128;
        uint256 feesGrowthGlobal1X128;
        uint256 blockNumber;
    }

    function updateRewards(
        PoolId poolId,
        ERC20 rewardToken,
        uint256 newAmountPerBlock,
        uint256 newNrOfBlocks
    ) external {
        // TODO check that the pool has this hook attached
        // require(address(poolKeys[poolId].hooks) == address(this), "Hook not attached to pool");
        
        uint256 currentBalance = rewards[poolId][rewardToken].amountPerBlock * rewards[poolId][rewardToken].nrOfBlocks;
        uint256 newAmount = newAmountPerBlock * newNrOfBlocks;

        if (currentBalance < newAmount) {
            uint256 needed = newAmount - currentBalance;
            require(rewardToken.allowance(msg.sender, address(this)) >= needed, "Insufficient allowance");
            rewardToken.transferFrom(msg.sender, address(this), needed);
        } else if (currentBalance > newAmount) {
            uint256 excess = currentBalance - newAmount;
            rewardToken.transfer(msg.sender, excess);
        }

        rewards[poolId][rewardToken] = Values(newAmountPerBlock, newNrOfBlocks);
    }

    function getRewards(
        PoolId poolId,
        ERC20 rewardToken
    ) external view returns (uint256, uint256) {
        return (rewards[poolId][rewardToken].amountPerBlock, rewards[poolId][rewardToken].nrOfBlocks);
    }

    function toPositionId(PoolId poolId, address owner, int24 tickLower, int24 tickUpper, bytes32 salt) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(poolId, owner, tickLower, tickUpper, salt));
    }

    struct PositionParams {
        PoolId poolId;
        address owner;
        int24 tickLower;
        int24 tickUpper;
        bytes32 salt;
    }

    function calculateRewards(
        PositionParams memory params,
        ERC20 rewardToken
    ) public view returns (uint256 rewards0, uint256 rewards1) {
        // Create position ID using the struct
        bytes32 positionId = toPositionId(params.poolId, params.owner, params.tickLower, params.tickUpper, params.salt);

        // Access withdrawal data
        WithdrawalSnapshot memory lastWithdrawal = lastWithdrawals[positionId];

        // Calculate fees accrued by the user since the last reward withdrawal
        (uint256 fees0, uint256 fees1) = getFeesAccrued(
            params.poolId, params.owner, params.tickLower, params.tickUpper, params.salt,
            lastWithdrawal.feeGrowthInside0X128, lastWithdrawal.feeGrowthInside1X128
        );

        // Calculate fees accrued by all the users since the last reward withdrawal
        (uint256 feesGlobal0, uint256 feesGlobal1) = getFeesAccruedGlobal(
            params.poolId, lastWithdrawal.feesGrowthGlobal0X128, lastWithdrawal.feesGrowthGlobal1X128
        );

        // Calculate total rewards since the last withdrawal of the user
        uint256 blocksPassed = block.number - lastWithdrawal.blockNumber;
        uint256 rewardPerBlock = rewards[params.poolId][rewardToken].amountPerBlock;
        uint256 totalRewards = blocksPassed * rewardPerBlock;

        // Rewards are split equally between the two swap directions
        uint256 totalRewardsPerDirection = totalRewards / 2;

        // Calculate the amount of rewards the user can claim
        rewards0 = (feesGlobal0 == 0) ? 0 : FullMath.mulDiv(fees0, totalRewardsPerDirection, feesGlobal0);
        rewards1 = (feesGlobal1 == 0) ? 0 : FullMath.mulDiv(fees1, totalRewardsPerDirection, feesGlobal1);
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
        Position.Info memory position = poolManager.getPosition(poolId, owner, tickLower, tickUpper, salt);

        unchecked {
            fees0 = position.feeGrowthInside0LastX128 - feeGrowthInside0X128LastWithdrawal;
            fees1 = position.feeGrowthInside1LastX128 - feeGrowthInside1X128LastWithdrawal;
        }
    }

    function getFeesAccruedGlobal(
        PoolId poolId,
        uint256 feesGrowthGlobal0X128LastWithdrawal,
        uint256 feesGrowthGlobal1X128LastWithdrawal
    ) public view returns (uint256 feesGlobal0, uint256 feesGlobal1) {
        (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) = poolManager.getFeeGrowthGlobals(poolId);

        unchecked {
            feesGlobal0 = feeGrowthGlobal0X128 - feesGrowthGlobal0X128LastWithdrawal;
            feesGlobal1 = feeGrowthGlobal1X128 - feesGrowthGlobal1X128LastWithdrawal;
        }
    }

    function withdrawRewards(
        PositionParams memory params,
        ERC20 rewardToken
    ) external returns (uint256 rewards0, uint256 rewards1) {
        // TODO Ensure the caller is the owner of the position
        // require(params.owner == msg.sender, "Caller is not the owner");

        // Calculate rewards
        (rewards0, rewards1) = calculateRewards(params, rewardToken);

        // Fetch the position information to get fee growth inside values
        Position.Info memory position = poolManager.getPosition(
            params.poolId,
            params.owner,
            params.tickLower,
            params.tickUpper,
            params.salt
        );

        // Fetch the global fee growth values
        (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) = poolManager.getFeeGrowthGlobals(params.poolId);

        // Update the last withdrawal snapshot
        bytes32 positionId = toPositionId(params.poolId, params.owner, params.tickLower, params.tickUpper, params.salt);
        lastWithdrawals[positionId] = WithdrawalSnapshot({
            feeGrowthInside0X128: position.feeGrowthInside0LastX128,
            feeGrowthInside1X128: position.feeGrowthInside1LastX128,
            feesGrowthGlobal0X128: feeGrowthGlobal0X128,
            feesGrowthGlobal1X128: feeGrowthGlobal1X128,
            blockNumber: block.number
        });

        // Transfer the rewards to the user
        uint256 totalRewards = rewards0 + rewards1;
        require(rewardToken.balanceOf(address(this)) >= totalRewards, "Insufficient contract balance");

        rewardToken.transfer(msg.sender, totalRewards);
    }
}
