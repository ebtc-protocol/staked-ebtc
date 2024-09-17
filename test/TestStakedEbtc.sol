// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.25;

import "./BaseTest.sol";

contract TestStakedEbtc is BaseTest {

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

    function testDonationAuth() public {
        vm.prank(bob);
        stakedEbtc.deposit(10 ether, bob);

        vm.expectRevert("Auth: UNAUTHORIZED");
        vm.prank(alice);
        stakedEbtc.donate(10 ether);

        vm.prank(defaultGovernance);
        governor.setUserRole(alice, 12, true);

        uint256 totalBalanceBefore = stakedEbtc.totalBalance();
        
        vm.prank(alice);
        stakedEbtc.donate(10 ether);

        assertEq(stakedEbtc.totalBalance() - totalBalanceBefore, 10 ether);
    }

    function testRewardAccrual() public {
        vm.prank(bob);
        stakedEbtc.deposit(10 ether, bob);

        vm.prank(defaultGovernance);
        governor.setUserRole(alice, 12, true);

        vm.prank(alice);
        stakedEbtc.donate(1 ether);
        
        vm.warp(block.timestamp + stakedEbtc.REWARDS_CYCLE_LENGTH() + 1);

        uint256 storedBefore = stakedEbtc.storedTotalAssets();

        stakedEbtc.syncRewardsAndDistribution();

        vm.warp(block.timestamp + stakedEbtc.REWARDS_CYCLE_LENGTH() / 2 - 1);

        uint256 rewardAmount = stakedEbtc.previewDistributeRewards();

        assertEq(rewardAmount, 0.5 ether);

        stakedEbtc.syncRewardsAndDistribution();

        assertEq(stakedEbtc.storedTotalAssets(), storedBefore + rewardAmount);
    }

    function testRewardAccrualAboveMaxDistribution() public {
        vm.prank(bob);
        stakedEbtc.deposit(10 ether, bob);

        vm.prank(defaultGovernance);
        governor.setUserRole(alice, 12, true);

        vm.prank(alice);
        stakedEbtc.donate(10 ether);
        
        vm.warp(block.timestamp + stakedEbtc.REWARDS_CYCLE_LENGTH() + 1);

        uint256 storedBefore = stakedEbtc.storedTotalAssets();
        uint256 timeBefore = block.timestamp;

        stakedEbtc.syncRewardsAndDistribution();

        vm.warp(block.timestamp + stakedEbtc.REWARDS_CYCLE_LENGTH() / 2 - 1);

        uint256 deltaTime = block.timestamp - timeBefore;
        uint256 maxDistribution = (stakedEbtc.maxDistributionPerSecondPerAsset() * deltaTime * stakedEbtc.storedTotalAssets()) / 1e18;

        uint256 rewardAmount = stakedEbtc.previewDistributeRewards();

        assertEq(rewardAmount, maxDistribution);

        stakedEbtc.syncRewardsAndDistribution();

        assertEq(stakedEbtc.storedTotalAssets(), storedBefore + rewardAmount);
    }

    function testSweepAuth() public {
        vm.prank(bob);
        stakedEbtc.deposit(10 ether, bob);

        vm.prank(donald);
        mockEbtc.transfer(address(stakedEbtc), 10 ether);

        vm.expectRevert("Auth: UNAUTHORIZED");
        vm.prank(alice);
        stakedEbtc.sweep(address(mockEbtc));

        vm.prank(defaultGovernance);
        governor.setUserRole(alice, 12, true);

        uint256 totalBalanceBefore = stakedEbtc.totalBalance();
        uint256 stakedEbtcBalanceBefore = mockEbtc.balanceOf(address(stakedEbtc));
        uint256 senderBalanceBefore = mockEbtc.balanceOf(alice);

        vm.prank(alice);
        stakedEbtc.sweep(address(mockEbtc));

        // total balance unchanged
        assertEq(stakedEbtc.totalBalance(), totalBalanceBefore);

        // contract balance goes down by 10 ether after sweep
        assertEq(stakedEbtcBalanceBefore - mockEbtc.balanceOf(address(stakedEbtc)), 10 ether);

        // sender receives unauthorized donation (10 ether)
        assertEq(mockEbtc.balanceOf(alice) - senderBalanceBefore, 10 ether);
    }

    function testMinRewardsPerPeriod() public {
        vm.prank(bob);
        stakedEbtc.deposit(10 ether, bob);

        vm.expectRevert("Auth: UNAUTHORIZED");
        vm.prank(alice);
        stakedEbtc.setMinRewardsPerPeriod(1 ether);

        vm.prank(defaultGovernance);
        stakedEbtc.setMinRewardsPerPeriod(1 ether);

        vm.warp(block.timestamp + stakedEbtc.REWARDS_CYCLE_LENGTH() + 1);

        vm.expectRevert("min rewards");
        stakedEbtc.syncRewardsAndDistribution();

        vm.prank(defaultGovernance);
        stakedEbtc.donate(1 ether);

        stakedEbtc.syncRewardsAndDistribution();
    }

    function testZeroSupplyDonation() public {
        // remove initial shares
        uint256 initShares = stakedEbtc.balanceOf(defaultGovernance);

        vm.prank(defaultGovernance);
        stakedEbtc.redeem(initShares, defaultGovernance, defaultGovernance);

        // intentionally setting the max distribution low to leave pending rewards in the contract
        vm.prank(defaultGovernance);
        stakedEbtc.setMaxDistributionPerSecondPerAsset(3022);

        console.log("totalSupply", stakedEbtc.totalSupply());

        console.log("==== donation (0 totalSupply) ===");

        vm.prank(defaultGovernance);
        stakedEbtc.donate(1 ether);

        console.log("totalBalance", stakedEbtc.totalBalance());
        console.log("storedTotalAssets", stakedEbtc.storedTotalAssets());

        console.log("==== sync ===");

        console.log("totalBalance", stakedEbtc.totalBalance());
        console.log("storedTotalAssets", stakedEbtc.storedTotalAssets());

        stakedEbtc.syncRewardsAndDistribution();

        vm.warp(block.timestamp + stakedEbtc.REWARDS_CYCLE_LENGTH() + 1);

        console.log("==== sync after cycle length ===");

        stakedEbtc.syncRewardsAndDistribution();

        console.log("totalBalance", stakedEbtc.totalBalance());
        console.log("storedTotalAssets", stakedEbtc.storedTotalAssets());

        vm.warp(block.timestamp + stakedEbtc.REWARDS_CYCLE_LENGTH() + 1);

        console.log("==== sync after cycle length (again) ===");

        console.log("totalBalance", stakedEbtc.totalBalance());
        console.log("storedTotalAssets", stakedEbtc.storedTotalAssets());

        console.log("==== deposit ===");

        vm.prank(bob);
        stakedEbtc.deposit(10 ether, bob);

        console.log("totalBalance", stakedEbtc.totalBalance());
        console.log("storedTotalAssets", stakedEbtc.storedTotalAssets());
        console.log("pricePerShare", stakedEbtc.pricePerShare());

        console.log("bobAssets", stakedEbtc.convertToAssets(stakedEbtc.balanceOf(bob)));
        console.log("bobShares", stakedEbtc.balanceOf(bob));

        uint256 bobShares = stakedEbtc.balanceOf(bob);
        uint256 bobBefore = mockEbtc.balanceOf(bob);
        
        console.log("==== redeem (all) ===");

        vm.prank(bob);
        stakedEbtc.redeem(bobShares, bob, bob);

        uint256 bobAfter = mockEbtc.balanceOf(bob);

        console.log("totalBalance", stakedEbtc.totalBalance());
        console.log("storedTotalAssets", stakedEbtc.storedTotalAssets());
        console.log("bobBefore", bobBefore);
        console.log("bobAfter", bobAfter);
        console.log("bobDiff", bobAfter - bobBefore);
    
        console.log("==== deposit ===");

        vm.prank(bob);
        stakedEbtc.deposit(10 ether, bob);

        vm.warp(block.timestamp + stakedEbtc.REWARDS_CYCLE_LENGTH() + 1);

        stakedEbtc.syncRewardsAndDistribution();

        console.log("totalBalance", stakedEbtc.totalBalance());
        console.log("storedTotalAssets", stakedEbtc.storedTotalAssets());
        console.log("pricePerShare", stakedEbtc.pricePerShare());

        console.log("==== redeem (all) ===");

        bobShares = stakedEbtc.balanceOf(bob);
        vm.prank(bob);
        stakedEbtc.redeem(bobShares, bob, bob);

        console.log("totalSupply", stakedEbtc.totalSupply());
        console.log("totalBalance", stakedEbtc.totalBalance());
        console.log("storedTotalAssets", stakedEbtc.storedTotalAssets());
        console.log("pricePerShare", stakedEbtc.pricePerShare());

        stakedEbtc.syncRewardsAndDistribution();

        vm.warp(block.timestamp + stakedEbtc.REWARDS_CYCLE_LENGTH() + 1);

        console.log("==== sync after cycle length ===");

        stakedEbtc.syncRewardsAndDistribution();

        console.log("totalBalance", stakedEbtc.totalBalance());
        console.log("storedTotalAssets", stakedEbtc.storedTotalAssets());

        vm.warp(block.timestamp + stakedEbtc.REWARDS_CYCLE_LENGTH() + 1);

        console.log("==== sync after cycle length (again) ===");

        console.log("totalBalance", stakedEbtc.totalBalance());
        console.log("storedTotalAssets", stakedEbtc.storedTotalAssets());
    }
}
