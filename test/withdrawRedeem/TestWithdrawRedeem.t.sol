// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../BaseTest.sol";
import {
    StakedFraxFunctions
} from "../setMaxDistributionPerSecondPerAsset/TestSetMaxDistributionPerSecondPerAsset.t.sol";
import { mintDepositFunctions } from "../mintDeposit/TestMintAndDeposit.t.sol";

abstract contract RedeemWithdrawFunctions is BaseTest {
    function _stakedFrax_redeem(uint256 _shares, address _recipient) internal {
        hoax(_recipient);
        stakedEbtc.redeem(_shares, _recipient, _recipient);
    }

    function _stakedFrax_withdraw(uint256 _assets, address _recipient) internal {
        hoax(_recipient);
        stakedEbtc.withdraw(_assets, _recipient, _recipient);
    }
}

contract TestRedeemAndWithdraw is BaseTest, StakedFraxFunctions, mintDepositFunctions, RedeemWithdrawFunctions {
    /// FEATURE: redeem and withdraw

    using StakedEbtcStructHelper for *;

    address bob;
    address alice;
    address donald;

    address joe;

    function setUp() public override {
        /// BACKGROUND: deploy the StakedFrax contract
        /// BACKGROUND: 10% APY cap
        /// BACKGROUND: frax as the underlying asset
        /// BACKGROUND: TIMELOCK_ADDRESS set as the timelock address
        super.setUp();

        bob = labelAndDeal(address(1234), "bob");
        mintEbtcTo(bob, 5000 ether);
        vm.prank(bob);
        mockEbtc.approve(stakedFraxAddress, type(uint256).max);

        alice = labelAndDeal(address(2345), "alice");
        mintEbtcTo(alice, 5000 ether);
        vm.prank(alice);
        mockEbtc.approve(stakedFraxAddress, type(uint256).max);

        donald = labelAndDeal(address(3456), "donald");
        mintEbtcTo(donald, 5000 ether);
        vm.prank(donald);
        mockEbtc.approve(stakedFraxAddress, type(uint256).max);

        joe = labelAndDeal(address(4567), "joe");
        mintEbtcTo(joe, 5000 ether);
        vm.prank(joe);
        mockEbtc.approve(stakedFraxAddress, type(uint256).max);
    }

    function test_RedeemAllWithUnCappedRewards() public {
        //==============================================================================
        // Arrange
        //==============================================================================

        /// GIVEN: totalSupply is 1000
        assertEq(stakedEbtc.totalSupply(), 1000 ether, "setup:totalSupply should be 1000");

        /// GIVEN: storedTotalAssets is 1000
        assertEq(stakedEbtc.storedTotalAssets(), 1000 ether, "setup: storedTotalAssets should be 1000");

        /// GIVEN: maxDistributionPerSecondPerAsset is uncapped
        uint256 _maxDistributionPerSecondPerAsset = type(uint256).max;
        _stakedFrax_setMaxDistributionPerSecondPerAsset(_maxDistributionPerSecondPerAsset);

        /// GIVEN: timestamp is 400_000 seconds away from the end of the cycle
        uint256 _syncDuration = 400_000;
        mineBlocksToTimestamp(stakedEbtc.__rewardsCycleData().cycleEnd + rewardsCycleLength - _syncDuration);

        /// GIVEN: 600 FRAX is transferred as rewards
        uint256 _rewards = 600 ether;
     //   mintFraxTo(stakedFraxAddress, _rewards);
        vm.prank(defaultGovernance);
        stakedEbtc.donate(_rewards);

        /// GIVEN: syncAndDistributeRewards is called
        stakedEbtc.syncRewardsAndDistribution();

        /// GIVEN: bob deposits 1000 FRAX
        _stakedFrax_deposit(1000 ether, bob);

        /// GIVEN: We wait 100_000 seconds
        uint256 _timeSinceLastRewardsDistribution = 100_000;
        mineBlocksBySecond(_timeSinceLastRewardsDistribution);

        //==============================================================================
        // Act
        //==============================================================================

        StakedFraxStorageSnapshot memory _initial_stakedFraxStorageSnapshot = stakedFraxStorageSnapshot(stakedEbtc);

        UserStorageSnapshot memory _initial_bobStorageSnapshot = userStorageSnapshot(bob, stakedEbtc);

        /// WHEN: bob redeems all of his FRAX
        uint256 _shares = stakedEbtc.balanceOf(bob);
        _stakedFrax_redeem(_shares, bob);

        DeltaStakedFraxStorageSnapshot memory _delta_stakedFraxStorageSnapshot = deltaStakedFraxStorageSnapshot(
            _initial_stakedFraxStorageSnapshot
        );

        DeltaUserStorageSnapshot memory _delta_bobStorageSnapshot = deltaUserStorageSnapshot(
            _initial_bobStorageSnapshot
        );

        //==============================================================================
        // Assert
        //==============================================================================

        assertEq({
            err: "THEN: totalSupply should decrease by _shares",
            left: _delta_stakedFraxStorageSnapshot.delta.totalSupply,
            right: _shares
        });
        assertLt({
            err: "THEN: totalSupply should decrease",
            left: _delta_stakedFraxStorageSnapshot.end.totalSupply,
            right: _delta_stakedFraxStorageSnapshot.start.totalSupply
        });

        uint256 _expectedWithdrawAmount = 1075e18 - 150e18;
        assertEq({
            err: "THEN: totalStored assets should change by +150 for rewards and -1125 for redeem",
            left: _delta_stakedFraxStorageSnapshot.delta.storedTotalAssets,
            right: _expectedWithdrawAmount
        });

        assertEq({
            err: "THEN: bob's balance should be 0",
            left: _delta_bobStorageSnapshot.end.stakedFrax.balanceOf,
            right: 0
        });
        assertEq({
            err: "THEN: bob's frax balance should have changed by 1075 (1000 + 75 rewards)",
            left: _delta_bobStorageSnapshot.delta.asset.balanceOf,
            right: 1075 ether
        });
    }

    function test_WithdrawWithUnCappedRewards() public {
        //==============================================================================
        // Arrange
        //==============================================================================

        /// GIVEN: totalSupply is 1000
        assertEq(stakedEbtc.totalSupply(), 1000 ether, "setup:totalSupply should be 1000");

        /// GIVEN: storedTotalAssets is 1000
        assertEq(stakedEbtc.storedTotalAssets(), 1000 ether, "setup: storedTotalAssets should be 1000");

        /// GIVEN: maxDistributionPerSecondPerAsset is uncapped
        uint256 _maxDistributionPerSecondPerAsset = type(uint256).max;
        _stakedFrax_setMaxDistributionPerSecondPerAsset(_maxDistributionPerSecondPerAsset);

        /// GIVEN: timestamp is 400_000 seconds away from the end of the cycle
        uint256 _syncDuration = 400_000;
        mineBlocksToTimestamp(stakedEbtc.__rewardsCycleData().cycleEnd + rewardsCycleLength - _syncDuration);

        /// GIVEN: 600 FRAX is transferred as rewards
        uint256 _rewards = 600 ether;
        //mintFraxTo(stakedFraxAddress, _rewards);
        vm.prank(defaultGovernance);
        stakedEbtc.donate(_rewards);

        /// GIVEN: syncAndDistributeRewards is called
        stakedEbtc.syncRewardsAndDistribution();

        /// GIVEN: bob deposits 1000 FRAX
        _stakedFrax_deposit(1000 ether, bob);

        /// GIVEN: We wait 100_000 seconds
        uint256 _timeSinceLastRewardsDistribution = 100_000;
        mineBlocksBySecond(_timeSinceLastRewardsDistribution);

        //==============================================================================
        // Act
        //==============================================================================

        StakedFraxStorageSnapshot memory _initial_stakedFraxStorageSnapshot = stakedFraxStorageSnapshot(stakedEbtc);

        UserStorageSnapshot memory _initial_bobStorageSnapshot = userStorageSnapshot(bob, stakedEbtc);

        /// WHEN: bob withdraws 1000 frax
        _stakedFrax_withdraw(1000 ether, bob);

        DeltaStakedFraxStorageSnapshot memory _delta_stakedFraxStorageSnapshot = deltaStakedFraxStorageSnapshot(
            _initial_stakedFraxStorageSnapshot
        );

        DeltaUserStorageSnapshot memory _delta_bobStorageSnapshot = deltaUserStorageSnapshot(
            _initial_bobStorageSnapshot
        );

        //==============================================================================
        // Assert
        //==============================================================================

        uint256 _expectedShares = (uint256(2000e18) * 1000e18) / 2150e18;
        assertApproxEqAbs({
            err: "/// THEN: totalSupply should decrease by totalSupply / totalAssets * 1000",
            left: _delta_stakedFraxStorageSnapshot.delta.totalSupply,
            right: _expectedShares,
            maxDelta: 1
        });
        assertLt({
            err: "/// THEN: totalSupply should decrease",
            left: _delta_stakedFraxStorageSnapshot.end.totalSupply,
            right: _delta_stakedFraxStorageSnapshot.start.totalSupply
        });
        assertEq({
            err: "/// THEN: totalStored assets should change by -1000 +150 for rewards",
            left: _delta_stakedFraxStorageSnapshot.delta.storedTotalAssets,
            right: 850e18
        });
        assertApproxEqAbs({
            err: "/// THEN: bob's balance should be 1000 - _expectedShares",
            left: _delta_bobStorageSnapshot.end.stakedFrax.balanceOf,
            right: 1000e18 - _expectedShares,
            maxDelta: 1
        });
        assertApproxEqAbs({
            err: "/// THEN: bob's staked frax balance should have changed by _expectedShares",
            left: _delta_bobStorageSnapshot.delta.stakedFrax.balanceOf,
            right: _expectedShares,
            maxDelta: 1
        });
        assertEq({
            err: "/// THEN: bob's frax balance should have changed by 1000",
            left: _delta_bobStorageSnapshot.delta.asset.balanceOf,
            right: 1000 ether
        });
    }
}
