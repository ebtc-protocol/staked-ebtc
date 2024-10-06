// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.25;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {Properties} from "./Properties.sol";
import {vm} from "@chimera/Hevm.sol";
import "forge-std/console2.sol";
import {MockERC20} from "./MockERC20.sol";

abstract contract TargetFunctions is BaseTargetFunctions, Properties, BeforeAfter {
    uint256 public constant MAX_EBTC = 1e27;
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

        if (!isEchidnaFork) {
            mockEbtc.mint(senderAddr, amount);
        } else {
            amount = between(amount, 0, mockEbtc.balanceOf(senderAddr));
        }

        vm.prank(senderAddr);
        mockEbtc.approve(address(stakedEbtc), type(uint256).max);

        __before();
        vm.prank(senderAddr);
        try stakedEbtc.deposit(amount, senderAddr) {
            __after();
            _checkPpfs();
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
            _checkPpfs();
        } catch {
            if (stakedEbtc.previewRedeem(shares) > 0) {
                t(false, "call shouldn't fail");
            }
        }
    }

    function donate(uint256 amount, bool authorized) public prepare {
        amount = between(amount, 1, MAX_EBTC);

        if (!isEchidnaFork) {
            mockEbtc.mint(defaultGovernance, amount);
        } else {
            amount = between(amount, 0, mockEbtc.balanceOf(defaultGovernance));
        }

        __before();

        if (authorized) {
            vm.prank(defaultGovernance);
            try stakedEbtc.donate(amount) {
                __after();

                t(_after.totalBalance > _before.totalBalance, "totalBalance should go up after an authorized donation");
                _checkPpfs();
            } catch {
                t(false, "call shouldn't fail");
            }
        } else {
            vm.prank(defaultGovernance);
            mockEbtc.transfer(address(stakedEbtc), amount);

            __after();

            _checkPpfs();
            t(
                _after.totalBalance == _before.totalBalance,
                "totalBalance should not go up after an unauthorized donation"
            );
        }
    }

    function sweep(uint256 amount) public prepare {
        amount = between(amount, 1, MAX_EBTC);

        if (!isEchidnaFork) {
            mockEbtc.mint(address(stakedEbtc), amount);
        } else {
            vm.prank(defaultGovernance);
            amount = between(amount, 0, mockEbtc.balanceOf(defaultGovernance));
            vm.prank(defaultGovernance);
            mockEbtc.transfer(address(stakedEbtc), amount);
        }

        __before();

        vm.prank(defaultGovernance);
        try stakedEbtc.sweep(address(mockEbtc)) {
            __after();
            t(_after.actualBalance < _before.actualBalance, "actualBalance should go down after sweep()");
            t(_after.totalBalance == _before.totalBalance, "totalBalance should not be affected by sweep()");
            _checkPpfs();
        } catch {
            t(false, "call shouldn't fail");
        }
    }

    function sweep_other(uint256 amount) public prepare {
        // MINT A TOKEN
        MockERC20 otherToken = new MockERC20("mock", "MOCK");

        otherToken.mint(address(stakedEbtc), amount);

        __before();

        uint256 balB4 = otherToken.balanceOf(defaultGovernance);

        vm.prank(defaultGovernance);
        try stakedEbtc.sweep(address(otherToken)) {}
        catch {
            t(false, "call shouldn't fail");
        }

        uint256 balAfter = otherToken.balanceOf(defaultGovernance);

        t(balAfter - balB4 == amount, "Sweep of other token");
    }

    function rewardAccrual(uint256 amount) public prepare {
        amount = between(amount, 1, 1000e18);

        __before();

        // reward distribution doesn't work with no deposits
        require(_before.totalStoredBalance > 0);

        if (!isEchidnaFork) {
            mockEbtc.mint(defaultGovernance, amount);
        } else {
            amount = between(amount, 0, mockEbtc.balanceOf(defaultGovernance));
        }

        vm.prank(defaultGovernance);
        try stakedEbtc.donate(amount) {
            vm.warp(block.timestamp + stakedEbtc.REWARDS_CYCLE_LENGTH() + 1);
            try stakedEbtc.syncRewardsAndDistribution() {}
            catch {
                t(false, "call shouldn't fail");
            }
            vm.warp(block.timestamp + stakedEbtc.REWARDS_CYCLE_LENGTH());
            try stakedEbtc.syncRewardsAndDistribution() {
                __after();
                t(_after.totalStoredBalance >= _before.totalStoredBalance, "reward accrual should work");
                _checkPpfs();
            } catch {
                t(false, "call shouldn't fail");
            }
        } catch {
            t(false, "call shouldn't fail");
        }
    }

    function _checkPpfs() private {
        if (stakedEbtc.totalSupply() > 0) {
            t(_after.ppfs >= _before.ppfs, "ppfs should never decrease");
        }
    }

    function sync_rewards_and_distribution_should_never_revert(uint256 ts) public prepare {
        ts = between(ts, 0, 500 * 52 weeks);
        try stakedEbtc.syncRewardsAndDistribution() {}
        catch {
            t(false, "syncRewardsAndDistribution should not revert");
        }
    }

    function erc4626_roundtrip_invariant_a(uint256 amount) public prepare {
        amount = between(amount, 1, MAX_EBTC);

        vm.prank(senderAddr);
        uint256 shares = stakedEbtc.deposit(amount, senderAddr);

        amount = stakedEbtc.convertToAssets(shares);

        vm.prank(senderAddr);
        uint256 redeemedAssets = stakedEbtc.redeem(shares, senderAddr, senderAddr);

        t(redeemedAssets <= amount, "ERC4626_ROUNDTRIP_INVARIANT_A: redeem(deposit(a)) <= a");
    }

    function erc4626_roundtrip_invariant_b(uint256 amount) public prepare {
        amount = between(amount, 1, MAX_EBTC);

        vm.prank(senderAddr);
        uint256 shares = stakedEbtc.deposit(amount, senderAddr);

        amount = stakedEbtc.convertToAssets(shares);

        vm.prank(senderAddr);
        uint256 withdrawnShares = stakedEbtc.withdraw(amount, senderAddr, senderAddr);

        t(withdrawnShares >= shares, "ERC4626_ROUNDTRIP_INVARIANT_B: s = deposit(a) s' = withdraw(a) s' >= s");
    }

    function erc4626_roundtrip_invariant_c(uint256 shares) public prepare {
        shares = between(shares, 1, stakedEbtc.convertToShares(MAX_EBTC));

        vm.prank(senderAddr);
        stakedEbtc.mint(shares, senderAddr);

        vm.prank(senderAddr);
        uint256 redeemedAssets = stakedEbtc.redeem(shares, senderAddr, senderAddr);

        vm.prank(senderAddr);
        uint256 mintedShares = stakedEbtc.deposit(redeemedAssets, senderAddr);

        /// @dev restore original state to not break invariants
        vm.prank(senderAddr);
        stakedEbtc.redeem(mintedShares, senderAddr, senderAddr);

        t(mintedShares <= shares, "ERC4626_ROUNDTRIP_INVARIANT_C: deposit(redeem(s)) <= s");
    }

    function erc4626_roundtrip_invariant_d(uint256 shares) public prepare {
        shares = between(shares, 1, stakedEbtc.convertToShares(MAX_EBTC));

        stakedEbtc.mint(shares, senderAddr);

        vm.prank(senderAddr);
        uint256 redeemedAssets = stakedEbtc.redeem(shares, senderAddr, senderAddr);

        stakedEbtc.mint(shares, senderAddr);

        uint256 depositedAssets = stakedEbtc.convertToAssets(shares);

        /// @dev restore original state to not break invariants
        vm.prank(senderAddr);
        stakedEbtc.withdraw(depositedAssets, senderAddr, senderAddr);

        t(depositedAssets >= redeemedAssets, "ERC4626_ROUNDTRIP_INVARIANT_D: a = redeem(s) a' = mint(s) a' >= a");
    }

    function erc4626_roundtrip_invariant_e(uint256 shares) public prepare {
        shares = between(shares, 1, stakedEbtc.convertToShares(MAX_EBTC));

        vm.prank(senderAddr);
        stakedEbtc.mint(shares, senderAddr);

        uint256 depositedAssets = stakedEbtc.convertToAssets(shares);

        vm.prank(senderAddr);
        uint256 withdrawnShares = stakedEbtc.withdraw(depositedAssets, senderAddr, senderAddr);

        t(withdrawnShares >= shares, "ERC4626_ROUNDTRIP_INVARIANT_E: withdraw(mint(s)) >= s");
    }

    function erc4626_roundtrip_invariant_f(uint256 shares) public prepare {
        shares = between(shares, 1, stakedEbtc.convertToShares(MAX_EBTC));

        vm.prank(senderAddr);

        stakedEbtc.mint(shares, senderAddr);

        uint256 depositedAssets = stakedEbtc.convertToAssets(shares);

        vm.prank(senderAddr);
        uint256 redeemedAssets = stakedEbtc.redeem(shares, senderAddr, senderAddr);

        t(redeemedAssets <= depositedAssets, "ERC4626_ROUNDTRIP_INVARIANT_F: a = mint(s) a' = redeem(s) a' <= a");
    }

    function erc4626_roundtrip_invariant_g(uint256 amount) public prepare {
        amount = between(amount, 1, MAX_EBTC);

        vm.prank(senderAddr);
        uint256 sharesMinted = stakedEbtc.deposit(amount, senderAddr);

        amount = stakedEbtc.convertToAssets(sharesMinted);

        vm.prank(senderAddr);
        uint256 redeemedShares = stakedEbtc.withdraw(amount, senderAddr, senderAddr);

        vm.prank(senderAddr);
        stakedEbtc.mint(redeemedShares, senderAddr);

        uint256 depositedAssets = stakedEbtc.convertToAssets(redeemedShares);

        /// @dev restore original state to not break invariants
        vm.prank(senderAddr);
        stakedEbtc.withdraw(depositedAssets, senderAddr, senderAddr);

        t(depositedAssets >= amount, "ERC4626_ROUNDTRIP_INVARIANT_G: mint(withdraw(a)) >= a");
    }

    function erc4626_roundtrip_invariant_h(uint256 amount) public prepare {
        amount = between(amount, 1, MAX_EBTC);

        vm.prank(senderAddr);
        uint256 sharesMinted = stakedEbtc.deposit(amount, senderAddr);

        amount = stakedEbtc.convertToAssets(sharesMinted);

        vm.prank(senderAddr);
        uint256 redeemedShares = stakedEbtc.withdraw(amount, senderAddr, senderAddr);

        vm.prank(senderAddr);
        uint256 mintedShares = stakedEbtc.deposit(amount, senderAddr);

        /// @dev restore original state to not break invariants
        vm.prank(senderAddr);
        stakedEbtc.redeem(mintedShares, senderAddr, senderAddr);

        t(mintedShares <= redeemedShares, "ERC4626_ROUNDTRIP_INVARIANT_H: s = withdraw(a) s' = deposit(a) s' <= s");
    }
}
