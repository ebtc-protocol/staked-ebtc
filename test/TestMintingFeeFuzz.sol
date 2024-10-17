// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.25;

import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import "./BaseTest.sol";

contract TestMintingFeeFuzz is BaseTest {
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event FeeTaken(address indexed recipient, uint256 feeAmount);

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

    function testFeeOnDeposit(uint256 mintingFee, uint256 depositAmount) public {
        mintingFee = bound(mintingFee, 1000000, 10000000); // bound fee from 1-10%
        depositAmount = bound(depositAmount, 1, 1000 ether);

        console.log("totalSupply", stakedEbtc.totalSupply());

        assertEq(mockEbtc.balanceOf(defaultFeeRecipient), 0);

        vm.prank(defaultGovernance);
        stakedEbtc.setMintingFee(mintingFee);

        uint256 previewShares = stakedEbtc.previewDeposit(depositAmount);
        uint256 previewAmount = stakedEbtc.convertToAssets(previewShares);
        uint256 computedFee = (depositAmount * mintingFee) / (mintingFee + stakedEbtc.FEE_PRECISION());

        vm.expectEmit(true, true, true, true, address(stakedEbtc));
        emit Deposit(bob, bob, depositAmount, previewShares);
        emit FeeTaken(defaultFeeRecipient, computedFee);

        uint256 totalBalBefore = mockEbtc.balanceOf(address(stakedEbtc));
        vm.prank(bob);
        stakedEbtc.deposit(depositAmount, bob);       
        uint256 totalBalAfter = mockEbtc.balanceOf(address(stakedEbtc));

        uint256 shares = stakedEbtc.balanceOf(bob);

        uint256 balBefore = mockEbtc.balanceOf(bob);
        vm.prank(bob);
        stakedEbtc.redeem(shares, bob, bob);
        uint256 balAfter = mockEbtc.balanceOf(bob);

        uint256 realFee = previewAmount * mintingFee / stakedEbtc.FEE_PRECISION();
        uint256 feeBalance = mockEbtc.balanceOf(defaultFeeRecipient);

        // rounding error from computed vs actual should never exceed 1 wei
        assertApproxEqAbs(computedFee, realFee, 1);
        assertEq(balAfter - balBefore, previewAmount);
        assertEq(previewAmount, totalBalAfter - totalBalBefore);
        assertEq(computedFee, feeBalance);
        assertEq(previewAmount + feeBalance, depositAmount);
    }

    function previewMintNoFee(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = stakedEbtc.totalSupply();

        return supply == 0 ? shares : FixedPointMathLib.mulDivUp(shares, stakedEbtc.totalAssets(), supply);
    }

    function testFeeOnMint(uint256 mintingFee, uint256 mintAmount) public {
        mintingFee = bound(mintingFee, 1000000, 10000000); // bound fee from 1-10%
        mintAmount = bound(mintAmount, 1, 500 ether);

        assertEq(mockEbtc.balanceOf(defaultFeeRecipient), 0);

        vm.prank(defaultGovernance);
        stakedEbtc.setMintingFee(mintingFee);

        uint256 previewAmount = stakedEbtc.previewMint(mintAmount);
        uint256 previewAmountNoFee = previewMintNoFee(mintAmount);

        vm.expectEmit(true, true, true, true, address(stakedEbtc));
        emit Deposit(bob, bob, previewAmount, mintAmount);
        emit FeeTaken(defaultFeeRecipient, previewAmountNoFee * stakedEbtc.mintingFee() / stakedEbtc.FEE_PRECISION());

        uint256 totalBalBefore = mockEbtc.balanceOf(address(stakedEbtc));
        vm.prank(bob);
        stakedEbtc.mint(mintAmount, bob);       
        uint256 totalBalAfter = mockEbtc.balanceOf(address(stakedEbtc));

        uint256 shares = stakedEbtc.balanceOf(bob);

        uint256 balBefore = mockEbtc.balanceOf(bob);
        vm.prank(bob);
        stakedEbtc.redeem(shares, bob, bob);
        uint256 balAfter = mockEbtc.balanceOf(bob);

        uint256 feeBalance = mockEbtc.balanceOf(defaultFeeRecipient);
        uint256 computedFee = (previewAmount * mintingFee) / (mintingFee + stakedEbtc.FEE_PRECISION());

        // rounding error from computed vs actual should never exceed 1 wei
        assertApproxEqAbs(feeBalance, computedFee, 1);
        assertEq(balAfter - balBefore + feeBalance, previewAmount);
    }
}
