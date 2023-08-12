// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./CannonaroPresaleERC20.sol";
import "./IRouter.sol";

contract NotePresale is CannonaroPresaleERC20 {
    address private constant ROUTER = address(0xa252eEE9BDe830Ca4793F054B506587027825a8e);
    address private constant DEAD = address(0x000000000000000000000000000000000000dEaD);
    address public constant NOTE = address(0x4e71A2E537B7f9D9413D3991D37958c0b5e1e503);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _supply,
        uint256 _presaleRaiseGoalAmount,
        uint256 _vestingDuration,
        uint256 _supplyPercentForPresaleBasisPoints,
        address _Factory
    )
        CannonaroPresaleERC20(
            _name,
            _symbol,
            _supply,
            _presaleRaiseGoalAmount,
            _vestingDuration,
            _supplyPercentForPresaleBasisPoints,
            _Factory
        )
    {}

    function joinPresale(uint256 amount) external payable override {
        IERC20(NOTE).transferFrom(msg.sender, address(this), amount);
        uint256 excessContribution = _joinPresale(amount);
        if (excessContribution > 0) {
            IERC20(NOTE).transfer(msg.sender, excessContribution);
        }
    }

    function _returnPresaleContribution(address account, uint256 amount) internal override {
        IERC20(NOTE).transfer(account, amount);
    }

    function _supplyLiquidity(uint256 totalAmountRaised, uint256 tokenAmountForInitialLiquidity) internal override {
        _approve(address(this), ROUTER, tokenAmountForInitialLiquidity);
        IERC20(NOTE).approve(ROUTER, totalAmountRaised);
        IRouter(ROUTER).addLiquidity(
            NOTE, address(this), false, totalAmountRaised, tokenAmountForInitialLiquidity, 0, 0, DEAD, block.timestamp
        );
    }
}
