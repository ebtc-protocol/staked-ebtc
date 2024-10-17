
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.25;

import {Asserts} from "@chimera/Asserts.sol";
import {vm} from "@chimera/Hevm.sol";
import {Setup} from "./Setup.sol";

abstract contract Properties is Setup, Asserts {
    address internal senderAddr;
    
    modifier prepare() {
        if (senderAddr == address(0)) {
            senderAddr = msg.sender;
        }

        bool found;
        for (uint256 i; i < senders.length; i++) {
            if (senderAddr == senders[i]) {
                found = true;
                break;
            }
        }

        if (!found) {
            senders.push(senderAddr);
        }

        // block.timestamp can somtimes fall behind lastRewardsDistribution
        // because we use warp in rewardAccrual. We need to make sure
        // block.timestamp never falls behind lastRewardsDistribution the avoid
        // underflow issues
        if (block.timestamp < stakedEbtc.lastRewardsDistribution()) {
            vm.warp(stakedEbtc.lastRewardsDistribution());
        }
        _;
    }

    function total_balance_below_actual_balance() public prepare {
        t(mockEbtc.balanceOf(address(stakedEbtc)) >= stakedEbtc.totalBalance(), "actualBalance >= totalBalance");
    }

    function total_assets_below_total_balance() public prepare {
        t(stakedEbtc.totalBalance() >= stakedEbtc.totalAssets(), "totalBalance >= totalAssets");
    }

    function sum_of_user_balances_equals_total_supply() public prepare {
        uint256 sumOfUserBalances;
        for (uint256 i; i < senders.length; i++) {
            sumOfUserBalances += stakedEbtc.balanceOf(senders[i]);
        }
        t(sumOfUserBalances == stakedEbtc.totalSupply(), "sumOfUserBalances == totalSupply");
    }

    function sum_of_user_assets_equals_total_assets() public prepare {
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
}
