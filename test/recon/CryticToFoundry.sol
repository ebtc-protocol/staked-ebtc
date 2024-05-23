
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {TargetFunctions} from "./TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";
import {vm as hevm} from "@chimera/Hevm.sol";

contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

    function testSumOfAssets() public {

        setSenderAddr(address(0x20000));
        deposit(115792089237316195423570985008687907853269984665640564039457584007907629891202);

        setSenderAddr(address(0x30000));
        deposit(82548787732489930966595887242219430396922353139416759276498465888425098196844);

        donate(73035438358962359599247245535717644510293383980530700180393992014309840921968, true);

        setSenderAddr(address(0x20000));
        redeem(97);

        sum_of_user_assets_equals_total_assets();    
    }
}
