// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";

contract IncentiveHook is BaseHook, ERC20 {
    using CurrencyLibrary for Currency;

    using BalanceDeltaLibrary for BalanceDelta;

    constructor(
        IPoolManager _manager,
        string memory _name,
        string memory _symbol
    ) BaseHook(_manager) ERC20(_name, _symbol, 18) {}

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
}
