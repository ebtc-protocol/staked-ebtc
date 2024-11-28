// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.25;

import {TargetFunctions} from "./TargetFunctions.sol";
import {CryticAsserts} from "@chimera/CryticAsserts.sol";
import {MockERC20} from "./MockERC20.sol";
import "src/StakedEbtc.sol";
import {vm} from "@chimera/Hevm.sol";
import "src/Dependencies/Governor.sol";

// echidna . --contract CryticForkTester --config echidna.yaml
// medusa fuzz
contract CryticForkTester is TargetFunctions, CryticAsserts {
    constructor() payable {
        setupFork();
    }
}