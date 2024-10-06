// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.25;

import {BaseSetup} from "@chimera/BaseSetup.sol";

import "src/LinearRewardsErc4626.sol";
import "src/Dependencies/Auth.sol";
import "src/StakedEbtc.sol";
import "src/Dependencies/Governor.sol";
import "src/Dependencies/AuthNoOwner.sol";
import "src/Dependencies/IRolesAuthority.sol";
import "src/Dependencies/RolesAuthority.sol";

import {vm} from "@chimera/Hevm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockERC20} from "./MockERC20.sol";

abstract contract Setup is BaseSetup {
    StakedEbtc internal stakedEbtc;
    MockERC20 internal mockEbtc;
    address internal defaultGovernance;
    Governor internal governor;
    address[] internal senders;
    address initialDepositor;

    bool isEchidnaFork = false;

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
        governor.setRoleCapability(
            12, address(stakedEbtc), StakedEbtc.setMaxDistributionPerSecondPerAsset.selector, true
        );

        vm.prank(defaultGovernance);
        governor.setRoleCapability(12, address(stakedEbtc), StakedEbtc.donate.selector, true);

        vm.prank(defaultGovernance);
        governor.setRoleCapability(12, address(stakedEbtc), StakedEbtc.sweep.selector, true);

        vm.prank(defaultGovernance);
        governor.setUserRole(defaultGovernance, 12, true);

        vm.prank(defaultGovernance);
        mockEbtc.approve(address(stakedEbtc), type(uint256).max);

        initialDepositor = vm.addr(0x1111);

        // initial deposit from governance to prevent edge cases around totalSupply
        mockEbtc.mint(initialDepositor, 0.01e18);
        vm.prank(initialDepositor);
        mockEbtc.approve(address(stakedEbtc), type(uint256).max);
        vm.prank(initialDepositor);
        stakedEbtc.deposit(0.01e18, initialDepositor);

        senders.push(initialDepositor);
        senders.push(address(0x10000));
        senders.push(address(0x20000));
        senders.push(address(0x30000));
    }

    // SETUP FORK TESTING, see CryticFork...
    function _setupFork() internal {
        isEchidnaFork = true;
        // Replace governance with real governace
        defaultGovernance = 0xaDDeE229Bd103bb5B10C3CdB595A01c425dd3264;

        governor = Governor(0x2A095d44831C26cFB6aCb806A6531AE3CA32DBc1);

        // Real eBTC
        mockEbtc = MockERC20(0x661c70333AA1850CcDBAe82776Bb436A0fCfeEfB);

        // Send eBTC to Actor 1, 2, 3 and governance

        // Replace addresses
        stakedEbtc = StakedEbtc(0x5cD81987743A17EFE67bb5BeD89fdE76f34ed884);

        address WHALE = 0xEf9b4FddD861aa2F00eE039C323b7FAbd7AFE239;
        uint256 numberOfAddresses = 4;

        uint256 perAddy = mockEbtc.balanceOf(WHALE) / numberOfAddresses;

        vm.prank(WHALE);
        mockEbtc.transfer(address(0x10000), perAddy);
        vm.prank(WHALE);
        mockEbtc.transfer(address(0x20000), perAddy);
        vm.prank(WHALE);
        mockEbtc.transfer(address(0x30000), perAddy);
        vm.prank(WHALE);
        mockEbtc.transfer(defaultGovernance, perAddy);

        vm.prank(defaultGovernance);
        mockEbtc.approve(address(stakedEbtc), type(uint256).max);

        // == SETUP == //
        vm.prank(defaultGovernance);
        governor.setRoleCapability(13, address(stakedEbtc), StakedEbtc.setMaxDistributionPerSecondPerAsset.selector, true);
        vm.prank(defaultGovernance);
        governor.setRoleCapability(13, address(stakedEbtc), StakedEbtc.donate.selector, true);
        vm.prank(defaultGovernance);
        governor.setRoleCapability(13, address(stakedEbtc), StakedEbtc.sweep.selector, true);
        vm.prank(defaultGovernance);
        governor.setRoleCapability(13, address(stakedEbtc), StakedEbtc.setMinRewardsPerPeriod.selector, true);
        vm.prank(defaultGovernance);
        governor.setUserRole(defaultGovernance, 13, true);
    }
}
