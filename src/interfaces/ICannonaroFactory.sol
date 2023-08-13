// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

interface ICannonaroFactory {
    enum PresaleStatus {
        OPEN,
        FUNDED,
        VESTING,
        VESTED
    }
    struct TokenPresaleData {
        PresaleStatus presaleStatus;
        uint lastPresaleStatusUpdateTimestamp;
        uint statusArrayIndex;
    }
    struct UserPresaleData {
        bool joined;
        uint joinedArrayIndex;
    }

    // Generated getters
    function tokens(uint tokenID) external view returns (TokenPresaleData memory);
    function tokenIDsByPresaleStatus(PresaleStatus, uint index) external view returns (uint tokenID);
    function tokenIDfromAddress(address) external view returns (uint);
    function tokenAddressFromID(uint) external view returns (address);
    function isToken(address) external view returns (bool);
    function presalesJoinedByUser(address user, uint index) external view returns (uint tokenID);
    function userPresaleData(address user, uint tokenID) external view returns (UserPresaleData memory);
    function csrID() external view returns (uint);

    // Custom getters
    function getTotalTokensCreated() external view returns (uint amount);
    function getTokenIDsForOpenPresales() external view returns (uint[] memory idsForOpenPresales);
    function getTokenIDsForFundedPresales() external view returns (uint[] memory idsForFundedPresales);
    function getTokenIDsForVestingPresales() external view returns (uint[] memory idsForVestingPresales);
    function getTokenIDsForVestedPresales() external view returns (uint[] memory idsForVestedPresales);
    function getPresaleStatusForTokenID(uint tokenID) external view returns (PresaleStatus status);
    function getPresaleStatusForTokenIDsArray(uint[] calldata tokenIDs) external view returns (PresaleStatus[] memory presaleStatusForTokenIDs);
    function getPresaleStatusForTokenAddress(address token) external view returns (PresaleStatus status);
    function getPresalesJoinedByUser(address user) external view returns (uint[] memory tokenIDs);

    // Update - Just for Presale Contract
    function updateTokenPresaleStatus(PresaleStatus status) external;
    function userJoiningPresale(address user) external;
    function userExitingPresale(address user) external;

    // Launch
    function createPresaleToken(
        string memory name,
        string memory symbol,
        uint supply,
        uint presaleRaiseGoalAmount,
        uint vestingDuration,
        uint supplyPercentForPresaleBasisPoints,
        uint8 pairType
    ) external returns (uint tokenID);
}
