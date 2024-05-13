// SPDX-License-Identifier: ISC
pragma solidity ^0.8.20;

import "../BaseTest.sol";

abstract contract StakedFraxFunctions is BaseTest {
    function _stakedFrax_setMaxDistributionPerSecondPerAsset(uint256 _maxDistributionPerSecondPerAsset) internal {
        vm.prank(defaultGovernance);
        stakedEbtc.setMaxDistributionPerSecondPerAsset(_maxDistributionPerSecondPerAsset);
    }
}

contract TestSetMaxDistributionPerSecondPerAsset is BaseTest, StakedFraxFunctions {
    /// FEATURE: setMaxDistributionPerSecondPerAsset

    function test_CannotCallIfNotTimelock() public {
        /// WHEN: unauthorized calls setMaxDistributionPerSecondPerAsset should fail
        vm.expectRevert("Auth: UNAUTHORIZED");
        stakedEbtc.setMaxDistributionPerSecondPerAsset(1 ether);
        /// THEN: we expect a revert with the Auth: UNAUTHORIZED error
    }

    function test_CannotSetAboveUint64() public {
        StakedFraxStorageSnapshot memory _initial_stakedFraxStorageSnapshot = stakedFraxStorageSnapshot(stakedEbtc);

        /// WHEN: governance sets maxDistributionPerSecondPerAsset to uint64.max + 1
        _stakedFrax_setMaxDistributionPerSecondPerAsset(uint256(type(uint64).max) + 1);

        DeltaStakedFraxStorageSnapshot memory _delta_stakedFraxStorageSnapshot = deltaStakedFraxStorageSnapshot(
            _initial_stakedFraxStorageSnapshot
        );

        /// THEN: values should be equal to uint64.max
        assertEq(
            _delta_stakedFraxStorageSnapshot.end.maxDistributionPerSecondPerAsset,
            type(uint64).max,
            "THEN: values should be equal to uint64.max"
        );
    }

    function test_CanSetMaxDistributionPerSecondPerAsset() public {
        StakedFraxStorageSnapshot memory _initial_stakedFraxStorageSnapshot = stakedFraxStorageSnapshot(stakedEbtc);

        /// WHEN: governance sets maxDistributionPerSecondPerAsset to 1 ether
        _stakedFrax_setMaxDistributionPerSecondPerAsset(1 ether);

        DeltaStakedFraxStorageSnapshot memory _delta_stakedFraxStorageSnapshot = deltaStakedFraxStorageSnapshot(
            _initial_stakedFraxStorageSnapshot
        );

        /// THEN: maxDistributionPerSecondPerAsset should be 1 ether
        assertEq(
            _delta_stakedFraxStorageSnapshot.end.maxDistributionPerSecondPerAsset,
            1 ether,
            "THEN: maxDistributionPerSecondPerAsset should be 1 ether"
        );
    }
}
