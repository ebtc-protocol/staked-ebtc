// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { AutomationCompatible } from "./Dependencies/AutomationCompatible.sol";
import { BaseModule } from "./Dependencies/BaseModule.sol";
import { IGnosisSafe } from "./Dependencies/IGnosisSafe.sol";
import { IActivePool } from "./Dependencies/IActivePool.sol";
import { ICdpManager } from "./Dependencies/ICdpManager.sol";
import { IPriceFeed } from "./Dependencies/IPriceFeed.sol";
import { ICollateral } from "./Dependencies/ICollateral.sol";
import { ISwapRouter } from "./Dependencies/ISwapRouter.sol";
import { IWstEth } from "./Dependencies/IWstEth.sol";
import { IStakedEbtc } from "./IStakedEbtc.sol";
import { LinearRewardsErc4626 } from "./LinearRewardsErc4626.sol";

contract FeeRecipientDonationModule is BaseModule, AutomationCompatible, Pausable {
    IGnosisSafe public constant SAFE = IGnosisSafe(0x2CEB95D4A67Bf771f1165659Df3D11D8871E906f);
    ICollateral public constant COLLATERAL = ICollateral(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IActivePool public constant ACTIVE_POOL = IActivePool(0x6dBDB6D420c110290431E863A1A978AE53F69ebC);
    ICdpManager public constant CDP_MANAGER = ICdpManager(0xc4cbaE499bb4Ca41E78f52F07f5d98c375711774);
    IPriceFeed public constant PRICE_FEED = IPriceFeed(0xa9a65B1B1dDa8376527E89985b221B6bfCA1Dc9a);
    IERC20 public constant EBTC_TOKEN = IERC20(0x661c70333AA1850CcDBAe82776Bb436A0fCfeEfB);
    IWstEth public constant wstETH = IWstEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    address public constant GOVERNANCE = 0x690C74AF48BE029e763E61b4aDeB10E06119D3ba;
    address public constant CHAINLINK_KEEPER_REGISTRY = 0x02777053d6764996e594c3E88AF1D58D5363a2e6;
    uint256 public constant WEEKS_IN_YEAR = 52;
    uint256 public constant BPS = 10000;

    IStakedEbtc public immutable STAKED_EBTC;
    ISwapRouter public immutable DEX;
    uint256 public immutable REWARDS_CYCLE_LENGTH;

    ////////////////////////////////////////////////////////////////////////////
    // STORAGE
    ////////////////////////////////////////////////////////////////////////////
    address public guardian;

    uint256 public lastProcessingTimestamp;
    uint256 public annualizedYieldBPS;
    uint256 public swapSlippageBPS;
    bytes public swapPath;

    ////////////////////////////////////////////////////////////////////////////
    // ERRORS
    ////////////////////////////////////////////////////////////////////////////

    error NotGovernance(address caller);
    error NotGovernanceOrGuardian(address caller);
    error NotKeeper(address caller);

    error TooSoon(uint256 lastProcessing, uint256 timestamp);

    error NoFeesCollected(uint256 tokenId);
    error NotOwnedNft(uint256 tokenId);

    error ZeroIntervalPeriod();
    error ZeroAddress();
    error ModuleMisconfigured();

    ////////////////////////////////////////////////////////////////////////////
    // EVENTS
    ////////////////////////////////////////////////////////////////////////////

    event GuardianUpdated(address indexed oldGuardian, address indexed newGuardian, uint256 timestamp);
    event SwapPathUpdated(bytes oldPath, bytes newPath);
    event AnnualizedYieldUpdated(uint256 oldYield, uint256 newYield);
    event SwapSlippageUpdated(uint256 oldSlippage, uint256 newSlippage);

    ////////////////////////////////////////////////////////////////////////////
    // MODIFIERS
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Checks whether a call is from governance
    modifier onlyGovernance() {
        if (msg.sender != GOVERNANCE) revert NotGovernance(msg.sender);
        _;
    }

    /// @notice Checks whether a call is from governance or guardian
    modifier onlyGovernanceOrGuardian() {
        if (msg.sender != GOVERNANCE && msg.sender != guardian) revert NotGovernanceOrGuardian(msg.sender);
        _;
    }

    /// @notice Checks whether a call is from the keeper.
    modifier onlyKeeper() {
        if (msg.sender != CHAINLINK_KEEPER_REGISTRY) revert NotKeeper(msg.sender);
        _;
    }

    /// @param _guardian Address allowed to pause contract
    constructor(
        address _steBtc, 
        address _dex, 
        address _guardian, 
        uint256 _annualizedYieldBPS,
        uint256 _swapSlippageBPS,
        bytes memory _swapPath
    ) {
        if (_steBtc == address(0)) revert ZeroAddress();
        if (_dex == address(0)) revert ZeroAddress();
        if (_guardian == address(0)) revert ZeroAddress();

        STAKED_EBTC = IStakedEbtc(_steBtc);
        DEX = ISwapRouter(_dex);
        guardian = _guardian;
        annualizedYieldBPS = _annualizedYieldBPS;
        swapSlippageBPS = _swapSlippageBPS;
        swapPath = _swapPath;
    }

    ////////////////////////////////////////////////////////////////////////////
    // PUBLIC: Governance
    ////////////////////////////////////////////////////////////////////////////

    /// @notice  Updates the guardian address. Only callable by governance.
    /// @param _guardian Address which will become guardian
    function setGuardian(address _guardian) external onlyGovernance {
        if (_guardian == address(0)) revert ZeroAddress();
        address oldGuardian = guardian;
        guardian = _guardian;
        emit GuardianUpdated(oldGuardian, _guardian, block.timestamp);
    }

    function setSwapPath(bytes calldata _swapPath) external onlyGovernance {
        emit SwapPathUpdated(swapPath, _swapPath);
        swapPath = _swapPath;
    }

    function setAnnualizedYieldBPS(uint256 _annualizedYieldBPS) external onlyGovernance {
        emit AnnualizedYieldUpdated(annualizedYieldBPS, _annualizedYieldBPS);
        annualizedYieldBPS = _annualizedYieldBPS;
    }

    function setSwapSlippageBPS(uint256 _swapSlippageBPS)  external onlyGovernance {
        emit SwapSlippageUpdated(swapSlippageBPS, _swapSlippageBPS);
        swapSlippageBPS = _swapSlippageBPS;
    }

    /// @dev Pauses the contract, which prevents executing performUpkeep.
    function pause() external onlyGovernanceOrGuardian {
        _pause();
    }

    /// @dev Unpauses the contract.
    function unpause() external onlyGovernance {
        _unpause();
    }

    ////////////////////////////////////////////////////////////////////////////
    // PUBLIC: Keeper
    ////////////////////////////////////////////////////////////////////////////

    /// @dev Contains the logic that should be executed on-chain when
    ///      `checkUpkeep` returns true.
    function performUpkeep(bytes calldata performData) external override whenNotPaused onlyKeeper {
        /// @dev safety check, ensuring onchain module is config
        if (!SAFE.isModuleEnabled(address(this))) revert ModuleMisconfigured();

        if (!_isReady()) {
            revert TooSoon(lastProcessingTimestamp, block.timestamp);
        }

        (uint256 collSharesToClaim, uint256 ebtcAmountRequired) = abi.decode(performData, (uint256, uint256));

        if (collSharesToClaim > 0) {
            uint256 stEthClaimed = _claimFeeRecipientCollShares(collSharesToClaim);

            uint256 wstEthAmount = _approveAndWrap(stEthClaimed);

            uint256 ebtcReceived = _dexTrade(wstEthAmount, ebtcAmountRequired);

            _donate(ebtcReceived);
        }

        // syncRewardsAndDistribution is called elsewhere after REWARDS_CYCLE_LENGTH
        lastProcessingTimestamp = block.timestamp;
    }

    ////////////////////////////////////////////////////////////////////////////
    // PUBLIC VIEW
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Checks whether an upkeep is to be performed.
    /// @return upkeepNeeded_ A boolean indicating whether an upkeep is to be performed.
    /// @return performData_ The calldata to be passed to the upkeep function.
    function checkUpkeep(bytes calldata checkData)
        external
        override
        cannotExecute
        returns (bool upkeepNeeded_, bytes memory performData_)
    {
        if (!SAFE.isModuleEnabled(address(this)) && _isReady()) {
            // NOTE: explicit early return to checking rest of logic if these conditions are not met
            return (upkeepNeeded_, performData_);
        }

        // total ebtc staked
        uint256 storedTotalAssets = STAKED_EBTC.storedTotalAssets();
        // total ebtc staked including left over rewards from the previous cycle
        uint256 totalBalance = STAKED_EBTC.totalBalance();
        uint256 residual = totalBalance - storedTotalAssets;
        uint256 ebtcYield = storedTotalAssets * annualizedYieldBPS / (BPS * WEEKS_IN_YEAR);

        if (residual >= ebtcYield) {
            // there's still enough residual balance in the contract for this week
            // performUpkeep still needs to be called to update lastProcessingTimestamp
            // no need to claim additional PYS
            return (true, abi.encode(0, 0));
        }

        uint256 ebtcAmountRequired = ebtcYield - residual;
        uint256 stEthToClaim = ebtcAmountRequired * 1e18 / PRICE_FEED.fetchPrice();
        uint256 collSharesToClaim = COLLATERAL.getSharesByPooledEth(stEthToClaim);
        uint256 collSharesAvailable = _getFeeRecipientCollShares();

        // cap by collSharesAvailable
        if (collSharesToClaim > collSharesAvailable) {
            collSharesToClaim = collSharesAvailable;
        }

        return (true, abi.encode(collSharesToClaim, ebtcAmountRequired));
    }

    ////////////////////////////////////////////////////////////////////////////
    // INTERNAL
    ////////////////////////////////////////////////////////////////////////////

    function _isReady() private view returns (bool) {
        if (lastProcessingTimestamp == 0) {
            // return true if we are executing for the first time
            return true;
        } else {
            return (block.timestamp - lastProcessingTimestamp) <= REWARDS_CYCLE_LENGTH;
        }        
    }

    function _lastRewardCycle() private view returns (uint256) {
        LinearRewardsErc4626.RewardsCycleData memory cycleData = STAKED_EBTC.rewardsCycleData();
        return cycleData.lastSync;
    }

    function _getFeeRecipientCollShares() private returns (uint256) {
        uint256 pendingShares = ACTIVE_POOL.getSystemCollShares() - CDP_MANAGER.getSyncedSystemCollShares();
        return ACTIVE_POOL.getFeeRecipientClaimableCollShares() + pendingShares;
    }

    function _claimFeeRecipientCollShares(uint256 collSharesToClaim) private returns (uint256) {
        uint256 stEthBefore = COLLATERAL.balanceOf(address(SAFE));
        _checkTransactionAndExecute(
            SAFE, 
            address(ACTIVE_POOL), 
            abi.encodeWithSelector(IActivePool.claimFeeRecipientCollShares.selector, collSharesToClaim)
        );
        return COLLATERAL.balanceOf(address(SAFE)) - stEthBefore;
    }

    function _approveAndWrap(uint256 stEthAmount) private returns (uint256) {
        _checkTransactionAndExecute(
            SAFE,
            address(COLLATERAL), 
            abi.encodeWithSelector(IERC20.approve.selector, address(wstETH), stEthAmount)
        );

        uint256 wstEthBefore = wstETH.balanceOf(address(SAFE));
        _checkTransactionAndExecute(
            SAFE,
            address(wstETH), 
            abi.encodeWithSelector(IWstEth.wrap.selector, stEthAmount)
        );

        _checkTransactionAndExecute(
            SAFE,
            address(COLLATERAL), 
            abi.encodeWithSelector(IERC20.approve.selector, address(wstETH), 0)
        );

        return wstETH.balanceOf(address(SAFE)) - wstEthBefore;
    }

    function _dexTrade(uint256 wstEthAmount, uint256 ebtcAmountRequired) private returns (uint256) {
        _checkTransactionAndExecute(
            SAFE,
            address(wstETH), 
            abi.encodeWithSelector(IERC20.approve.selector, address(DEX), wstEthAmount)
        );

        ISwapRouter.ExactInputParams memory params;

        params.amountIn = wstEthAmount;
        params.recipient = address(SAFE);
        params.path = swapPath;
        params.amountOutMinimum = ebtcAmountRequired * swapSlippageBPS / BPS;

        uint256 ebtcBefore = EBTC_TOKEN.balanceOf(address(SAFE));
        _checkTransactionAndExecute(
            SAFE, 
            address(DEX), 
            abi.encodeWithSelector(ISwapRouter.exactInput.selector, params)
        );

        _checkTransactionAndExecute(
            SAFE,
            address(wstETH), 
            abi.encodeWithSelector(IERC20.approve.selector, address(DEX), 0)
        );

        return EBTC_TOKEN.balanceOf(address(SAFE)) - ebtcBefore;
    }

    function _donate(uint256 ebtcAmount) private {
        _checkTransactionAndExecute(
            SAFE,
            address(EBTC_TOKEN), 
            abi.encodeWithSelector(IERC20.approve.selector, address(STAKED_EBTC), ebtcAmount)
        );

        _checkTransactionAndExecute(
            SAFE, 
            address(STAKED_EBTC), 
            abi.encodeWithSelector(IStakedEbtc.donate.selector, ebtcAmount)
        );

        _checkTransactionAndExecute(
            SAFE,
            address(EBTC_TOKEN), 
            abi.encodeWithSelector(IERC20.approve.selector, address(STAKED_EBTC), 0)
        );
    }
}
