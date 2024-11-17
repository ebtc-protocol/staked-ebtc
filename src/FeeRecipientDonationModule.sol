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
import { IQuoterV2 } from "./Dependencies/IQuoterV2.sol";
import { IWstEth } from "./Dependencies/IWstEth.sol";
import { LinearRewardsErc4626 } from "./LinearRewardsErc4626.sol";
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
    IStakedEbtc public constant STAKED_EBTC = IStakedEbtc(0x5884055ca6CacF53A39DA4ea76DD88956baFAee0);
    ISwapRouter public constant DEX = ISwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    IQuoterV2 public constant QUOTER = IQuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);

    /// @notice eBTC techops multisig
    address public constant GOVERNANCE = 0x690C74AF48BE029e763E61b4aDeB10E06119D3ba;
    address public constant TREASURY = 0xD0A7A8B98957b9CD3cFB9c0425AbE44551158e9e;
    uint256 public constant WEEKS_IN_YEAR = 52;
    uint256 public constant BPS = 10000;
    /// @notice cap max slippage at 10% (90% minBPS)
    uint256 public constant MIN_BPS_LOWER_BOUND = 9000;
    /// @notice cap annualized yield at 20%
    uint256 public constant MAX_YIELD_BPS = 2000;


    ////////////////////////////////////////////////////////////////////////////
    // STORAGE
    ////////////////////////////////////////////////////////////////////////////
    address public guardian;
    address public keeper;

    uint256 public lastProcessedCycle;
    uint256 public annualizedYieldBPS;
    uint256 public minOutBPS;
    bytes public swapPath;
    uint256 public executionDelay;

    ////////////////////////////////////////////////////////////////////////////
    // ERRORS
    ////////////////////////////////////////////////////////////////////////////

    error NotGovernance(address caller);
    error NotGovernanceOrGuardian(address caller);
    error NotKeeper(address caller);

    error TooSoon(uint256 lastProcessedCycle, uint256 timestamp);

    error ZeroIntervalPeriod();
    error ZeroAddress();
    error ModuleMisconfigured();

    ////////////////////////////////////////////////////////////////////////////
    // EVENTS
    ////////////////////////////////////////////////////////////////////////////

    event GuardianUpdated(address indexed oldGuardian, address indexed newGuardian);
    event KeeperUpdated(address indexed oldKeeper, address indexed newKeeper);
    event SwapPathUpdated(bytes oldPath, bytes newPath);
    event AnnualizedYieldUpdated(uint256 oldYield, uint256 newYield);
    event MinOutUpdated(uint256 oldMinOut, uint256 newMinOut);
    event PerformedUpkeep(
        uint256 collSharesToClaim, 
        uint256 ebtcAmountRequired, 
        uint256 stEthClaimed, 
        uint256 wstEthAmount, 
        uint256 ebtcReceived
    );
    event ExecutionDelayUpdated(uint256 oldDelay, uint256 newDelay);

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
        if (msg.sender != keeper) revert NotKeeper(msg.sender);
        _;
    }

    /// @param _guardian Address allowed to pause contract
    constructor(
        address _guardian, 
        uint256 _annualizedYieldBPS,
        uint256 _minOutBPS,
        bytes memory _swapPath
    ) {
        if (_guardian == address(0)) revert ZeroAddress();
        require(_isValidSwapPath(_swapPath), "bad swapPath");

        guardian = _guardian;
        annualizedYieldBPS = _annualizedYieldBPS;
        swapPath = _swapPath;

        minOutBPS = _minOutBPS;
        require(minOutBPS <= BPS && minOutBPS >= MIN_BPS_LOWER_BOUND);

        // keeper will be set later
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
        emit GuardianUpdated(oldGuardian, _guardian);
    }

    /// @notice  Updates the keeper address. Only callable by governance.
    /// @param _keeper Address which will become keeper
    function setKeeper(address _keeper) external onlyGovernance {
        if (_keeper == address(0)) revert ZeroAddress();
        address oldKeeper = keeper;
        keeper = _keeper;
        emit KeeperUpdated(oldKeeper, _keeper);
    }

    function setSwapPath(bytes calldata _swapPath) external onlyGovernance {
        require(_isValidSwapPath(_swapPath), "bad swapPath");

        emit SwapPathUpdated(swapPath, _swapPath);
        swapPath = _swapPath;
    }

    function setAnnualizedYieldBPS(uint256 _annualizedYieldBPS) external onlyGovernance {
        require(_annualizedYieldBPS <= MAX_YIELD_BPS);

        emit AnnualizedYieldUpdated(annualizedYieldBPS, _annualizedYieldBPS);
        annualizedYieldBPS = _annualizedYieldBPS;
    }

    function setMinOutBPS(uint256 _minOutBPS) external onlyGovernance {
        require(minOutBPS <= BPS && minOutBPS >= MIN_BPS_LOWER_BOUND);

        emit MinOutUpdated(minOutBPS, _minOutBPS);
        minOutBPS = _minOutBPS;
    }

    /// @notice execution delay controls when automation will trigger
    function setExecutionDelay(uint256 _executionDelay) external onlyGovernance() {
        require(_executionDelay <= STAKED_EBTC.REWARDS_CYCLE_LENGTH());

        emit ExecutionDelayUpdated(executionDelay, _executionDelay);
        executionDelay = _executionDelay;
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
    // PUBLIC: TechOps
    ////////////////////////////////////////////////////////////////////////////

    function manualUpkeep(bytes calldata performData) external onlyGovernance {
        _performUpkeep(performData);
    }

    function claimFeeRecipientCollShares(uint256 collSharesToClaim) external onlyGovernance {
        _claimFeeRecipientCollShares(collSharesToClaim);
    }

    function sendFeeRecipientCollSharesToTreasury(uint256 collSharesToSend) external onlyGovernance {
        _sendFeeToTreasury(collSharesToSend);
    }

    function sendEbtcToTreasury(uint256 amountToSend) external onlyGovernance {
        _sendEbtcToTreasury(amountToSend);
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
            revert TooSoon(lastProcessedCycle, block.timestamp);
        }

        _performUpkeep(performData);
    }

    function _performUpkeep(bytes calldata performData) internal {
        (uint256 collSharesToClaim, uint256 ebtcAmountRequired) = abi.decode(performData, (uint256, uint256));

        uint256 stEthClaimed;
        uint256 wstEthAmount;
        uint256 ebtcReceived;
        if (collSharesToClaim > 0) {
            stEthClaimed = _claimFeeRecipientCollShares(collSharesToClaim);

            wstEthAmount = _approveAndWrap(stEthClaimed);

            ebtcReceived = _dexTrade(wstEthAmount, ebtcAmountRequired);

            _donate(ebtcReceived);
        }

        emit PerformedUpkeep(
            collSharesToClaim, ebtcAmountRequired, stEthClaimed, wstEthAmount, ebtcReceived
        );

        // syncRewardsAndDistribution is called elsewhere after REWARDS_CYCLE_LENGTH
        lastProcessedCycle = getCurrentCycle();
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
        if (!SAFE.isModuleEnabled(address(this)) || !_isReady() || !_isValidSwapPath(swapPath)) {
            // NOTE: explicit early return to checking rest of logic if these conditions are not met
            return (upkeepNeeded_, performData_);
        }

        // sync rewards to get the most up to date numbers
        STAKED_EBTC.syncRewardsAndDistribution();

        /// @audit this will be incorrect since it's not the total assets at end of epoch
        // We would instead have to check against the amount of assets at the end of the epoch

        // Current Assets (Since we accrued until now)
        uint256 totalAssetsToGiveYieldTo = STAKED_EBTC.storedTotalAssets();

        // We need to add the future assets from rewards, at end of this cycle
        LinearRewardsErc4626.RewardsCycleData memory data = STAKED_EBTC.rewardsCycleData();

        // Accrue in the future // NOTE: We can skip the accrual with a bit extra work
        if(data.cycleEnd > block.timestamp) {
    
            uint256 timeToEnd = data.cycleEnd - data.lastSync; // Now
            uint256 newRewards = STAKED_EBTC.calculateRewardsToDistribute(data, timeToEnd);

            // NOTE: `calculateRewardsToDistribute` caps the yield to `maxDistributionPerSecondPerAsset`
            // Technically stBTC can be made to compound, making the amt of rewards granted
            //  higher than what we can calculate, it's QA at most
            totalAssetsToGiveYieldTo += newRewards;
        }


        uint256 ebtcAmountRequired = totalAssetsToGiveYieldTo * annualizedYieldBPS / (BPS * WEEKS_IN_YEAR);

        uint256 stEthToClaim = ebtcAmountRequired * 1e18 / PRICE_FEED.fetchPrice();
        uint256 collSharesToClaim = COLLATERAL.getSharesByPooledEth(stEthToClaim);
        uint256 collSharesAvailable = _getFeeRecipientCollShares();

        // cap by collSharesAvailable
        if (collSharesToClaim > collSharesAvailable) {
            collSharesToClaim = collSharesAvailable;

            // recaclulate expected ebtcAmount after capping collSharesToClaim
            ebtcAmountRequired = COLLATERAL.getPooledEthByShares(collSharesToClaim) * PRICE_FEED.fetchPrice() / 1e18;
        }

        return (true, abi.encode(collSharesToClaim, ebtcAmountRequired));
    }

    function getCurrentCycle() public view returns (uint256) {
        // Truncation of current time gives us current cycle
        // stBTC doesn't track cycle internally so we simply track it in this way
        // We can get the `start` by multiplying * STAKED_EBTC.REWARDS_CYCLE_LENGTH()
        // We can get the `end` by adding STAKED_EBTC.REWARDS_CYCLE_LENGTH() to the `start`
        uint256 currentCycle = block.timestamp / STAKED_EBTC.REWARDS_CYCLE_LENGTH();

        return currentCycle;
    }

    function getTimePassedInCycle() public view returns (uint256) {
        // By definition each cycle ends and starts at REWARDS_CYCLE_LENGTH
        uint256 timeInCycle = block.timestamp % STAKED_EBTC.REWARDS_CYCLE_LENGTH();

        // Therefore the remainder is the time in the cycle
        return timeInCycle;
    }

    function isLateEnoughInTheCycle() public view returns (bool) {
        uint256 passedInCycle = getTimePassedInCycle();
        return passedInCycle > executionDelay;
    }

    ////////////////////////////////////////////////////////////////////////////
    // INTERNAL
    ////////////////////////////////////////////////////////////////////////////

    function _isReady() private view returns (bool) {

        uint256 currentCycle = getCurrentCycle();

        /// INVARIANT: By definition we can never process in the future
        require(currentCycle >= lastProcessedCycle);

        // We already processed this epoch
        if(lastProcessedCycle == currentCycle) {
            return false;
        }

        // Edge case, we skipped a process
        if(currentCycle > lastProcessedCycle + 1) {
            // Donate urgently, we skipped an epoch
            return true;
        }


        // Sanity check, we are in the new cycle and we need to see if we're late enough
        require(lastProcessedCycle + 1 == currentCycle);
        // Check if late enough
        return isLateEnoughInTheCycle();
    }

    function _isValidSwapPath(bytes memory _swapPath) private returns (bool) {
        (uint256 spotPrice, , , ) = QUOTER.quoteExactInput(_swapPath, wstETH.getWstETHByStETH(1e18));
        uint256 oraclePrice = PRICE_FEED.fetchPrice();

        uint256 absDiff;
        if (spotPrice > oraclePrice) {
            absDiff = spotPrice - oraclePrice;
        } else if (spotPrice < oraclePrice) {
            absDiff = oraclePrice - spotPrice;
        }

        // make sure price diff % never exceeds minOut %
        return (absDiff * BPS / oraclePrice) <= (BPS - minOutBPS);
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

    function _sendFeeToTreasury(uint256 sharesToSend) private {
        _checkTransactionAndExecute(
            SAFE, 
            address(COLLATERAL), 
            abi.encodeWithSelector(ICollateral.transferShares.selector, TREASURY, sharesToSend)
        );        
    }

    function _sendEbtcToTreasury(uint256 amountToSend) private {
        _checkTransactionAndExecute(
            SAFE, 
            address(EBTC_TOKEN), 
            abi.encodeWithSelector(IERC20.transfer.selector, TREASURY, amountToSend)
        );        
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
        params.amountOutMinimum = ebtcAmountRequired * minOutBPS / BPS;

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
