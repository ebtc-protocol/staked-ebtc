// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {vm} from "@chimera/Hevm.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";


import {TargetFunctions} from "./TargetFunctions.sol";
import {MockERC20} from "./MockERC20.sol";
import "src/StakedEbtc.sol";
import "src/Dependencies/Governor.sol";

contract CryticToForkFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        uint256 FORK_FROM_BLOCK = vm.envUint("FORK_FROM_BLOCK");
        // TODO: when testing locally change this block with block from coverage report set inside _setUpFork
        vm.createSelectFork(MAINNET_RPC_URL, FORK_FROM_BLOCK); 

        setupFork();
    }

// forge test --match-test test_rewardAccrual_0 --rpc-url RPC -vvvvv
 function test_rewardAccrual_0() public {
    vm.prank(address(0x10000));
    deposit(0);
    vm.prank(address(0x10000));
    rewardAccrual(0);
 }

 // forge test --match-test test_donate_1 --rpc-url RPC -vvvv
 function test_donate_1() public {
    vm.prank(address(0x10000));
    donate(7175949089520898362738541290599025649800349600,true);
 }
}