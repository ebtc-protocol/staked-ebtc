// SPDX-License-Identifier: ISC
pragma solidity ^0.8.20;

import "../BaseTest.sol";
import {
    StakedFraxFunctions
} from "../setMaxDistributionPerSecondPerAsset/TestSetMaxDistributionPerSecondPerAsset.t.sol";

abstract contract mintDepositFunctions is BaseTest {
    function _stakedFrax_mint(uint256 _amount, address _recipient) internal {
        hoax(_recipient);
        stakedEbtc.mint(_amount, _recipient);
    }

    function _stakedFrax_deposit(uint256 _amount, address _recipient) internal {
        hoax(_recipient);
        stakedEbtc.deposit(_amount, _recipient);
    }
}

contract TestMintAndDeposit is BaseTest, StakedFraxFunctions, mintDepositFunctions {
    /// FEATURE: mint and deposit

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

    function test_CanDepositNoRewards() public {
        /// SCENARIO: No rewards distribution, A user deposits 1000 FRAX and should have 50% of the shares

        //==============================================================================
        // Act
        //==============================================================================

        StakedFraxStorageSnapshot memory _initial_stakedFraxStorageSnapshot = stakedFraxStorageSnapshot(stakedEbtc);

        /// WHEN: bob deposits 1000 FRAX
        _stakedFrax_deposit(1000 ether, bob);

        DeltaStakedFraxStorageSnapshot memory _delta_stakedFraxStorageSnapshot = deltaStakedFraxStorageSnapshot(
            _initial_stakedFraxStorageSnapshot
        );

        //==============================================================================
        // Assert
        //==============================================================================

        /// THEN: The user should have 1000 shares
        assertEq(stakedEbtc.balanceOf(bob), 1000 ether, "THEN: The user should have 2000 shares");

        /// THEN: The totalSupply should have increased by 1000 shares
        assertEq(
            _delta_stakedFraxStorageSnapshot.delta.totalSupply,
            1000 ether,
            "THEN: THe totalSupply should have increased by 1000 shares"
        );

        /// THEN: The totalSupply should be 2000 shares
        assertEq(
            _delta_stakedFraxStorageSnapshot.end.totalSupply,
            2000 ether,
            "THEN: The totalSupply should be 2000 shares"
        );

        /// THEN: The storedTotalAssets should have increased by 1000 FRAX
        assertEq(
            _delta_stakedFraxStorageSnapshot.delta.storedTotalAssets,
            1000 ether,
            "THEN: The storedTotalAssets should have increased by 1000 FRAX"
        );

        /// THEN: storedTotalAssets should be 2000 FRAX
        assertEq(
            _delta_stakedFraxStorageSnapshot.end.storedTotalAssets,
            2000 ether,
            "THEN: storedTotalAssets should be 2000 FRAX"
        );
    }

    function test_CanDepositAndMintWithRewardsCappedRewards() public {
        /// SCENARIO: A user deposits 1000 FRAX and should have 50% of the shares, 600 FRAX is distributed as rewards, uncapped

        //==============================================================================
        // Arrange
        //==============================================================================

        StakedFraxStorageSnapshot memory _initial_stakedFraxSnapshot = stakedFraxStorageSnapshot(stakedEbtc);

        /// GIVEN: maxDistributionPerSecondPerAsset is at 3_033_347_948 per second per 1e18 asset (roughly 10% APY)
        uint256 _maxDistributionPerSecondPerAsset = 3_033_347_948;
        _stakedFrax_setMaxDistributionPerSecondPerAsset(_maxDistributionPerSecondPerAsset);

        /// GIVEN: timestamp is 400_000 seconds away from the end of the cycle
        uint256 _syncDuration = 400_000;
        mineBlocksToTimestamp(stakedEbtc.__rewardsCycleData().cycleEnd + rewardsCycleLength - _syncDuration);

        /// GIVEN: 600 FRAX is transferred as rewards
        uint256 _rewards = 600 ether;
//        mintEbtcTo(stakedFraxAddress, _rewards);
        vm.prank(defaultGovernance);
        stakedEbtc.donate(_rewards);

        /// GIVEN: syncAndDistributeRewards is called
        stakedEbtc.syncRewardsAndDistribution();

        /// GIVEN: We wait 100_000 seconds
        uint256 _timeSinceLastRewardsDistribution = 100_000;
        mineBlocksBySecond(_timeSinceLastRewardsDistribution);

        //==============================================================================
        // Act
        //==============================================================================

        DeltaStakedFraxStorageSnapshot memory _second_deltaStakedFraxStorageSnapshot = deltaStakedFraxStorageSnapshot(
            _initial_stakedFraxSnapshot
        );

        /// WHEN: A user deposits 1000 FRAX
        _stakedFrax_deposit(1000 ether, bob);

        DeltaStakedFraxStorageSnapshot memory _third_deltaStakedFraxStorageSnapshot = deltaStakedFraxStorageSnapshot(
            _second_deltaStakedFraxStorageSnapshot.start
        );

        //==============================================================================
        // Assert
        //==============================================================================

        uint256 _expectedRewards = (1000e18 * _maxDistributionPerSecondPerAsset * _timeSinceLastRewardsDistribution) /
            1e18;
        /// THEN: the storedTotalAssets should have increased by 150 frax for the rewards and 1000 frax for the deposit
        assertEq(
            _third_deltaStakedFraxStorageSnapshot.delta.storedTotalAssets,
            1000 ether + _expectedRewards,
            "storedTotalAssets should have increased by _expectedFrax for the rewards and 1000 frax for the deposit"
        );

        // _expected = newAssets / sharePrice, sharePrice = assets / shares
        uint256 _expectedShares = (uint256(1000e18) * 1000e18) / (1000e18 + _expectedRewards);
        /// THEN: The user should have 1000e18 * 1000e18 / 1150e18 shares
        assertEq(
            stakedEbtc.balanceOf(bob),
            _expectedShares,
            "THEN: The user should have 1000e18 * 1000e18 / (1000 + _expectedRewards) shares"
        );

        /// THEN: The totalSupply should have increased by _expectedShares
        assertEq(
            _third_deltaStakedFraxStorageSnapshot.delta.totalSupply,
            _expectedShares,
            " THEN: The totalSupply should have increased by _expectedShares"
        );
    }

    function test_CanMintWithRewardsCappedRewards() public {
        /// SCENARIO: A user deposits 1000 FRAX and should have 50% of the shares, 600 FRAX is distributed as rewards, uncapped

        //==============================================================================
        // Arrange
        //==============================================================================

        /// GIVEN: maxDistributionPerSecondPerAsset is at 3_033_347_948 per second per 1e18 asset (roughly 10% APY)
        uint256 _maxDistributionPerSecondPerAsset = 3_033_347_948;
        _stakedFrax_setMaxDistributionPerSecondPerAsset(_maxDistributionPerSecondPerAsset);

        /// GIVEN: timestamp is 400_000 seconds away from the end of the cycle
        uint256 _syncDuration = 400_000;
        mineBlocksToTimestamp(stakedEbtc.__rewardsCycleData().cycleEnd + rewardsCycleLength - _syncDuration);

        /// GIVEN: 600 FRAX is transferred as rewards
        uint256 _rewards = 600 ether;
       // mintFraxTo(stakedFraxAddress, _rewards);
        vm.prank(defaultGovernance);
        stakedEbtc.donate(_rewards);

        /// GIVEN: syncAndDistributeRewards is called
        stakedEbtc.syncRewardsAndDistribution();

        /// GIVEN: We wait 100_000 seconds
        uint256 _timeSinceLastRewardsDistribution = 100_000;
        mineBlocksBySecond(_timeSinceLastRewardsDistribution);

        //==============================================================================
        // Act
        //==============================================================================

        StakedFraxStorageSnapshot memory _initial_stakedFraxSnapshot = stakedFraxStorageSnapshot(stakedEbtc);

        /// WHEN: A user mints 1000 FRAX
        // uint256 _expectedSharesToMint = stakedFrax.convertToShares(1000 ether);
        _stakedFrax_mint(1000 ether, bob);

        DeltaStakedFraxStorageSnapshot memory _fourth_deltaStakedFraxStorageSnapshot = deltaStakedFraxStorageSnapshot(
            _initial_stakedFraxSnapshot
        );

        //==============================================================================
        // Assert
        //==============================================================================

        uint256 _expectedRewards = (1000e18 * _maxDistributionPerSecondPerAsset * _timeSinceLastRewardsDistribution) /
            1e18;
        uint256 _expectedSharePrice = (1000 ether + _expectedRewards) / 1000;
        uint256 _expectedAmountTransferred = (1000 ether * _expectedSharePrice) / 1e18;
        // Expected transfer amount = shares * sharePrice, sharePrice = 1150 / 1000.  => 1000 ether + _expectedRewards frax transferred
        /// THEN: the storedTotalAssets should have increased by 150 frax for the rewards and 1150 frax for the mint
        assertEq(
            _fourth_deltaStakedFraxStorageSnapshot.delta.storedTotalAssets,
            _expectedAmountTransferred + _expectedRewards,
            "storedTotalAssets should have increased by _expectedRewards frax for the rewards and _expectedAmountTransferred frax for the mint"
        );

        /// THEN: the user should have 1000 shares
        assertEq(stakedEbtc.balanceOf(bob), 1000 ether, "THEN: the user should have 1000 shares");

        /// THEN: The totalSupply should have increased by _expectedShares
        assertEq(
            _fourth_deltaStakedFraxStorageSnapshot.delta.totalSupply,
            1000 ether,
            " THEN: The totalSupply should have increased by 1000"
        );
    }

    function test_CanMintWithRewardsNoCap() public {
        /// SCENARIO: A user deposits 1000 FRAX and should have 50% of the shares, 600 FRAX is distributed as rewards, uncapped

        //==============================================================================
        // Arrange
        //==============================================================================

        uint256 _maxDistributionPerSecondPerAsset = type(uint256).max;
        uint256 _syncDuration = 400_000;
        uint256 _timeSinceLastRewardsDistribution = 100_000;
        uint256 _rewards = 600 ether;

        StakedFraxStorageSnapshot memory _initial_stakedFraxSnapshot = stakedFraxStorageSnapshot(stakedEbtc);

        /// GIVEN: maxDistributionPerSecondPerAsset is uncapped
        _stakedFrax_setMaxDistributionPerSecondPerAsset(_maxDistributionPerSecondPerAsset);

        /// GIVEN: timestamp is 400_000 seconds away from the end of the cycle
        mineBlocksToTimestamp(stakedEbtc.__rewardsCycleData().cycleEnd + rewardsCycleLength - _syncDuration);

        /// GIVEN: 600 FRAX is transferred as rewards
   //     mintFraxTo(stakedFraxAddress, _rewards);
        vm.prank(defaultGovernance);
        stakedEbtc.donate(_rewards);

        /// GIVEN: syncAndDistributeRewards is called
        stakedEbtc.syncRewardsAndDistribution();

        /// GIVEN: We wait 100_000 seconds
        mineBlocksBySecond(_timeSinceLastRewardsDistribution);

        //==============================================================================
        // Act
        //==============================================================================

        DeltaStakedFraxStorageSnapshot memory _second_deltaStakedFraxStorageSnapshot = deltaStakedFraxStorageSnapshot(
            _initial_stakedFraxSnapshot
        );

        /// WHEN: A user mints 1000 FRAX
        _stakedFrax_mint(1000 ether, bob);

        DeltaStakedFraxStorageSnapshot memory _third_deltaSavingsFraxStorageSnapshot = deltaStakedFraxStorageSnapshot(
            _second_deltaStakedFraxStorageSnapshot.start
        );

        //==============================================================================
        // Assert
        //==============================================================================

        /// THEN: the storedTotalAssets should have increased by 150 frax for the rewards and 1150 frax for the mint
        assertEq(
            _third_deltaSavingsFraxStorageSnapshot.delta.storedTotalAssets,
            1300 ether,
            "storedTotalAssets should have increased by 150 frax for the rewards and 1000 frax for the mint"
        );

        /// THEN: the user should have 1000 shares
        assertEq(stakedEbtc.balanceOf(bob), 1000 ether, "THEN: the user should have 1000 shares");
    }

    function test_CanDepositWithRewardsCap() public {
        /// SCENARIO: A user deposits 1000 FRAX and should have 50% of the shares, 600 FRAX is distributed as rewards, uncapped

        //==============================================================================
        // Arrange
        //==============================================================================

        uint256 _maxDistributionPerSecondPerAsset = type(uint256).max;
        uint256 _syncDuration = 400_000;
        uint256 _timeSinceLastRewardsDistribution = 100_000;
        uint256 _rewards = 600 ether;

        StakedFraxStorageSnapshot memory _initial_stakedFraxSnapshot = stakedFraxStorageSnapshot(stakedEbtc);

        /// GIVEN: maxDistributionPerSecondPerAsset is uncapped
        _stakedFrax_setMaxDistributionPerSecondPerAsset(_maxDistributionPerSecondPerAsset);

        /// GIVEN: timestamp is 400_000 seconds away from the end of the cycle
        mineBlocksToTimestamp(stakedEbtc.__rewardsCycleData().cycleEnd + rewardsCycleLength - _syncDuration);

        /// GIVEN: 600 FRAX is transferred as rewards
      //  mintFraxTo(stakedFraxAddress, _rewards);
        vm.prank(defaultGovernance);
        stakedEbtc.donate(_rewards);

        /// GIVEN: syncAndDistributeRewards is called
        stakedEbtc.syncRewardsAndDistribution();

        /// GIVEN: We wait 100_000 seconds
        mineBlocksBySecond(_timeSinceLastRewardsDistribution);
        //==============================================================================
        // Deposit Test
        //==============================================================================

        /// WHEN: A user deposits 1000 FRAX
        _stakedFrax_deposit(1000 ether, bob);

        DeltaStakedFraxStorageSnapshot memory _second_deltaStakedFraxStorageSnapshot = deltaStakedFraxStorageSnapshot(
            _initial_stakedFraxSnapshot
        );

        //==============================================================================
        // Assert
        //==============================================================================

        /// THEN: the storedTotalAssets should have increased by 150 frax for the rewards and 1000 frax for the deposit
        assertEq(
            _second_deltaStakedFraxStorageSnapshot.delta.storedTotalAssets,
            1150 ether,
            "storedTotalAssets should have increased by 150 frax for the rewards and 1000 frax for the deposit"
        );

        // _expected = newAssets / sharePrice, sharePrice = assets / shares
        uint256 _expectedShares = (uint256(1000e18) * 1000e18) / 1150e18;
        /// THEN: The user should have 1000e18 * 1000e18 / 1150e18 shares
        assertEq(
            stakedEbtc.balanceOf(bob),
            _expectedShares,
            "THEN: The user should have 1000e18 * 1000e18 / 1150e18 shares"
        );

        /// THEN: The totalSupply should have increased by _expectedShares
        assertEq(
            _second_deltaStakedFraxStorageSnapshot.delta.totalSupply,
            _expectedShares,
            " THEN: The totalSupply should have increased by _expectedShares"
        );
    }
}
