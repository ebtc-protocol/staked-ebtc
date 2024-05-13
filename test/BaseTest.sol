// SPDX-License-Identifier: ISC
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdMath.sol";
import { StakedEbtc } from "../src/StakedEbtc.sol";
import { Governor } from "../src/Dependencies/Governor.sol";
import { StakedEbtcStructHelper } from "./helpers/StakedEbtcStructHelper.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract BaseTest is Test {
    using StakedEbtcStructHelper for *;

    StakedEbtc public stakedEbtc;
    address public stakedFraxAddress;
    uint256 public rewardsCycleLength;
    IERC20 public mockEbtc;
    address internal defaultGovernance;
    Governor internal governor;

    function setUp() public {
        defaultGovernance = vm.addr(0x123456);
        governor = new Governor(defaultGovernance);
        mockEbtc = new ERC20Mock();

        uint256 TEN_PERCENT = 3_022_266_030; // per second rate compounded week each block (1.10^(365 * 86400 / 12) - 1) / 12 * 1e18

        stakedEbtc = new StakedEbtc({
            _underlying: mockEbtc,
            _name: "Staked Ebtc",
            _symbol: "stEbtc",
            _rewardsCycleLength: 7 days,
            _maxDistributionPerSecondPerAsset: TEN_PERCENT,
            _authorityAddress: address(governor)
        });

        vm.startPrank(defaultGovernance);
        governor.setRoleCapability(12, address(stakedEbtc), StakedEbtc.setMaxDistributionPerSecondPerAsset.selector, true);
        governor.setUserRole(defaultGovernance, 12, true);
        vm.stopPrank();

        rewardsCycleLength = stakedEbtc.REWARDS_CYCLE_LENGTH();
    }
}

function calculateDeltaRewardsCycleData(
    StakedEbtc.RewardsCycleData memory _initial,
    StakedEbtc.RewardsCycleData memory _final
) pure returns (StakedEbtc.RewardsCycleData memory _delta) {
    _delta.cycleEnd = uint32(stdMath.delta(_initial.cycleEnd, _final.cycleEnd));
    _delta.lastSync = uint32(stdMath.delta(_initial.lastSync, _final.lastSync));
    _delta.rewardCycleAmount = uint192(stdMath.delta(_initial.rewardCycleAmount, _final.rewardCycleAmount));
}

struct StakedFraxStorageSnapshot {
    address stakedFraxAddress;
    uint256 maxDistributionPerSecondPerAsset;
    StakedEbtc.RewardsCycleData rewardsCycleData;
    uint256 lastRewardsDistribution;
    uint256 storedTotalAssets;
    uint256 totalSupply;
}

struct DeltaStakedFraxStorageSnapshot {
    StakedFraxStorageSnapshot start;
    StakedFraxStorageSnapshot end;
    StakedFraxStorageSnapshot delta;
}

function stakedFraxStorageSnapshot(StakedEbtc _stakedFrax) view returns (StakedFraxStorageSnapshot memory _initial) {
    if (address(_stakedFrax) == address(0)) {
        return _initial;
    }
    _initial.stakedFraxAddress = address(_stakedFrax);
    _initial.maxDistributionPerSecondPerAsset = _stakedFrax.maxDistributionPerSecondPerAsset();
    _initial.rewardsCycleData = StakedEbtcStructHelper.__rewardsCycleData(_stakedFrax);
    _initial.lastRewardsDistribution = _stakedFrax.lastRewardsDistribution();
    _initial.storedTotalAssets = _stakedFrax.storedTotalAssets();
    _initial.totalSupply = _stakedFrax.totalSupply();
}

function calculateDeltaStakedFraxStorage(
    StakedFraxStorageSnapshot memory _initial,
    StakedFraxStorageSnapshot memory _final
) pure returns (StakedFraxStorageSnapshot memory _delta) {
    _delta.stakedFraxAddress = _initial.stakedFraxAddress == _final.stakedFraxAddress
        ? address(0)
        : _final.stakedFraxAddress;
    _delta.maxDistributionPerSecondPerAsset = stdMath.delta(
        _initial.maxDistributionPerSecondPerAsset,
        _final.maxDistributionPerSecondPerAsset
    );
    _delta.rewardsCycleData = calculateDeltaRewardsCycleData(_initial.rewardsCycleData, _final.rewardsCycleData);
    _delta.lastRewardsDistribution = stdMath.delta(_initial.lastRewardsDistribution, _final.lastRewardsDistribution);
    _delta.storedTotalAssets = stdMath.delta(_initial.storedTotalAssets, _final.storedTotalAssets);
    _delta.totalSupply = stdMath.delta(_initial.totalSupply, _final.totalSupply);
}

function deltaStakedFraxStorageSnapshot(
    StakedFraxStorageSnapshot memory _initial
) view returns (DeltaStakedFraxStorageSnapshot memory _final) {
    _final.start = _initial;
    _final.end = stakedFraxStorageSnapshot(StakedEbtc(_initial.stakedFraxAddress));
    _final.delta = calculateDeltaStakedFraxStorage(_final.start, _final.end);
}

//==============================================================================
// User Snapshot Functions
//==============================================================================

struct Erc20UserStorageSnapshot {
    uint256 balanceOf;
}

function calculateDeltaErc20UserStorageSnapshot(
    Erc20UserStorageSnapshot memory _initial,
    Erc20UserStorageSnapshot memory _final
) pure returns (Erc20UserStorageSnapshot memory _delta) {
    _delta.balanceOf = stdMath.delta(_initial.balanceOf, _final.balanceOf);
}

struct UserStorageSnapshot {
    address user;
    address stakedFraxAddress;
    uint256 balance;
    Erc20UserStorageSnapshot stakedFrax;
    Erc20UserStorageSnapshot asset;
}

struct DeltaUserStorageSnapshot {
    UserStorageSnapshot start;
    UserStorageSnapshot end;
    UserStorageSnapshot delta;
}

function userStorageSnapshot(
    address _user,
    StakedEbtc _stakedFrax
) view returns (UserStorageSnapshot memory _snapshot) {
    _snapshot.user = _user;
    _snapshot.stakedFraxAddress = address(_stakedFrax);
    _snapshot.balance = _user.balance;
    _snapshot.stakedFrax.balanceOf = _stakedFrax.balanceOf(_user);
    _snapshot.asset.balanceOf = IERC20(address(_stakedFrax.asset())).balanceOf(_user);
}

function calculateDeltaUserStorageSnapshot(
    UserStorageSnapshot memory _initial,
    UserStorageSnapshot memory _final
) pure returns (UserStorageSnapshot memory _delta) {
    _delta.user = _initial.user == _final.user ? address(0) : _final.user;
    _delta.stakedFraxAddress = _initial.stakedFraxAddress == _final.stakedFraxAddress
        ? address(0)
        : _final.stakedFraxAddress;
    _delta.balance = stdMath.delta(_initial.balance, _final.balance);
    _delta.stakedFrax = calculateDeltaErc20UserStorageSnapshot(_initial.stakedFrax, _final.stakedFrax);
    _delta.asset = calculateDeltaErc20UserStorageSnapshot(_initial.asset, _final.asset);
}

function deltaUserStorageSnapshot(
    UserStorageSnapshot memory _initial
) view returns (DeltaUserStorageSnapshot memory _snapshot) {
    _snapshot.start = _initial;
    _snapshot.end = userStorageSnapshot(_initial.user, StakedEbtc(_initial.stakedFraxAddress));
    _snapshot.delta = calculateDeltaUserStorageSnapshot(_snapshot.start, _snapshot.end);
}
