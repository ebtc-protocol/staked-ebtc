// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.25;

import "./BaseTest.sol";

contract TestGrief is BaseTest {

    address bob;
    address alice;
    address donald;

    function setUp() public override {
        /// BACKGROUND: deploy the StakedFrax contract
        /// BACKGROUND: 10% APY cap
        /// BACKGROUND: frax as the underlying asset
        /// BACKGROUND: TIMELOCK_ADDRESS set as the timelock address
        super.setUp();

        bob = labelAndDeal(address(1234), "bob");
        mintEbtcTo(bob, 1000 ether);
        vm.prank(bob);
        mockEbtc.approve(stakedFraxAddress, type(uint256).max);

        alice = labelAndDeal(address(2345), "alice");
        mintEbtcTo(alice, 1000 ether);
        vm.prank(alice);
        mockEbtc.approve(stakedFraxAddress, type(uint256).max);

        donald = labelAndDeal(address(3456), "donald");
        mintEbtcTo(donald, 1000 ether);
        vm.prank(donald);
        mockEbtc.approve(stakedFraxAddress, type(uint256).max);
    }


    function testGriefRewards() public {
        vm.prank(bob);
        stakedEbtc.deposit(10 ether, bob);

        vm.prank(defaultGovernance);
        governor.setUserRole(alice, 12, true);

        vm.warp(block.timestamp + stakedEbtc.REWARDS_CYCLE_LENGTH() + 1);

        // Sync and grief
        stakedEbtc.syncRewardsAndDistribution();
        (, , uint256 rewards) = stakedEbtc.rewardsCycleData();

        assertEq(rewards, 0, "No rewards for a week");
        vm.warp(block.timestamp + 1);

        // Donate
        vm.prank(defaultGovernance);
        governor.setUserRole(alice, 12, true);

        vm.prank(alice);
        stakedEbtc.donate(1 ether);

        // Will not revert
        stakedEbtc.syncRewardsAndDistribution();

        // But it's still at 0, rip
        (, , uint256 rewardsAfter) = stakedEbtc.rewardsCycleData();
        assertEq(rewards, rewardsAfter, "Griefed for an entire week");
    }
}
