// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRouter {
    function addLiquidityCANTO(
        address token,
        bool stable,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountCANTOMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountCANTO, uint256 liquidity);
    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}
