
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseSetup} from "@chimera/BaseSetup.sol";

import "src/LinearRewardsErc4626.sol";
import "src/Dependencies/Auth.sol";
import "src/StakedEbtc.sol";
import "src/Dependencies/Governor.sol";
import "src/Dependencies/AuthNoOwner.sol";
import "src/Dependencies/IRolesAuthority.sol";
import "src/Dependencies/RolesAuthority.sol";

import {vm} from "@chimera/Hevm.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockERC20} from "./MockERC20.sol";

abstract contract Setup is BaseSetup {

    StakedEbtc internal stakedEbtc;
    MockERC20 internal mockEbtc;
    address internal defaultGovernance;
    Governor internal governor;
    address[] internal senders;

    function setup() internal virtual override {
        defaultGovernance = vm.addr(0x123456);
        governor = new Governor(defaultGovernance);
        mockEbtc = new MockERC20("eBTC", "eBTC");

        uint256 TEN_PERCENT = 3_022_266_030; // per second rate compounded week each block (1.10^(365 * 86400 / 12) - 1) / 12 * 1e18

        stakedEbtc = new StakedEbtc({
            _underlying: IERC20(address(mockEbtc)),
            _name: "Staked eBTC",
            _symbol: "stEbtc",
            _rewardsCycleLength: 7 days,
            _maxDistributionPerSecondPerAsset: TEN_PERCENT,
            _authorityAddress: address(governor)
        });

        vm.prank(defaultGovernance);
        governor.setRoleCapability(12, address(stakedEbtc), StakedEbtc.setMaxDistributionPerSecondPerAsset.selector, true);

        vm.prank(defaultGovernance);
        governor.setRoleCapability(12, address(stakedEbtc), StakedEbtc.donate.selector, true);

        vm.prank(defaultGovernance);
        governor.setRoleCapability(12, address(stakedEbtc), StakedEbtc.sweep.selector, true);

        vm.prank(defaultGovernance);
        governor.setUserRole(defaultGovernance, 12, true);

        vm.prank(defaultGovernance);
        mockEbtc.approve(address(stakedEbtc), type(uint256).max);

        senders.push(address(0x10000));
        senders.push(address(0x20000));
        senders.push(address(0x30000));
    }
}
