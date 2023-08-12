// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./CannonaroPresaleERC20.sol";

/**
 * @title Cannonaro Factory
 * @notice Factory for deploying Cannonaro ERC20 presale contracts
 * @dev Presale status and user participation state maintained here
 */
contract CannonaroFactory {
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

    TokenPresaleData[] public tokens;

    uint[][4] public tokenIDsByPresaleStatus;

    mapping(address => uint) public tokenIDfromAddress;
    mapping(uint => address) public tokenAddressFromID;
    mapping(address => bool) public isToken;
    mapping(address => uint[]) public presalesJoinedByUser;
    mapping(address => mapping(uint => UserPresaleData)) public userPresaleData;

    uint public immutable csrID;

    address public constant Turnstile = address(0xEcf044C5B4b867CFda001101c617eCd347095B44);

    event PresaleERC20Created(uint tokenID, address token);
    event PresaleStatusUpdated(uint tokenID, address token, PresaleStatus newStatus);

    constructor() {
        csrID = ITurnstile(Turnstile).register(msg.sender);
    }

    modifier onlyTokens {
        require(isToken[msg.sender], "Caller is not a registered token");
        _;
    }

    modifier onlyEOA {
        require(msg.sender == tx.origin, "Only EOA");
        _;
    }

    /// View Functions

    /// @notice Get total number of tokens launched through factory
    /// @return amount Number of tokens created
    function getTotalTokensCreated() external view returns (uint amount) {
        amount = tokens.length;
    }

    /// @notice Get all token IDs for currently open presales
    /// @return idsForOpenPresales Array of token IDs for open presales
    function getTokenIDsForOpenPresales() external view returns (uint[] memory idsForOpenPresales) {
        idsForOpenPresales = tokenIDsByPresaleStatus[uint(PresaleStatus.OPEN)];
    }

    /// @notice Get all token IDs for currently funded presales
    /// @return idsForFundedPresales Array of token IDs for live presales
    function getTokenIDsForFundedPresales() external view returns (uint[] memory idsForFundedPresales) {
        idsForFundedPresales = tokenIDsByPresaleStatus[uint(PresaleStatus.FUNDED)];
    }

    /// @notice Get all token IDs for currently vesting presales
    /// @return idsForVestingPresales Array of token IDs for live presales
    function getTokenIDsForVestingPresales() external view returns (uint[] memory idsForVestingPresales) {
        idsForVestingPresales = tokenIDsByPresaleStatus[uint(PresaleStatus.VESTING)];
    }

    /// @notice Get all token IDs for currently live presales
    /// @return idsForVestedPresales Array of token IDs for live presales
    function getTokenIDsForVestedPresales() external view returns (uint[] memory idsForVestedPresales) {
        idsForVestedPresales = tokenIDsByPresaleStatus[uint(PresaleStatus.VESTED)];
    }

    /// @notice Presale status getter for single token ID
    /// @param tokenID token ID
    /// @return status PresaleStatus value
    function getPresaleStatusForTokenID(uint tokenID) public view returns (PresaleStatus status) {
        status = tokens[tokenID].presaleStatus;
    }

    /// @notice Presale status getter for array of presale IDs
    /// @param tokenIDs Array of token IDs
    /// @return presaleStatusForTokenIDs Array of PresaleStatus values
    function getPresaleStatusForTokenIDsArray(uint[] calldata tokenIDs) public view returns (PresaleStatus[] memory presaleStatusForTokenIDs) {
        presaleStatusForTokenIDs = new PresaleStatus[](tokenIDs.length);
        for (uint i; i < tokenIDs.length; ++i) {
            presaleStatusForTokenIDs[i] = getPresaleStatusForTokenID(tokenIDs[i]);
        }
    }

    /// @notice Presale status getter by address
    /// @param token Contract address of the token launched through factory
    /// @return status Presale status of the input token address
    function getPresaleStatusForTokenAddress(address token) external view returns (PresaleStatus status) {
        uint tokenID = tokenIDfromAddress[token];
        status = getPresaleStatusForTokenID(tokenID);
    }

    /// @notice Get token IDs for presales joined by a user
    /// @param user Address of the user
    /// @return tokenIDs Array of token IDs for all presales joined by a user
    function getPresalesJoinedByUser(address user) external view returns (uint[] memory tokenIDs) {
        tokenIDs = presalesJoinedByUser[user];
    }

    /// Internal and token only functions

    function _removeFromCurrentStatusArray(uint tokenID) internal {
        TokenPresaleData memory td = tokens[tokenID];
        uint[] storage tokenIDs = tokenIDsByPresaleStatus[uint(td.presaleStatus)];
        uint length = tokenIDs.length;
        // Multiple elements in the array and not removing the last element
        // Move last element into position of removed element
        if (length > 1 && (length - 1 != td.statusArrayIndex)) {
            uint lastTokenID = tokenIDs[length - 1];
            tokens[lastTokenID].statusArrayIndex = td.statusArrayIndex;
            tokenIDs[td.statusArrayIndex] = lastTokenID;
        }
        tokenIDs.pop();
    }

    function updateTokenPresaleStatus(PresaleStatus status) external onlyTokens {
        uint tokenID = tokenIDfromAddress[msg.sender];
        _removeFromCurrentStatusArray(tokenID);
        uint nextStatusArrayIndex = tokenIDsByPresaleStatus[uint(status)].length;
        tokenIDsByPresaleStatus[uint(status)].push(tokenID);
        tokens[tokenID] = TokenPresaleData(status, block.timestamp, nextStatusArrayIndex);

        emit PresaleStatusUpdated(tokenID, msg.sender, status);
    }

    function userJoiningPresale(address user) external onlyTokens {
        uint tokenID = tokenIDfromAddress[msg.sender];
        if (!userPresaleData[user][tokenID].joined) {
            uint nextJoinedArrayIndex = presalesJoinedByUser[user].length;
            presalesJoinedByUser[user].push(tokenID);
            userPresaleData[user][tokenID] = UserPresaleData(true, nextJoinedArrayIndex);
        }
    }

    function userExitingPresale(address user) external onlyTokens {
        uint tokenID = tokenIDfromAddress[msg.sender];
        uint length = presalesJoinedByUser[user].length;
        uint tokenIDtoRemoveIndex = userPresaleData[user][tokenID].joinedArrayIndex;
        userPresaleData[user][tokenID].joined = false;
        if (length > 1 && (length - 1 != tokenIDtoRemoveIndex)) {
            uint lastTokenID = presalesJoinedByUser[user][length - 1];
            presalesJoinedByUser[user][tokenIDtoRemoveIndex] = lastTokenID;
            userPresaleData[user][lastTokenID].joinedArrayIndex = tokenIDtoRemoveIndex;
        }
        presalesJoinedByUser[user].pop();
    }

    /// Launch function

    /**
     * @notice Launch token with presale logic
     * @dev Function has an EOA only guard to prevent contract launch + presale contributing in single transaction
     * @param name Token name 
     * @param symbol Token symbol 
     * @param supply Token total supply 
     * @param presaleRaiseGoalAmount Total amount desired to raise for liquidity 
     * @param vestingDuration Length of the vesting period, entered as seconds 
     * @param supplyPercentForPresaleBasisPoints Percent of total supply allocated for presale (entered as basis points)
     * @param pairType Token type for raise and liquidity pair, 0 - CANTO, 1 - NOTE
     * @return tokenID Unique ID for presale and token in Cannonaro
     */
    function createPresaleToken(
        string memory name,
        string memory symbol,
        uint supply,
        uint presaleRaiseGoalAmount,
        uint vestingDuration,
        uint supplyPercentForPresaleBasisPoints,
        CannonaroPresaleERC20.PairType pairType
    ) external onlyEOA returns (uint tokenID) {
        address tokenAddress = address(new CannonaroPresaleERC20(
            name,
            symbol,
            supply,
            presaleRaiseGoalAmount,
            vestingDuration,
            supplyPercentForPresaleBasisPoints,
            address(this),
            pairType
        ));

        tokenID = tokens.length;
        tokenIDfromAddress[tokenAddress] = tokenID;
        tokenAddressFromID[tokenID] = tokenAddress;
        isToken[tokenAddress] = true;

        uint[] storage tokenIDs = tokenIDsByPresaleStatus[uint(PresaleStatus.OPEN)];
        uint index = tokenIDs.length;
        tokenIDs.push(tokenID);
        tokens.push(TokenPresaleData(PresaleStatus.OPEN, block.timestamp, index));

        emit PresaleERC20Created(tokenID, tokenAddress);
    }

}
