
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.25;

import {BaseSetup} from "@chimera/BaseSetup.sol";
import {console2} from "forge-std/console2.sol";

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

    // local fuzzing setup
    StakedEbtc internal stakedEbtc;
    MockERC20 internal mockEbtc;
    address internal defaultGovernance;
    address internal defaultFeeRecipient;
    Governor internal governor;
    address[] internal senders;
    address initialDepositor;

    function setup() internal virtual override {
        defaultGovernance = vm.addr(0x123456);
        defaultFeeRecipient = vm.addr(0x234567);
        governor = new Governor(defaultGovernance);
        mockEbtc = new MockERC20("eBTC", "eBTC");

        uint256 TEN_PERCENT = 3_022_266_030; // per second rate compounded week each block (1.10^(365 * 86400 / 12) - 1) / 12 * 1e18

        stakedEbtc = new StakedEbtc({
            _underlying: IERC20(address(mockEbtc)),
            _name: "Staked eBTC",
            _symbol: "stEbtc",
            _rewardsCycleLength: 7 days,
            _maxDistributionPerSecondPerAsset: TEN_PERCENT,
            _authorityAddress: address(governor),
            _feeRecipient: defaultFeeRecipient
        });

        vm.prank(defaultGovernance);
        governor.setRoleCapability(12, address(stakedEbtc), StakedEbtc.setMaxDistributionPerSecondPerAsset.selector, true);

        vm.prank(defaultGovernance);
        governor.setRoleCapability(12, address(stakedEbtc), StakedEbtc.donate.selector, true);

        vm.prank(defaultGovernance);
        governor.setRoleCapability(12, address(stakedEbtc), StakedEbtc.sweep.selector, true);

        vm.prank(defaultGovernance);
        governor.setRoleCapability(12, address(stakedEbtc), StakedEbtc.setMintingFee.selector, true);

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

    function setupFork() internal virtual {
        defaultGovernance = address(0xaDDeE229Bd103bb5B10C3CdB595A01c425dd3264);
        governor = Governor(0x2A095d44831C26cFB6aCb806A6531AE3CA32DBc1);

        // wrap the deployed eBTC token with the MockERC20 interface
        mockEbtc = MockERC20(0x661c70333AA1850CcDBAe82776Bb436A0fCfeEfB);
        stakedEbtc = StakedEbtc(0x5884055ca6CacF53A39DA4ea76DD88956baFAee0);

        senders.push(address(0x10000));
        senders.push(address(0x20000));
        senders.push(address(0x30000));
        senders.push(address(governor));

        // distribute whale balance among actors
        address whale = address(0x272BF7e4Ce3308B1Fb5e54d6a1Fc32113619c401);
        _distributeWhaleBalance(whale, address(mockEbtc), senders);

        // max approves system contracts for actor tokens
        _approveSystemForActorTokens(address(stakedEbtc), address(mockEbtc), senders);

        // governance configuration
        vm.prank(defaultGovernance);
        governor.setRoleCapability(12, address(stakedEbtc), StakedEbtc.setMaxDistributionPerSecondPerAsset.selector, true);
        vm.prank(defaultGovernance);
        governor.setRoleCapability(12, address(stakedEbtc), StakedEbtc.donate.selector, true);
        vm.prank(defaultGovernance);
        governor.setRoleCapability(12, address(stakedEbtc), StakedEbtc.sweep.selector, true);
        vm.prank(defaultGovernance);
        governor.setRoleCapability(12, address(stakedEbtc), StakedEbtc.setMintingFee.selector, true);
        vm.prank(defaultGovernance);
        governor.setUserRole(defaultGovernance, 12, true);
    }

    function _distributeWhaleBalance(address whale, address token, address[] memory actors) internal {
        uint256 whaleBalance = IERC20(token).balanceOf(whale);
        uint256 amountPerActor = whaleBalance / actors.length;

        for(uint8 i; i < actors.length; i++) {
            vm.prank(whale);
            IERC20(token).transfer(actors[i], amountPerActor);
        }
    }

    function _approveSystemForActorTokens(address systemContract, address token, address[] memory actors) internal {
        for(uint8 i; i < actors.length; i++) {
            vm.prank(actors[i]);
            IERC20(token).approve(systemContract, type(uint256).max);
        }
    }
}
