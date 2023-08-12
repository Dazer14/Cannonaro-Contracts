// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./CannonaroPresaleERC20.sol";
import "./IRouter.sol";

contract CantoPresale is CannonaroPresaleERC20 {
    address private constant ROUTER = address(0xa252eEE9BDe830Ca4793F054B506587027825a8e);
    address private constant DEAD = address(0x000000000000000000000000000000000000dEaD);

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
        uint256 contributionAmount = msg.value;
        uint256 excessContribution = _joinPresale(contributionAmount);
        if (excessContribution > 0) {
            Address.sendValue(payable(msg.sender), excessContribution);
        }
    }

    function _returnPresaleContribution(address account, uint256 amount) internal override {
        Address.sendValue(payable(account), amount);
    }

    function _supplyLiquidity(uint256 totalAmountRaised, uint256 tokenAmountForInitialLiquidity) internal override {
        _approve(address(this), ROUTER, tokenAmountForInitialLiquidity);
        IRouter(ROUTER).addLiquidityCANTO{value: totalAmountRaised}(
            address(this), false, tokenAmountForInitialLiquidity, 0, 0, DEAD, block.timestamp
        );
    }
}
