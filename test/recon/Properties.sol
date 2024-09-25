
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.25;

import {Asserts} from "@chimera/Asserts.sol";
import {Setup} from "./Setup.sol";

abstract contract Properties is Setup, Asserts {
    function total_balance_below_actual_balance() public {
        t(mockEbtc.balanceOf(address(stakedEbtc)) >= stakedEbtc.totalBalance(), "actualBalance >= totalBalance");
    }

    function total_assets_below_total_balance() public {
        t(stakedEbtc.totalBalance() >= stakedEbtc.totalAssets(), "totalBalance >= totalAssets");
    }

    function sum_of_user_balances_equals_total_supply() public {
        uint256 sumOfUserBalances;
        for (uint256 i; i < senders.length; i++) {
            sumOfUserBalances += stakedEbtc.balanceOf(senders[i]);
        }
        t(sumOfUserBalances == stakedEbtc.totalSupply(), "sumOfUserBalances == totalSupply");
    }

    function sum_of_user_assets_equals_total_assets() public {
        uint256 sumOfUserAssets;
        for (uint256 i; i < senders.length; i++) {
            sumOfUserAssets += stakedEbtc.convertToAssets(stakedEbtc.balanceOf(senders[i]));
        }

        if (sumOfUserAssets <= stakedEbtc.totalAssets()) {
            // account for rounding error (1 wei per sender)
            t((stakedEbtc.totalAssets() - sumOfUserAssets) < senders.length, "sumOfUserAssets == totalAssets");
        } else {
            t(false, "sumOfUserAssets shouldn't be greater than totalAssets");
        }
    }

    function cycle_end_gte_last_rewards_distribution() public {
        (uint40 cycleEnd, , ) = stakedEbtc.rewardsCycleData();
        t(cycleEnd >= stakedEbtc.lastRewardsDistribution(), "cycleEnd >= lastRewardsDistribution");
    }

    function last_rewards_distribution_gte_last_sync() public {
        (, uint40 lastSync, ) = stakedEbtc.rewardsCycleData();
        t(stakedEbtc.lastRewardsDistribution() >= lastSync, "lastRewardsDistribution >= lastSync");
    }
}
