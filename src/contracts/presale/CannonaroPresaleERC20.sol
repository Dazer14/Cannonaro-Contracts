// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "openzeppelin/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "openzeppelin/token/ERC20/extensions/draft-ERC20Permit.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "openzeppelin/security/ReentrancyGuard.sol";
// import "@openzeppelin/contracts/utils/Address.sol";
import "openzeppelin/utils/Address.sol";
import "lib/CSR-Rewards-ERC20/src/contracts/CsrRewardsERC20.sol";

import "../../interfaces/ICannonaroFactory.sol";

/**
 * @title Cannonaro Presale ERC20
 * @notice ERC20 extended with linear vesting presale support
 * @dev Inherited by Presale pair type
 */
abstract contract CannonaroPresaleERC20 is ERC20, ReentrancyGuard, ERC20Permit, CsrRewardsERC20 {
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

    address public immutable Factory;
    PresaleConstants public presaleConstants;
    PresaleMutables public presaleMutables;
    mapping(address => AllocationData) public presaleParticipant;

    event PresaleContribution(address contributor, uint256 amount);
    event PresaleFullyFunded();
    event PresaleExit(address contributor, uint256 amountReturned);
    event TokenLaunch(uint256 timestamp);
    event VestingClaim(address contributor, uint256 claimAmount);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _supply,
        uint256 _presaleRaiseGoalAmount,
        uint256 _vestingDuration,
        uint256 _supplyPercentForPresaleBasisPoints,
        address _Factory,
        bool _usingWithdrawCallFee,
        uint16 _withdrawCallFeeBasisPoints
    ) ERC20(_name, _symbol) ERC20Permit(_name) CsrRewardsERC20(_usingWithdrawCallFee, _withdrawCallFeeBasisPoints) {
        require(
            _supplyPercentForPresaleBasisPoints <= 9900 && _supplyPercentForPresaleBasisPoints >= 100,
            "Presale supply must be between 1% and 99%"
        );

        require(_supply > 0 && _presaleRaiseGoalAmount > 0, "Supply and raise goal must be non zero");

        _mint(address(this), _supply);

        Factory = _Factory;

        uint256 tokenAmountReservedForPresale = _supply * _supplyPercentForPresaleBasisPoints / 10000;

        presaleConstants = PresaleConstants(
            _presaleRaiseGoalAmount,
            _vestingDuration,
            _supplyPercentForPresaleBasisPoints,
            tokenAmountReservedForPresale,
            _supply - tokenAmountReservedForPresale,
            block.timestamp
        );
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override(ERC20, CsrRewardsERC20) {
        super._afterTokenTransfer(from, to, amount);
    }

    /// VIEW FUNCTIONS

    /// @notice Percent progress of presale raise
    /// @return progress Percent progress returned as integer
    function presaleProgress() external view returns (uint256 progress) {
        progress = presaleMutables.totalAmountRaised * 100 / presaleConstants.presaleRaiseGoalAmount;
    }

    /// @notice Presale Contributors can view claimable amount
    /// @return amount Token amount claimable
    function amountClaimable(address user) public view returns (uint256 amount) {
        if (!presaleMutables.tokenHasLaunched) return 0;
        AllocationData memory ad = presaleParticipant[user];
        if (block.timestamp < (presaleMutables.tokenPairLaunchTimestamp + presaleConstants.vestingDuration)) {
            // vesting
            uint256 claimStartTimestamp =
                ad.lastClaimTimestamp == 0 ? presaleMutables.tokenPairLaunchTimestamp : ad.lastClaimTimestamp;
            amount = ad.totalAllocation * (block.timestamp - claimStartTimestamp) / presaleConstants.vestingDuration;
        } else {
            // vesting period finished, return remainder of unclaimed tokens
            amount = ad.totalAllocation - ad.amountClaimed;
        }
    }

    /// MUTABLE FUNCTIONS

    function _updateStatusInFactory(ICannonaroFactory.PresaleStatus status) internal {
        ICannonaroFactory(Factory).updateTokenPresaleStatus(status);
    }

    function _joinPresale(uint256 contributionAmount) internal returns (uint256 excessContribution) {
        require(!presaleMutables.presaleComplete, "Presale has completed");
        require(contributionAmount > 0, "Must make non zero contribution");

        ICannonaroFactory(Factory).userJoiningPresale(msg.sender);

        // contributing within raise goal bounds
        if (presaleMutables.totalAmountRaised + contributionAmount < presaleConstants.presaleRaiseGoalAmount) {
            uint256 tokenAllocationAmountForContribution = presaleConstants.tokenAmountReservedForPresale
                * contributionAmount / presaleConstants.presaleRaiseGoalAmount;

            presaleParticipant[msg.sender].totalAllocation += tokenAllocationAmountForContribution;
            presaleParticipant[msg.sender].amountContributed += contributionAmount;
            presaleMutables.presaleTokensAllocated += tokenAllocationAmountForContribution;
            presaleMutables.totalAmountRaised += contributionAmount;

            emit PresaleContribution(msg.sender, contributionAmount);
        } else {
            // contribution is remainder of raise goal or excess contribution
            uint256 presaleAllocationRemainder =
                presaleConstants.tokenAmountReservedForPresale - presaleMutables.presaleTokensAllocated;
            presaleParticipant[msg.sender].totalAllocation += presaleAllocationRemainder;
            uint256 remainingRaiseMargin = presaleConstants.presaleRaiseGoalAmount - presaleMutables.totalAmountRaised;
            excessContribution = contributionAmount - remainingRaiseMargin;
            presaleParticipant[msg.sender].amountContributed += remainingRaiseMargin;
            presaleMutables.presaleTokensAllocated = presaleConstants.tokenAmountReservedForPresale;
            presaleMutables.totalAmountRaised = presaleConstants.presaleRaiseGoalAmount;

            presaleMutables.presaleComplete = true;
            _updateStatusInFactory(ICannonaroFactory.PresaleStatus.FUNDED);

            emit PresaleContribution(msg.sender, remainingRaiseMargin);
            emit PresaleFullyFunded();
        }
    }

    function joinPresale(uint256 amount) external payable virtual;

    function _returnPresaleContribution(address account, uint256 amount) internal virtual;

    /// @notice Presale contributors can exit prior to raise completion and retrieve all contributions
    function exitPresale() external nonReentrant {
        require(!presaleMutables.presaleComplete, "Presale is complete");
        AllocationData memory ad = presaleParticipant[msg.sender];
        require(ad.amountContributed > 0, "You have not made any contribution yet");
        presaleMutables.totalAmountRaised -= ad.amountContributed;
        presaleMutables.presaleTokensAllocated -= ad.totalAllocation;
        presaleParticipant[msg.sender] = AllocationData(0, 0, 0, 0);

        _returnPresaleContribution(msg.sender, ad.amountContributed);

        ICannonaroFactory(Factory).userExitingPresale(msg.sender);

        emit PresaleExit(msg.sender, ad.amountContributed);
    }

    function _supplyLiquidity(uint256 totalAmountRaised, uint256 tokenAmountForInitialLiquidity) internal virtual;

    /// @notice Launch token pair liquidity when presale raise goal is met
    function launchToken() external nonReentrant {
        require(presaleMutables.presaleComplete, "Presale raise goal has not been met");
        require(!presaleMutables.tokenHasLaunched, "Token has already launched");
        presaleMutables.tokenPairLaunchTimestamp = block.timestamp;

        _supplyLiquidity(presaleMutables.totalAmountRaised, presaleConstants.tokenAmountForInitialLiquidity);

        presaleMutables.tokenHasLaunched = true;
        _updateStatusInFactory(ICannonaroFactory.PresaleStatus.VESTING);

        emit TokenLaunch(block.timestamp);
    }

    /// @notice Presale contributors can vest claimable tokens
    function vest() external nonReentrant {
        require(presaleMutables.tokenHasLaunched, "Token has not launched, no vesting");
        uint256 claimableAmount = amountClaimable(msg.sender);
        require(claimableAmount > 0, "No tokens to vest");
        presaleParticipant[msg.sender].amountClaimed += claimableAmount;
        presaleParticipant[msg.sender].lastClaimTimestamp = block.timestamp;
        presaleMutables.totalAmountClaimed += claimableAmount;
        _transfer(address(this), msg.sender, claimableAmount);
        if (presaleMutables.totalAmountClaimed == presaleConstants.tokenAmountReservedForPresale) {
            _updateStatusInFactory(ICannonaroFactory.PresaleStatus.VESTED);
        }

        emit VestingClaim(msg.sender, claimableAmount);
    }
}
