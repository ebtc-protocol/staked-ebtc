
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {Properties} from "./Properties.sol";
import {vm} from "@chimera/Hevm.sol";
import "forge-std/console.sol";

abstract contract TargetFunctions is BaseTargetFunctions, Properties, BeforeAfter {
    uint256 public constant MAX_EBTC = 1e27;
    address internal senderAddr;

    modifier setSender() {
        if (senderAddr == address(0)) {
            senderAddr = msg.sender;
        }
        _;
    }

    function setSenderAddr(address newAddr) internal {
        senderAddr = newAddr;
    }

    function deposit(uint256 amount) public setSender {
        amount = between(amount, 1, MAX_EBTC);

        mockEbtc.mint(senderAddr, amount);

        vm.prank(senderAddr);
        mockEbtc.approve(address(stakedEbtc), type(uint256).max);

        vm.prank(senderAddr);
        try stakedEbtc.deposit(amount, senderAddr) {
        } catch {
            if (stakedEbtc.previewDeposit(amount) > 0) {
                t(false, "call shouldn't fail");
            }
        }
    }

    function redeem(uint256 shares) public setSender {
        shares = between(shares, 0, stakedEbtc.balanceOf(senderAddr));

        vm.prank(senderAddr);
        try stakedEbtc.redeem(shares, senderAddr, senderAddr) {
        } catch {
            if (stakedEbtc.previewRedeem(shares) > 0) {
                t(false, "call shouldn't fail");
            }
        }
    }

    function donate(uint256 amount, bool authorized) public setSender {
        amount = between(amount, 1, MAX_EBTC);

        mockEbtc.mint(defaultGovernance, amount);

        __before();

        if (authorized) {
            vm.prank(defaultGovernance);
            try stakedEbtc.donate(amount) {
                __after();

                t(_after.totalBalance > _before.totalBalance, "totalBalance should go up after an authorized donation");
            } catch {
                t(false, "call shouldn't fail");
            }
        } else {
            vm.prank(defaultGovernance);
            mockEbtc.transfer(address(stakedEbtc), amount);
            
            __after();
 
            t(_after.totalBalance == _before.totalBalance, "totalBalance should not go up after an unauthorized donation");
        }
    }

    function sweep(uint256 amount) public setSender {
        amount = between(amount, 1, MAX_EBTC);

        mockEbtc.mint(address(stakedEbtc), amount);

        __before();

        vm.prank(defaultGovernance);
        try stakedEbtc.sweep(address(mockEbtc)) {
            __after();
            t(_after.actualBalance < _before.actualBalance, "actualBalance should go down after sweep()");
            t(_after.totalBalance == _before.totalBalance, "totalBalance should not be affected by sweep()");
        } catch {
            t(false, "call shouldn't fail");
        }
    }
}
