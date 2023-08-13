// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITurnstile {
    function register(address) external returns (uint256);
    function assign(uint256) external returns (uint256);
}
