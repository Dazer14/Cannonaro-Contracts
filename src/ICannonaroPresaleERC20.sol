// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

interface ICannonaroPresaleERC20 {
    struct PresaleConstants {
        uint256 presaleRaiseGoalAmount;
        uint256 vestingDuration;
        uint256 supplyPercentForPresaleBasisPoints;
        uint256 tokenAmountReservedForPresale;
        uint256 tokenAmountForInitialLiquidity;
        uint256 presaleLaunchTimestamp;
    }

    struct PresaleMutables {
        uint256 totalAmountRaised;
        uint256 presaleTokensAllocated;
        uint256 totalAmountClaimed;
        bool presaleComplete;
        bool tokenHasLaunched;
        uint256 tokenPairLaunchTimestamp;
    }

    struct AllocationData {
        uint256 totalAllocation;
        uint256 amountClaimed;
        uint256 lastClaimTimestamp;
        uint256 amountContributed;
    }

    // Generated getters

    function Factory() external returns (address);
    function presaleConstants() external returns (PresaleConstants memory);
    function presaleMutables() external returns (PresaleMutables memory);
    function presaleParticipant(address user) external returns (AllocationData memory);

    // Custom getters
    function presaleProgress() external view returns (uint256 progress);
    function amountClaimable(address user) external view returns (uint256 amount);

    // Mutable Functions
    function joinPresaleCANTO() external payable;
    function joinPresaleNOTE(uint256 contributionAmount) external;
    function exitPresale() external;
    function launchToken() external;
    function vest() external;
}
