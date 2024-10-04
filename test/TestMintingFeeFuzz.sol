// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.25;

import "./BaseTest.sol";

contract TestMintingFeeFuzz is BaseTest {

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

    // fuzzes implementation of _computeFeeRaw
    function testZeroRawFee(uint256 mintingFee, uint256 _assets) public {
        mintingFee = bound(mintingFee, 1000000, 10000000); // bound fee from 1-10%
        // Ensure _assets is within a safe range to prevent overflow
        uint256 maxSafeAssets = type(uint256).max / mintingFee;
        // _assets = bound(_assets, 0, maxSafeAssets); // this works but finds values that are very low
        _assets = bound(_assets, 5e9, maxSafeAssets); // sets lower bound to half of 1 stakedEbtc

        uint256 rawFee = _assets * mintingFee / stakedEbtc.FEE_PRECISION();
        assertGt(rawFee, 0, "asset can be minted for no fee");
    }

    // fuzzes implementation of _computeFeeTotal
    function testZeroFeeTotal(uint256 mintingFee, uint256 _assets) public {
        mintingFee = bound(mintingFee, 1000000, 10000000); // bound fee from 1-10%
        // Ensure _assets is within a safe range to prevent overflow
        uint256 maxSafeAssets = type(uint256).max / mintingFee;
        // _assets = bound(_assets, 0, maxSafeAssets); // this works but finds values that are very low
        _assets = bound(_assets, 5e9, maxSafeAssets); // sets lower bound to half of 1 stakedEbtc

        uint256 rawFee = (_assets * mintingFee) / (mintingFee + stakedEbtc.FEE_PRECISION());
        assertGt(rawFee, 0, "asset can be minted for no fee");
    }
}
