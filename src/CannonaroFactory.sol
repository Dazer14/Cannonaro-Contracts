// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./CantoPresale.sol";
import "./ITurnstile.sol";

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
        uint256 lastPresaleStatusUpdateTimestamp;
        uint256 statusArrayIndex;
    }

    struct UserPresaleData {
        bool joined;
        uint256 joinedArrayIndex;
    }

    TokenPresaleData[] public tokens;

    uint256[][4] public tokenIDsByPresaleStatus;

    mapping(address => uint256) public tokenIDfromAddress;
    mapping(uint256 => address) public tokenAddressFromID;
    mapping(address => bool) public isToken;
    mapping(address => uint256[]) public presalesJoinedByUser;
    mapping(address => mapping(uint256 => UserPresaleData)) public userPresaleData;

    uint256 public immutable csrID;

    address public constant Turnstile = address(0xEcf044C5B4b867CFda001101c617eCd347095B44);

    event PresaleERC20Created(uint256 tokenID, address token);
    event PresaleStatusUpdated(uint256 tokenID, address token, PresaleStatus newStatus);

    constructor() {
        csrID = ITurnstile(Turnstile).register(msg.sender);
    }

    modifier onlyTokens() {
        require(isToken[msg.sender], "Caller is not a registered token");
        _;
    }

    modifier onlyEOA() {
        require(msg.sender == tx.origin, "Only EOA");
        _;
    }

    /// VIEW FUNCTIONS

    /// @notice Get total number of tokens launched through factory
    /// @return amount Number of tokens created
    function getTotalTokensCreated() external view returns (uint256 amount) {
        amount = tokens.length;
    }

    /// @notice Get all token IDs for currently open presales
    /// @return idsForOpenPresales Array of token IDs for open presales
    function getTokenIDsForOpenPresales() external view returns (uint256[] memory idsForOpenPresales) {
        idsForOpenPresales = tokenIDsByPresaleStatus[uint256(PresaleStatus.OPEN)];
    }

    /// @notice Get all token IDs for currently funded presales
    /// @return idsForFundedPresales Array of token IDs for live presales
    function getTokenIDsForFundedPresales() external view returns (uint256[] memory idsForFundedPresales) {
        idsForFundedPresales = tokenIDsByPresaleStatus[uint256(PresaleStatus.FUNDED)];
    }

    /// @notice Get all token IDs for currently vesting presales
    /// @return idsForVestingPresales Array of token IDs for live presales
    function getTokenIDsForVestingPresales() external view returns (uint256[] memory idsForVestingPresales) {
        idsForVestingPresales = tokenIDsByPresaleStatus[uint256(PresaleStatus.VESTING)];
    }

    /// @notice Get all token IDs for currently live presales
    /// @return idsForVestedPresales Array of token IDs for live presales
    function getTokenIDsForVestedPresales() external view returns (uint256[] memory idsForVestedPresales) {
        idsForVestedPresales = tokenIDsByPresaleStatus[uint256(PresaleStatus.VESTED)];
    }

    /// @notice Presale status getter for single token ID
    /// @param tokenID token ID
    /// @return status PresaleStatus value
    function getPresaleStatusForTokenID(uint256 tokenID) public view returns (PresaleStatus status) {
        status = tokens[tokenID].presaleStatus;
    }

    /// @notice Presale status getter for array of presale IDs
    /// @param tokenIDs Array of token IDs
    /// @return presaleStatusForTokenIDs Array of PresaleStatus values
    function getPresaleStatusForTokenIDsArray(uint256[] calldata tokenIDs)
        public
        view
        returns (PresaleStatus[] memory presaleStatusForTokenIDs)
    {
        presaleStatusForTokenIDs = new PresaleStatus[](tokenIDs.length);
        for (uint256 i; i < tokenIDs.length; ++i) {
            presaleStatusForTokenIDs[i] = getPresaleStatusForTokenID(tokenIDs[i]);
        }
    }

    /// @notice Presale status getter by address
    /// @param token Contract address of the token launched through factory
    /// @return status Presale status of the input token address
    function getPresaleStatusForTokenAddress(address token) external view returns (PresaleStatus status) {
        uint256 tokenID = tokenIDfromAddress[token];
        status = getPresaleStatusForTokenID(tokenID);
    }

    /// @notice Get token IDs for presales joined by a user
    /// @param user Address of the user
    /// @return tokenIDs Array of token IDs for all presales joined by a user
    function getPresalesJoinedByUser(address user) external view returns (uint256[] memory tokenIDs) {
        tokenIDs = presalesJoinedByUser[user];
    }

    /// INTERNAL AND ONLY TOKEN FUNCTIONS

    function _removeFromCurrentStatusArray(uint256 tokenID) internal {
        TokenPresaleData memory td = tokens[tokenID];
        uint256[] storage tokenIDs = tokenIDsByPresaleStatus[uint256(td.presaleStatus)];
        uint256 length = tokenIDs.length;
        // Multiple elements in the array and not removing the last element
        // Move last element into position of removed element
        if (length > 1 && (length - 1 != td.statusArrayIndex)) {
            uint256 lastTokenID = tokenIDs[length - 1];
            tokens[lastTokenID].statusArrayIndex = td.statusArrayIndex;
            tokenIDs[td.statusArrayIndex] = lastTokenID;
        }
        tokenIDs.pop();
    }

    function updateTokenPresaleStatus(PresaleStatus status) external onlyTokens {
        uint256 tokenID = tokenIDfromAddress[msg.sender];
        _removeFromCurrentStatusArray(tokenID);
        uint256 nextStatusArrayIndex = tokenIDsByPresaleStatus[uint256(status)].length;
        tokenIDsByPresaleStatus[uint256(status)].push(tokenID);
        tokens[tokenID] = TokenPresaleData(status, block.timestamp, nextStatusArrayIndex);

        emit PresaleStatusUpdated(tokenID, msg.sender, status);
    }

    function userJoiningPresale(address user) external onlyTokens {
        uint256 tokenID = tokenIDfromAddress[msg.sender];
        if (!userPresaleData[user][tokenID].joined) {
            uint256 nextJoinedArrayIndex = presalesJoinedByUser[user].length;
            presalesJoinedByUser[user].push(tokenID);
            userPresaleData[user][tokenID] = UserPresaleData(true, nextJoinedArrayIndex);
        }
    }

    function userExitingPresale(address user) external onlyTokens {
        uint256 tokenID = tokenIDfromAddress[msg.sender];
        uint256 length = presalesJoinedByUser[user].length;
        uint256 tokenIDtoRemoveIndex = userPresaleData[user][tokenID].joinedArrayIndex;
        userPresaleData[user][tokenID].joined = false;
        if (length > 1 && (length - 1 != tokenIDtoRemoveIndex)) {
            uint256 lastTokenID = presalesJoinedByUser[user][length - 1];
            presalesJoinedByUser[user][tokenIDtoRemoveIndex] = lastTokenID;
            userPresaleData[user][lastTokenID].joinedArrayIndex = tokenIDtoRemoveIndex;
        }
        presalesJoinedByUser[user].pop();
    }

    /// LAUNCH FUNCTION

    /**
     * @notice Launch token with presale logic
     * @dev Function has an EOA only guard to prevent contract launch + presale contributing in single transaction
     * @dev Only using Canto pairs for now, update to handle others
     * @param name Token name
     * @param symbol Token symbol
     * @param supply Token total supply
     * @param presaleRaiseGoalAmount Total amount desired to raise for liquidity
     * @param vestingDuration Length of the vesting period, entered as seconds
     * @param supplyPercentForPresaleBasisPoints Percent of total supply allocated for presale (entered as basis points)
     * @return tokenID Unique ID for presale and token in Cannonaro
     */
    function createPresaleToken(
        string memory name,
        string memory symbol,
        uint256 supply,
        uint256 presaleRaiseGoalAmount,
        uint256 vestingDuration,
        uint256 supplyPercentForPresaleBasisPoints
    ) external onlyEOA returns (uint256 tokenID) {
        address tokenAddress = address(
            new CantoPresale(
                name,
                symbol,
                supply,
                presaleRaiseGoalAmount,
                vestingDuration,
                supplyPercentForPresaleBasisPoints,
                address(this)
            )
        );

        tokenID = tokens.length;
        tokenIDfromAddress[tokenAddress] = tokenID;
        tokenAddressFromID[tokenID] = tokenAddress;
        isToken[tokenAddress] = true;

        uint256[] storage tokenIDs = tokenIDsByPresaleStatus[uint256(PresaleStatus.OPEN)];
        uint256 index = tokenIDs.length;
        tokenIDs.push(tokenID);
        tokens.push(TokenPresaleData(PresaleStatus.OPEN, block.timestamp, index));

        emit PresaleERC20Created(tokenID, tokenAddress);
    }
}
