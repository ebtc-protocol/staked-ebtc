// SPDX-License-Identifier: ISC
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IGnosisSafe } from "../src/Dependencies/IGnosisSafe.sol";
import { Governor } from "../src/Dependencies/Governor.sol";
import { ICollateral } from "../src/Dependencies/ICollateral.sol";
import { StakedEbtc } from "../src/StakedEbtc.sol";
import { FeeRecipientDonationModule } from "../src/FeeRecipientDonationModule.sol";

interface IEbtcToken is IERC20 {
    function mint(address _account, uint256 _amount) external;
}

// forge test --match-contract TestDonationModule --fork-url <RPC_URL> --fork-block-number 20780077
contract TestDonationModule is Test {

    StakedEbtc public stakedEbtc;
    uint256 public rewardsCycleLength;
    FeeRecipientDonationModule public donationModule;
    IEbtcToken ebtcToken;
    ICollateral collateralToken;
    address depositor;
    address keeper;

    function setUp() public virtual {
        depositor = vm.addr(0x123456);
        keeper = vm.addr(0x234567);
        ebtcToken = IEbtcToken(0x661c70333AA1850CcDBAe82776Bb436A0fCfeEfB);
        collateralToken = ICollateral(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

        // borrowerOperations
        vm.prank(0xd366e016Ae0677CdCE93472e603b75051E022AD0);
        ebtcToken.mint(depositor, 100e18);

        uint256 TEN_PERCENT = 3_022_266_030; // per second rate compounded week each block (1.10^(365 * 86400 / 12) - 1) / 12 * 1e18

        Governor governor = Governor(0x2A095d44831C26cFB6aCb806A6531AE3CA32DBc1);

        stakedEbtc = StakedEbtc(0x5cD81987743A17EFE67bb5BeD89fdE76f34ed884);

        vm.prank(depositor);
        ebtcToken.approve(address(stakedEbtc), type(uint256).max);
        
        donationModule = new FeeRecipientDonationModule({
            _steBtc: address(stakedEbtc),
            _dex:  0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45,
            _guardian: 0x690C74AF48BE029e763E61b4aDeB10E06119D3ba,
            _annualizedYieldBPS: 500,
            _minOutBPS: 9900,
            _swapPath: abi.encodePacked(
                0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
                uint24(100),
                0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                uint24(500),
                0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
                uint24(500),
                ebtcToken
            )
        });

        assertEq(donationModule.REWARDS_CYCLE_LENGTH(), 7 days);

        IGnosisSafe safe = IGnosisSafe(0x2CEB95D4A67Bf771f1165659Df3D11D8871E906f);

        // high-sec timelock
        vm.startPrank(0xaDDeE229Bd103bb5B10C3CdB595A01c425dd3264);
        governor.setRoleCapability(13, address(stakedEbtc), StakedEbtc.setMaxDistributionPerSecondPerAsset.selector, true);
        governor.setRoleCapability(13, address(stakedEbtc), StakedEbtc.donate.selector, true);
        governor.setRoleCapability(13, address(stakedEbtc), StakedEbtc.sweep.selector, true);
        governor.setRoleCapability(13, address(stakedEbtc), StakedEbtc.setMinRewardsPerPeriod.selector, true);
        governor.setUserRole(address(safe), 13, true);
        vm.stopPrank();

        vm.prank(donationModule.GOVERNANCE());
        donationModule.setKeeper(keeper);

        // enable safe module
        vm.prank(address(safe));
        safe.enableModule(address(donationModule));
    }

    function testEbtcDonation() public {
        vm.prank(depositor);
        stakedEbtc.deposit(10e18, depositor);

        vm.startPrank(address(0), address(0));
        (bool upkeepNeeded, bytes memory performData) = donationModule.checkUpkeep("");
        vm.stopPrank();

        uint256 ebtcBefore = stakedEbtc.totalBalance();

        vm.prank(donationModule.keeper());
        donationModule.performUpkeep(performData);

        assertEq(stakedEbtc.totalBalance() - ebtcBefore, 9576908003342648);
        assertEq(donationModule.lastProcessingTimestamp(), block.timestamp);

        vm.startPrank(address(0), address(0));
        (upkeepNeeded, performData) = donationModule.checkUpkeep("");
        vm.stopPrank();

        assertEq(upkeepNeeded, false);

        vm.warp(block.timestamp + donationModule.REWARDS_CYCLE_LENGTH());

        vm.startPrank(address(0), address(0));
        (upkeepNeeded, performData) = donationModule.checkUpkeep("");
        vm.stopPrank();

        assertEq(upkeepNeeded, false);

        vm.warp(block.timestamp + donationModule.REWARDS_CYCLE_LENGTH() + 1);

        vm.startPrank(address(0), address(0));
        (upkeepNeeded, performData) = donationModule.checkUpkeep("");
        vm.stopPrank();

        assertEq(upkeepNeeded, true);  
    }

    function testSendFeeToTreasury() public {
        vm.expectRevert(abi.encodeWithSelector(FeeRecipientDonationModule.NotGovernance.selector, depositor));
        vm.prank(depositor);
        donationModule.claimAndSendFeeToTreasury(2e18);

        uint256 balBefore = collateralToken.balanceOf(donationModule.TREASURY());
        vm.prank(donationModule.GOVERNANCE());
        donationModule.claimAndSendFeeToTreasury(2e18);
        uint256 balAfter = collateralToken.balanceOf(donationModule.TREASURY());

        // max 2 wei diff due to rounding
        assertApproxEqAbs(balAfter - balBefore, collateralToken.getPooledEthByShares(2e18), 2);
    }
}
