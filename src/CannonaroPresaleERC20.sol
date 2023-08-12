// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
// import "@openzeppelin/contracts/utils/Address.sol";
import "lib/openzeppelin-contracts/contracts/utils/Address.sol";

import "./ICannonaroFactory.sol";
import "./ITurnstile.sol";
import "./IRouter.sol";

/**
 * @title Cannonaro Presale ERC20
 * @notice ERC20 extended with linear vesting presale support
 * @dev This contract is deployed through the Cannonaro Factory
 */
contract CannonaroPresaleERC20 is ERC20, ReentrancyGuard, ERC20Permit {
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

    address public immutable Factory;
    PresaleConstants public presaleConstants;
    PresaleMutables public presaleMutables;
    mapping (address => AllocationData) public presaleParticipant;

    address public constant NOTE = address(0x4e71A2E537B7f9D9413D3991D37958c0b5e1e503);
    address public constant Router = address(0xa252eEE9BDe830Ca4793F054B506587027825a8e);
    address public constant Turnstile = address(0xEcf044C5B4b867CFda001101c617eCd347095B44);
    address private constant DEAD = address(0x000000000000000000000000000000000000dEaD);

    event PresaleContribution(address contributor, uint amount);
    event PresaleFullyFunded();
    event PresaleExit(address contributor, uint amountReturned);
    event TokenLaunch(uint timestamp);
    event VestingClaim(address contributor, uint claimAmount);

    constructor(
        string memory _name,
        string memory _symbol,
        uint _supply,
        uint _presaleRaiseGoalAmount,
        uint _vestingDuration,
        uint _supplyPercentForPresaleBasisPoints,
        address _Factory,
        PairType _pairType
    ) ERC20(_name, _symbol) ERC20Permit(_name) {
        require(
            _supplyPercentForPresaleBasisPoints <= 9900 &&
            _supplyPercentForPresaleBasisPoints >= 100, 
            "Presale supply must be between 1% and 99%"
        );

        require(
            _supply > 0 &&
            _presaleRaiseGoalAmount > 0,
            "Supply and raise goal must be non zero"
        );

        require(
            _pairType == PairType.CANTO || _pairType == PairType.NOTE,
            "Invalid pair type input"
        );

        _mint(address(this), _supply);

        Factory = _Factory;

        uint tokenAmountReservedForPresale = _supply * _supplyPercentForPresaleBasisPoints / 10000;

        presaleConstants = PresaleConstants(
            _presaleRaiseGoalAmount,
            _vestingDuration,
            _supplyPercentForPresaleBasisPoints,
            tokenAmountReservedForPresale,
            _supply - tokenAmountReservedForPresale,
            block.timestamp,
            _pairType
        );

        ITurnstile(Turnstile).assign(ICannonaroFactory(Factory).csrID());
    }

    function _isCantoPair() internal view returns (bool) {
        return presaleConstants.pairType == PairType.CANTO;
    }

    function _isNotePair() internal view returns (bool) {
        return presaleConstants.pairType == PairType.NOTE;
    }

    /// View Functions

    /// @notice Percent progress of presale raise
    /// @return progress Percent progress returned as integer
    function presaleProgress() external view returns (uint progress) {
        progress = presaleMutables.totalAmountRaised * 100 / presaleConstants.presaleRaiseGoalAmount;
    }

    /// @notice Presale Contributors can view claimable amount
    /// @return amount Token amount claimable
    function amountClaimable(address user) public view returns (uint amount) {
        if (!presaleMutables.tokenHasLaunched) return 0;
        AllocationData memory ad = presaleParticipant[user];
        if (block.timestamp < (presaleMutables.tokenPairLaunchTimestamp + presaleConstants.vestingDuration)) { // vesting
            uint claimStartTimestamp = ad.lastClaimTimestamp == 0 ? presaleMutables.tokenPairLaunchTimestamp : ad.lastClaimTimestamp;
            amount = ad.totalAllocation * (block.timestamp - claimStartTimestamp) / presaleConstants.vestingDuration;
        } else { // vesting period finished, return remainder of unclaimed tokens
            amount = ad.totalAllocation - ad.amountClaimed;
        }
    }

    /// Mutable Functions

    function _updateStatusInFactory(ICannonaroFactory.PresaleStatus status) internal {
        ICannonaroFactory(Factory).updateTokenPresaleStatus(status);
    }

    function _joinPresale(uint contributionAmount) internal returns (uint excessContribution) {
        require(!presaleMutables.presaleComplete, "Presale has completed");
        require(contributionAmount > 0, "Must make non zero contribution");

        ICannonaroFactory(Factory).userJoiningPresale(msg.sender);

        // contributing within raise goal bounds
        if (presaleMutables.totalAmountRaised + contributionAmount < presaleConstants.presaleRaiseGoalAmount) { 
            uint tokenAllocationAmountForContribution = 
                presaleConstants.tokenAmountReservedForPresale * contributionAmount / presaleConstants.presaleRaiseGoalAmount;
            
            presaleParticipant[msg.sender].totalAllocation += tokenAllocationAmountForContribution;
            presaleParticipant[msg.sender].amountContributed += contributionAmount;
            presaleMutables.presaleTokensAllocated += tokenAllocationAmountForContribution;
            presaleMutables.totalAmountRaised += contributionAmount;

            emit PresaleContribution(msg.sender, contributionAmount);

        } else { // contribution is remainder of raise goal or excess contribution
            uint presaleAllocationRemainder = presaleConstants.tokenAmountReservedForPresale - presaleMutables.presaleTokensAllocated;
            presaleParticipant[msg.sender].totalAllocation += presaleAllocationRemainder;
            uint remainingRaiseMargin = presaleConstants.presaleRaiseGoalAmount - presaleMutables.totalAmountRaised;
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

    /// @notice Payable contribution function for CANTO based presales
    function joinPresaleCANTO() external payable nonReentrant {
        require(_isCantoPair(), "Must be a CANTO pair to call");

        uint contributionAmount = msg.value;

        uint excessContribution = _joinPresale(contributionAmount);

        if (excessContribution > 0) {
            Address.sendValue(payable(msg.sender), excessContribution);
        }
    }

    /// @notice Contribution function for NOTE based presales, must approve before
    /// @param contributionAmount NOTE amount to contribute
    function joinPresaleNOTE(uint contributionAmount) external nonReentrant {
        require(_isNotePair(), "Must be a NOTE pair to call");

        IERC20(NOTE).transferFrom(msg.sender, address(this), contributionAmount);

        uint excessContribution = _joinPresale(contributionAmount);

        if (excessContribution > 0) {
            IERC20(NOTE).transfer(msg.sender, excessContribution);
        }
    }

    /// @notice Presale contributors can exit prior to raise completion and retrieve all contributions
    function exitPresale() external nonReentrant {
        require(!presaleMutables.presaleComplete, "Presale is complete");
        AllocationData memory ad = presaleParticipant[msg.sender];
        require(ad.amountContributed > 0, "You have not made any contribution yet");
        presaleMutables.totalAmountRaised -= ad.amountContributed;
        presaleMutables.presaleTokensAllocated -= ad.totalAllocation;
        presaleParticipant[msg.sender] = AllocationData(0,0,0,0);

        if (_isCantoPair()) {
            Address.sendValue(payable(msg.sender), ad.amountContributed);
        } 
        
        if (_isNotePair()) {
            IERC20(NOTE).transfer(msg.sender, ad.amountContributed);
        }

        ICannonaroFactory(Factory).userExitingPresale(msg.sender);

        emit PresaleExit(msg.sender, ad.amountContributed);
    }

    /// @notice Launch token pair liquidity when presale raise goal is met
    function launchToken() external nonReentrant {
        require(presaleMutables.presaleComplete, "Presale raise goal has not been met");
        require(!presaleMutables.tokenHasLaunched, "Token has already launched");
        presaleMutables.tokenPairLaunchTimestamp = block.timestamp;

        _approve(address(this), Router, presaleConstants.tokenAmountForInitialLiquidity);

        if (_isCantoPair()) {
            IRouter(Router).addLiquidityCANTO{value: presaleMutables.totalAmountRaised}(
                address(this), 
                false,
                presaleConstants.tokenAmountForInitialLiquidity, 
                0, 
                0, 
                DEAD, 
                block.timestamp
            );
        }

        if (_isNotePair()) {
            IERC20(NOTE).approve(Router, presaleMutables.totalAmountRaised);
            IRouter(Router).addLiquidity(
                NOTE,
                address(this),
                false,
                presaleMutables.totalAmountRaised,
                presaleConstants.tokenAmountForInitialLiquidity,
                0,
                0,
                DEAD,
                block.timestamp
            );
        }

        presaleMutables.tokenHasLaunched = true;
        _updateStatusInFactory(ICannonaroFactory.PresaleStatus.VESTING);

        emit TokenLaunch(block.timestamp);
    }

    /// @notice Presale contributors can vest claimable tokens 
    function vest() external nonReentrant {
        require(presaleMutables.tokenHasLaunched, "Token has not launched, no vesting");
        uint claimableAmount = amountClaimable(msg.sender);
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
