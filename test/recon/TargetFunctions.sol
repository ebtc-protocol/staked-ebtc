
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {Properties} from "./Properties.sol";

abstract contract TargetFunctions is BaseTargetFunctions, Properties, BeforeAfter {
    uint256 public constant MAX_EBTC = 1e27;

    function deposit(uint256 amount) public {
        amount = between(amount, 0, MAX_EBTC);

        mockEbtc.mint(msg.sender, amount);
        mockEbtc.approve(address(stakedEbtc), type(uint256).max);

        try stakedEbtc.deposit(amount, msg.sender) {
        } catch {
            t(false, "call shouldn't fail");
        }
    }

    function redeem(uint256 shares) public {
        shares = between(shares, 0, stakedEbtc.balanceOf(msg.sender));

        try stakedEbtc.redeem(shares, msg.sender, msg.sender) {
        } catch {
            t(false, "call shouldn't fail");
        }
    }

    /*function donate() public {
        
    }*/
}
