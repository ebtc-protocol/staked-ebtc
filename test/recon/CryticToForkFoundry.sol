// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {TargetFunctions} from "./TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";
import {MockERC20} from "./MockERC20.sol";
import "src/StakedEbtc.sol";
import {vm} from "@chimera/Hevm.sol";
import "src/Dependencies/Governor.sol";
contract CryticToForkFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();

         _setupFork();
    }
}
