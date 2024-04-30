// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";

struct Values {
    uint256 period;
    uint256 amount;
}

contract IncentiveHook is BaseHook {
    using CurrencyLibrary for Currency;

    using BalanceDeltaLibrary for BalanceDelta;

    mapping(Currency => mapping(Currency => mapping(ERC20 => Values))) public rewards;

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
                afterDonate: false
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
        PoolKey calldata,
        uint160,
        int24,
        bytes calldata
    ) external pure override returns (bytes4) {
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
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.afterAddLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.afterRemoveLiquidity.selector;
    }

    function beforeSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.beforeSwap.selector;
    }

    function afterSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.afterSwap.selector;
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

    /// @notice Updates the amount of ERC20 rewards allocated to a given pair and distribution period.
    /// @dev The rewards are allocated to all the pools of the given pair that have this hook attached.
    /// @param currency0 The lower currency of the pair.
    /// @param currency1 The higher currency of the pair.
    /// @param rewardToken The ERC20 token to allocate as rewards. 
    /// @param newAmount The amount of ERC20 rewards to allocate.
    /// @param period The distribution period in blocks.
    function updateRewards(
        Currency currency0,
        Currency currency1,
        ERC20 rewardToken,
        uint256 newAmount,
        uint256 period
    ) external {
        // sets the amount of rewardToken allocated to the pair regardless of the direction
        rewards[currency0][currency1][rewardToken] = Values(newAmount, period);
        rewards[currency1][currency0][rewardToken] = Values(newAmount, period);

        // settles the amount of rewardToken between the caller and this contract
        
        // calculates the balance difference for this hook contract
        uint256 currentBalance = rewardToken.balanceOf(address(this));
        if (currentBalance < newAmount) {
            // Need more tokens to allocate the reward properly
            uint256 needed = newAmount - currentBalance;
            // check allowance and transfer the needed amount
            require(rewardToken.allowance(msg.sender, address(this)) >= needed, "Insufficient allowance");
            rewardToken.transferFrom(msg.sender, address(this), needed);
        } else if (currentBalance > newAmount) {
            // Excess tokens can be returned to the caller
            uint256 excess = currentBalance - newAmount;
            rewardToken.transfer(msg.sender, excess);
        }
    }

    // Public function to manually access values in the nested mapping
    function getRewards(Currency from, Currency to, ERC20 token) public view returns (uint256, uint256) {
        // Access the nested mapping structure
        Values storage value = rewards[from][to][token];
        return (value.period, value.amount);
    }

    /// @notice Withdraws the ERC20 rewards allocated to the caller.
    /// @param tokens ERC20 tokens to withdraw 
    /// @param amounts amounts corresponding to the tokens to withdraw
    function withdrawRewards(ERC20[] memory tokens, uint256[] memory amounts) external {
    }

    /// @notice Returns the amount of ERC20 rewards allocated to an address.
    /// @param token The ERC20 token to query.
    /// @param account The address to query.
    /// @return The amount of ERC20 rewards allocated to the address.
    function getRewards(ERC20 token, address account) external view returns (uint256) {
        
    }
}
