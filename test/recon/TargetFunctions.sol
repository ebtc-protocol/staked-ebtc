
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {Properties} from "./Properties.sol";
import {vm} from "@chimera/Hevm.sol";

abstract contract TargetFunctions is BaseTargetFunctions, Properties, BeforeAfter {
    uint256 public constant MAX_EBTC = 1e27;
    address internal senderAddr;

    function deposit(uint256 amount) public {
        senderAddr = msg.sender;
        amount = between(amount, 1, MAX_EBTC);

        mockEbtc.mint(senderAddr, amount);

        vm.prank(senderAddr);
        mockEbtc.approve(address(stakedEbtc), type(uint256).max);

        vm.prank(senderAddr);
        try stakedEbtc.deposit(amount, senderAddr) {
        } catch {
            t(false, "call shouldn't fail");
        }
    }

    function redeem(uint256 shares) public {
        senderAddr = msg.sender;
        shares = between(shares, 0, stakedEbtc.balanceOf(senderAddr));

        vm.prank(senderAddr);
        try stakedEbtc.redeem(shares, senderAddr, senderAddr) {
        } catch {
            if (stakedEbtc.previewRedeem(shares) > 0) {
                t(false, "call shouldn't fail");
            }
        }
    }
}
