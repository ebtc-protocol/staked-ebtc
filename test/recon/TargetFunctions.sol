
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {Properties} from "./Properties.sol";
import {vm} from "@chimera/Hevm.sol";

abstract contract TargetFunctions is BaseTargetFunctions, Properties, BeforeAfter {
    uint256 public constant MAX_EBTC = 1e27;
    address internal senderAddr;

    modifier prepare() {
        if (senderAddr == address(0)) {
            senderAddr = msg.sender;
        }
        // block.timestamp can somtimes fall behind lastRewardsDistribution
        // Is this a medusa issue?
        if (block.timestamp < stakedEbtc.lastRewardsDistribution()) {
            vm.warp(stakedEbtc.lastRewardsDistribution());
        }
        _;
    }

    function setSenderAddr(address newAddr) internal {
        senderAddr = newAddr;
    }

    function deposit(uint256 amount) public prepare {
        amount = between(amount, 1, MAX_EBTC);

        mockEbtc.mint(senderAddr, amount);

        vm.prank(senderAddr);
        mockEbtc.approve(address(stakedEbtc), type(uint256).max);

        __before();
        vm.prank(senderAddr);
        try stakedEbtc.deposit(amount, senderAddr) {
            __after();
            t(_after.ppfs >= _before.ppfs, "ppfs should never decrease");
        } catch {
            if (stakedEbtc.previewDeposit(amount) > 0) {
                t(false, "call shouldn't fail");
            }
        }

        __after();
    }

    function redeem(uint256 shares) public prepare {
        shares = between(shares, 0, stakedEbtc.balanceOf(senderAddr));

        __before();
        vm.prank(senderAddr);
        try stakedEbtc.redeem(shares, senderAddr, senderAddr) {
            __after();
            t(_after.ppfs >= _before.ppfs, "ppfs should never decrease");
        } catch {
            if (stakedEbtc.previewRedeem(shares) > 0) {
                t(false, "call shouldn't fail");
            }
        }
    }

    function donate(uint256 amount, bool authorized) public prepare {
        amount = between(amount, 1, MAX_EBTC);

        mockEbtc.mint(defaultGovernance, amount);

        __before();

        if (authorized) {
            vm.prank(defaultGovernance);
            try stakedEbtc.donate(amount) {
                __after();

                t(_after.totalBalance > _before.totalBalance, "totalBalance should go up after an authorized donation");
                t(_after.ppfs >= _before.ppfs, "ppfs should never decrease");
            } catch {
                t(false, "call shouldn't fail");
            }
        } else {
            vm.prank(defaultGovernance);
            mockEbtc.transfer(address(stakedEbtc), amount);
            
            __after();

            t(_after.ppfs >= _before.ppfs, "ppfs should never decrease"); 
            t(_after.totalBalance == _before.totalBalance, "totalBalance should not go up after an unauthorized donation");
        }
    }

    function sweep(uint256 amount) public prepare {
        amount = between(amount, 1, MAX_EBTC);

        mockEbtc.mint(address(stakedEbtc), amount);

        __before();

        vm.prank(defaultGovernance);
        try stakedEbtc.sweep(address(mockEbtc)) {
            __after();
            t(_after.actualBalance < _before.actualBalance, "actualBalance should go down after sweep()");
            t(_after.totalBalance == _before.totalBalance, "totalBalance should not be affected by sweep()");
            t(_after.ppfs >= _before.ppfs, "ppfs should never decrease");
        } catch {
            t(false, "call shouldn't fail");
        }
    }

    function rewardAccrual(uint256 amount) public prepare {
        amount = between(amount, 1, 1000e18);

        __before();

        // reward distribution doesn't work with no deposits
        require(_before.totalStoredBalance > 0);

        mockEbtc.mint(defaultGovernance, amount);

        vm.prank(defaultGovernance);
        try stakedEbtc.donate(amount) {
            vm.warp(block.timestamp + stakedEbtc.REWARDS_CYCLE_LENGTH() + 1);
            try stakedEbtc.syncRewardsAndDistribution() {
            } catch {
                t(false, "call shouldn't fail");
            }
            vm.warp(block.timestamp + stakedEbtc.REWARDS_CYCLE_LENGTH());
            try stakedEbtc.syncRewardsAndDistribution() {
                __after();
                t(_after.totalStoredBalance >= _before.totalStoredBalance, "reward accrual should work");
                t(_after.ppfs >= _before.ppfs, "ppfs should never decrease");
            } catch {
                t(false, "call shouldn't fail");
            }
        } catch {
            t(false, "call shouldn't fail");
        }
    }

    function sync_rewards_and_distribution_should_never_revert(uint256 ts) public prepare {
        ts = between(ts, 0, 500 * 52 weeks);
        try stakedEbtc.syncRewardsAndDistribution() {
        } catch {
            t(false, "syncRewardsAndDistribution should not revert");
        }
    }
}
