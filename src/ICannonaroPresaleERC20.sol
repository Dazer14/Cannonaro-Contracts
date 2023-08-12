// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

interface ICannonaroPresaleERC20 {
    enum PairType {
        CANTO,
        NOTE
    }
    struct PresaleConstants {
        uint presaleRaiseGoalAmount; 
        uint vestingDuration;
        uint supplyPercentForPresaleBasisPoints;
        uint tokenAmountReservedForPresale;
        uint tokenAmountForInitialLiquidity;
        uint presaleLaunchTimestamp;
        PairType pairType;
    }
    struct PresaleMutables {
        uint totalAmountRaised;
        uint presaleTokensAllocated;
        uint totalAmountClaimed;
        bool presaleComplete;
        bool tokenHasLaunched;
        uint tokenPairLaunchTimestamp;
    }
    struct AllocationData {
        uint totalAllocation;
        uint amountClaimed;
        uint lastClaimTimestamp;
        uint amountContributed;
    }

    // Generated getters

    function Factory() external returns (address);
    function presaleConstants() external returns (PresaleConstants memory);
    function presaleMutables() external returns (PresaleMutables memory);
    function presaleParticipant(address user) external returns (AllocationData memory);

    // Custom getters
    function presaleProgress() external view returns (uint progress);
    function amountClaimable(address user) external view returns (uint amount);

    // Mutable Functions
    function joinPresaleCANTO() external payable;
    function joinPresaleNOTE(uint contributionAmount) external;
    function exitPresale() external;
    function launchToken() external;
    function vest() external;
}
