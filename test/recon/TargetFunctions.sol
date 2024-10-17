
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.25;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {Properties} from "./Properties.sol";
import {vm} from "@chimera/Hevm.sol";
import "forge-std/console2.sol";
import {LinearRewardsErc4626} from "src/LinearRewardsErc4626.sol";

abstract contract TargetFunctions is BaseTargetFunctions, Properties, BeforeAfter {
    uint256 public constant MAX_EBTC = 1e27;

    function _checkPpfs() private {
        if (stakedEbtc.totalSupply() > 0) {
            t(_after.ppfs >= _before.ppfs, "ppfs should never decrease");
        }
    }

    function setSenderAddr(address newAddr) internal {
        senderAddr = newAddr;
    }

    function setMaxDistributionPerSecondPerAsset(uint256 amt) public prepare {
        vm.prank(defaultGovernance);
        try stakedEbtc.setMaxDistributionPerSecondPerAsset(amt) {
        } catch {
            t(false, "call shouldn't fail");
        }
    }

    function setMintingFee(uint256 mintingFee) public prepare {
        mintingFee = between(mintingFee, 0, stakedEbtc.MAX_MINTING_FEE());

        vm.prank(defaultGovernance);
        try stakedEbtc.setMintingFee(mintingFee) {
        } catch {
            t(false, "call shouldn't fail");
        }
    }


    function calculateRewardsToDistribute(uint64 deltaTime) public prepare {
        (uint40 cycleEnd, uint40 lastSync, uint192 rewardCycleAmount) = stakedEbtc.rewardsCycleData();
        LinearRewardsErc4626.RewardsCycleData memory data = LinearRewardsErc4626.RewardsCycleData({
            cycleEnd: cycleEnd,
            lastSync: lastSync,
            rewardCycleAmount: rewardCycleAmount
        });

        try stakedEbtc.calculateRewardsToDistribute(data, deltaTime) {
        } catch {
            t(false, "call shouldn't fail");
        }
    }
    
    function sync_rewards_and_distribution_should_never_revert(uint256 ts) public prepare {
        ts = between(ts, 0, 500 * 52 weeks);
        vm.warp(block.timestamp + ts);
        try stakedEbtc.syncRewardsAndDistribution() {
        } catch {
            t(false, "syncRewardsAndDistribution should not revert");
        }
    }

    function deposit(uint256 amount) public prepare {
        amount = between(amount, 1, MAX_EBTC);

        mockEbtc.mint(senderAddr, amount);

        vm.prank(senderAddr);
        mockEbtc.approve(address(stakedEbtc), type(uint256).max);

        uint256 previewShares = stakedEbtc.previewDeposit(amount);

        __before();
        vm.prank(senderAddr);
        try stakedEbtc.deposit(amount, senderAddr) returns (uint256 actualShares) {
            t(previewShares == actualShares, "previewShares == actualShares");
            __after();
            _checkPpfs();
        } catch {
            if (previewShares > 0) {
                t(false, "call shouldn't fail");
            }
        }

        __after();
    }

    function mint(uint256 shares) public prepare {
        shares = between(shares, 1, MAX_EBTC / 10);

        uint256 previewAmount = stakedEbtc.previewMint(shares);

        mockEbtc.mint(senderAddr, previewAmount);

        vm.prank(senderAddr);
        mockEbtc.approve(address(stakedEbtc), type(uint256).max);

        __before();
        vm.prank(senderAddr);
        try stakedEbtc.mint(shares, senderAddr) returns (uint256 actualAmount) {
            t(previewAmount == actualAmount, "previewAmount == actualAmount");
            __after();
            _checkPpfs();
        } catch {
            if (previewAmount > 0) {
                t(false, "call shouldn't fail");
            }
        }

        __after();
    }

    function redeem(uint256 shares) public prepare {
        shares = between(shares, 0, stakedEbtc.balanceOf(senderAddr));

        uint256 previewAmount = stakedEbtc.previewRedeem(shares);

        __before();
        vm.prank(senderAddr);
        try stakedEbtc.redeem(shares, senderAddr, senderAddr) returns (uint256 actualAmount) {
            t(previewAmount == actualAmount, "previewAmount == actualAmount");
            __after();
            _checkPpfs();
        } catch {
            if (stakedEbtc.previewRedeem(shares) > 0) {
                t(false, "call shouldn't fail");
            }
        }
    }

    function withdraw(uint256 amount) public prepare {
        amount = between(amount, 0, stakedEbtc.convertToAssets(stakedEbtc.balanceOf(senderAddr)));

        uint256 previewShares = stakedEbtc.previewWithdraw(amount);

        __before();
        vm.prank(senderAddr);
        try stakedEbtc.withdraw(amount, senderAddr, senderAddr) returns (uint256 actualShares) {
            t(previewShares == actualShares, "previewShares == actualShares");
            __after();
            _checkPpfs();
        } catch {
            if (stakedEbtc.previewWithdraw(amount) > 0) {
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
                _checkPpfs();
            } catch {
                t(false, "call shouldn't fail");
            }
        } else {
            vm.prank(defaultGovernance);
            mockEbtc.transfer(address(stakedEbtc), amount);
            
            __after();

            _checkPpfs();
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
            _checkPpfs();
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
                _checkPpfs();
            } catch {
                t(false, "call shouldn't fail");
            }
        } catch {
            t(false, "call shouldn't fail");
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

        vm.prank(senderAddr);
        stakedEbtc.mint(shares, senderAddr);

        vm.prank(senderAddr);
        uint256 redeemedAssets = stakedEbtc.redeem(shares, senderAddr, senderAddr);

        vm.prank(senderAddr);
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
