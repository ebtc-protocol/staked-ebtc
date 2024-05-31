
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Setup} from "./Setup.sol";

abstract contract BeforeAfter is Setup {

    struct Vars {
        uint256 actualBalance;
        uint256 totalBalance;
        uint256 totalStoredBalance;
        uint256 ppfs;
    }

    Vars internal _before;
    Vars internal _after;

    function __before() internal {
        _before.actualBalance = mockEbtc.balanceOf(address(stakedEbtc));
        _before.totalBalance = stakedEbtc.totalBalance();
        _before.totalStoredBalance = stakedEbtc.storedTotalAssets();
        _before.ppfs = stakedEbtc.pricePerShare();
    }

    function __after() internal {
        _after.actualBalance = mockEbtc.balanceOf(address(stakedEbtc));
        _after.totalBalance = stakedEbtc.totalBalance();
        _after.totalStoredBalance = stakedEbtc.storedTotalAssets();
        _after.ppfs = stakedEbtc.pricePerShare();
    }
}
