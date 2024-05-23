
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Asserts} from "@chimera/Asserts.sol";
import {Setup} from "./Setup.sol";

abstract contract Properties is Setup, Asserts {
    function crytic_total_balance_below_actual_balance() public {
        t(mockEbtc.balanceOf(address(stakedEbtc)) >= stakedEbtc.totalBalance(), "actualBalance >= totalBalance");
    }

    function crytic_total_assets_below_total_balance() public {
        t(stakedEbtc.totalBalance() >= stakedEbtc.totalAssets(), "totalBalance >= totalAssets");
    }
}
