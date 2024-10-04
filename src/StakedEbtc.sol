// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeCastLib } from "@solmate/utils/SafeCastLib.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { LinearRewardsErc4626, ERC20 } from "./LinearRewardsErc4626.sol";
import { AuthNoOwner } from "./Dependencies/AuthNoOwner.sol";

/// @title Staked eBTC
/// @notice A ERC4626 Vault implementation with linear rewards, rewards can be capped
contract StakedEbtc is LinearRewardsErc4626, AuthNoOwner {
    using SafeTransferLib for ERC20;
    using SafeCastLib for *;

    /// @notice The maximum amount of rewards that can be distributed per second per 1e18 asset
    uint256 public maxDistributionPerSecondPerAsset;

    event Donation(address indexed donor, uint256 amount);

    /// @notice Receive an eBTC donation from an authorized donor
    function donate(uint256 amount) external requiresAuth {
        totalBalance += amount;
        asset.safeTransferFrom(msg.sender, address(this), amount);
        emit Donation(msg.sender, amount);
    }

    /// @notice Sweep unauthorized donations and extra tokens
    function sweep(address token) external requiresAuth {
        if (token == address(asset)) {
            uint256 currentBalance = asset.balanceOf(address(this));
            if (currentBalance > totalBalance) {
                unchecked {
                    asset.safeTransfer(msg.sender, currentBalance - totalBalance);
                }
            }
        } else {
            ERC20(token).safeTransfer(msg.sender, ERC20(token).balanceOf(address(this)));
        }
    }
    
    /// @param _underlying The erc20 asset deposited
    /// @param _name The name of the vault
    /// @param _symbol The symbol of the vault
    /// @param _rewardsCycleLength The length of the rewards cycle in seconds
    /// @param _maxDistributionPerSecondPerAsset The maximum amount of rewards that can be distributed per second per 1e18 asset
    constructor(
        IERC20 _underlying,
        string memory _name,
        string memory _symbol,
        uint32 _rewardsCycleLength,
        uint256 _maxDistributionPerSecondPerAsset,
        address _authorityAddress,
        address _feeRecipient
    ) LinearRewardsErc4626(ERC20(address(_underlying)), _name, _symbol, _rewardsCycleLength, _feeRecipient) {
        if (_maxDistributionPerSecondPerAsset > type(uint64).max) {
            _maxDistributionPerSecondPerAsset = type(uint64).max;
        }

        maxDistributionPerSecondPerAsset = _maxDistributionPerSecondPerAsset;
        _initializeAuthority(_authorityAddress);
    }

    /// @notice The ```SetMaxDistributionPerSecondPerAsset``` event is emitted when the maxDistributionPerSecondPerAsset is set
    /// @param oldMax The old maxDistributionPerSecondPerAsset value
    /// @param newMax The new maxDistributionPerSecondPerAsset value
    event SetMaxDistributionPerSecondPerAsset(uint256 oldMax, uint256 newMax);

    /// @notice The ```setMaxDistributionPerSecondPerAsset``` function sets the maxDistributionPerSecondPerAsset
    /// @dev This function can only be called by the timelock, caps the value to type(uint64).max
    /// @param _maxDistributionPerSecondPerAsset The maximum amount of rewards that can be distributed per second per 1e18 asset
    function setMaxDistributionPerSecondPerAsset(uint256 _maxDistributionPerSecondPerAsset) external requiresAuth {
        syncRewardsAndDistribution();

        // NOTE: prevents bricking the contract via overflow
        if (_maxDistributionPerSecondPerAsset > type(uint64).max) {
            _maxDistributionPerSecondPerAsset = type(uint64).max;
        }

        emit SetMaxDistributionPerSecondPerAsset({
            oldMax: maxDistributionPerSecondPerAsset,
            newMax: _maxDistributionPerSecondPerAsset
        });

        maxDistributionPerSecondPerAsset = _maxDistributionPerSecondPerAsset;
    }

    /// @notice Sets the ```minRewardsPerPeriod``` required to start the next rewards cycle
    /// @param _minRewards minimum amount of rewards required to start the next rewards cycle
    function setMinRewardsPerPeriod(uint256 _minRewards) external requiresAuth {
        _setMinRewardsPerPeriod(_minRewards);
    }

    /// @notice Sets the ```mintingFee``` required deposit and mint
    /// @param _mintingFee the amount of minting fee in FEE_PRECISION
    function setMintingFee(uint256 _mintingFee) external requiresAuth {
        _setMintingFee(_mintingFee);
    }

    /// @notice The ```calculateRewardsToDistribute``` function calculates the amount of rewards to distribute based on the rewards cycle data and the time passed
    /// @param _rewardsCycleData The rewards cycle data
    /// @param _deltaTime The time passed since the last rewards distribution
    /// @return _rewardToDistribute The amount of rewards to distribute
    function calculateRewardsToDistribute(
        RewardsCycleData memory _rewardsCycleData,
        uint256 _deltaTime
    ) public view override returns (uint256 _rewardToDistribute) {
        _rewardToDistribute = super.calculateRewardsToDistribute({
            _rewardsCycleData: _rewardsCycleData,
            _deltaTime: _deltaTime
        });

        // Cap rewards
        uint256 _maxDistribution = (maxDistributionPerSecondPerAsset * _deltaTime * storedTotalAssets) / PRECISION;
        if (_rewardToDistribute > _maxDistribution) {
            _rewardToDistribute = _maxDistribution;
        }
    }
}
