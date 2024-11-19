// SPDX-License-Identifier: ISC
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IGnosisSafe } from "../src/Dependencies/IGnosisSafe.sol";
import { Governor } from "../src/Dependencies/Governor.sol";
import { ICollateral } from "../src/Dependencies/ICollateral.sol";
import { StakedEbtc } from "../src/StakedEbtc.sol";
import { LinearRewardsErc4626 } from "../src/LinearRewardsErc4626.sol";
import { FeeRecipientDonationModule } from "../src/FeeRecipientDonationModule.sol";

interface IEbtcToken is IERC20 {
    function mint(address _account, uint256 _amount) external;
}

// forge test --match-contract TestDonationModule --fork-url <RPC_URL> --fork-block-number 21162517
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
        
        donationModule = new FeeRecipientDonationModule({
            _guardian: 0x690C74AF48BE029e763E61b4aDeB10E06119D3ba,
            _annualizedYieldBPS: 300, // 3%
            _minOutBPS: 9900, // 1%
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
                
        stakedEbtc = StakedEbtc(address(donationModule.STAKED_EBTC()));

        // borrowerOperations
        vm.prank(0xd366e016Ae0677CdCE93472e603b75051E022AD0);
        ebtcToken.mint(depositor, 100e18);

        Governor governor = Governor(0x2A095d44831C26cFB6aCb806A6531AE3CA32DBc1);

        vm.prank(depositor);
        ebtcToken.approve(address(stakedEbtc), type(uint256).max);

        IGnosisSafe safe = IGnosisSafe(0x2CEB95D4A67Bf771f1165659Df3D11D8871E906f);

        // enable safe module
        vm.prank(address(safe));
        safe.enableModule(address(donationModule));

        vm.prank(donationModule.GOVERNANCE());
        donationModule.setKeeper(keeper);
    }

    function _cycleEnd() private view returns (uint256) {
        (uint40 cycleEnd, , ) = stakedEbtc.rewardsCycleData();
        return cycleEnd;
    }

    function testDoDonation() public {
        vm.startPrank(address(0), address(0));
        (bool upkeepNeeded, bytes memory performData) = donationModule.checkUpkeep("");
        vm.stopPrank();

        console.log("upkeepNeeded", upkeepNeeded);
        console.logBytes(performData);
    }

    function testEbtcDonationSuccess() public {
        uint256 depositAmount = 10e18;

        vm.prank(depositor);
        stakedEbtc.deposit(depositAmount, depositor);

        // TEST: lastProcessedCycle starts at 0
        assertEq(donationModule.lastProcessedCycle(), 0);

        vm.startPrank(address(0), address(0));
        (bool upkeepNeeded, bytes memory performData) = donationModule.checkUpkeep("");
        vm.stopPrank();

        uint256 ebtcBefore = stakedEbtc.totalBalance();

        vm.prank(donationModule.keeper());
        donationModule.performUpkeep(performData);

        uint256 yieldAmount = (stakedEbtc.totalBalance() - ebtcBefore) * 52;
        uint256 computedYield = yieldAmount * donationModule.BPS() / depositAmount;

        assertApproxEqAbs(computedYield, donationModule.annualizedYieldBPS(), 1);
        // TEST: lastProcessedCycle == getCurrentCycle
        assertEq(donationModule.lastProcessedCycle(), donationModule.getCurrentCycle());
        // TEST: getCurrentCycle == currentTimestamp / REWARDS_CYCLE_LENGTH
        assertEq(donationModule.getCurrentCycle(), block.timestamp / stakedEbtc.REWARDS_CYCLE_LENGTH());

        vm.startPrank(address(0), address(0));
        (upkeepNeeded, performData) = donationModule.checkUpkeep("");
        vm.stopPrank();

        // TEST: no upkeep needed
        assertEq(upkeepNeeded, false);

        vm.warp(_cycleEnd());

        vm.startPrank(address(0), address(0));
        (upkeepNeeded, performData) = donationModule.checkUpkeep("");
        vm.stopPrank();

        // TEST: no upkeep needed
        assertEq(upkeepNeeded, false);

        // advance to cycleEnd + 1
        vm.warp(block.timestamp + 1);

        vm.startPrank(address(0), address(0));
        (upkeepNeeded, performData) = donationModule.checkUpkeep("");
        vm.stopPrank();

        // TEST: upkeep needed 1 second past cycleEnd
        assertEq(upkeepNeeded, true);

        stakedEbtc.syncRewardsAndDistribution();

        vm.startPrank(address(0), address(0));
        (upkeepNeeded, performData) = donationModule.checkUpkeep("");
        vm.stopPrank();

        assertEq(upkeepNeeded, true);

        vm.prank(donationModule.keeper());
        donationModule.performUpkeep(performData);

        vm.startPrank(address(0), address(0));
        (upkeepNeeded, performData) = donationModule.checkUpkeep("");
        vm.stopPrank();

        assertEq(upkeepNeeded, false);
        assertEq(donationModule.lastProcessedCycle(), donationModule.getCurrentCycle());
    }

    function testCheckUpkeepNeverOverflows(uint256 ts) public {
        ts = bound(ts, 0, 1000000);
        vm.warp(block.timestamp + ts);
        try donationModule.checkUpkeep("") {}
        catch (bytes memory returnData) {
            assertRevertReasonNotEqual(returnData, "Panic(17)");
            assertRevertReasonNotEqual(returnData, "Panic(18)");
        }
    }

    function testCheckTotalAssetsToGiveYieldTo() public {
        uint256 depositAmount = 10e18;

        vm.prank(depositor);
        stakedEbtc.deposit(depositAmount, depositor);

        vm.startPrank(address(0), address(0));
        (bool upkeepNeeded, bytes memory performData) = donationModule.checkUpkeep("");
        vm.stopPrank();

        (, , uint256 totalAssetsToGiveYieldTo) = abi.decode(performData, (uint256, uint256, uint256));

        (uint40 cycleEnd, ,) = stakedEbtc.rewardsCycleData();

        vm.warp(cycleEnd);

        stakedEbtc.syncRewardsAndDistribution();

        assertEq(totalAssetsToGiveYieldTo, stakedEbtc.storedTotalAssets());
    }

    function testEbtcDonationWithExecutionDelay() public {
        vm.prank(donationModule.GOVERNANCE());
        donationModule.setExecutionDelay(2 days);

        uint256 depositAmount = 10e18;

        vm.prank(depositor);
        stakedEbtc.deposit(depositAmount, depositor);

        // TEST: lastProcessedCycle starts at 0
        assertEq(donationModule.lastProcessedCycle(), 0);

        vm.startPrank(address(0), address(0));
        (bool upkeepNeeded, bytes memory performData) = donationModule.checkUpkeep("");
        vm.stopPrank();

        vm.prank(donationModule.keeper());
        donationModule.performUpkeep(performData);

        assertEq(donationModule.lastProcessedCycle(), donationModule.getCurrentCycle());
        assertEq(donationModule.getCurrentCycle(), block.timestamp / stakedEbtc.REWARDS_CYCLE_LENGTH());

        vm.startPrank(address(0), address(0));
        (upkeepNeeded, performData) = donationModule.checkUpkeep("");
        vm.stopPrank();

        // TEST: no upkeep needed
        assertEq(upkeepNeeded, false);

        vm.warp(_cycleEnd());

        vm.startPrank(address(0), address(0));
        (upkeepNeeded, performData) = donationModule.checkUpkeep("");
        vm.stopPrank();

        // TEST: no upkeep needed
        assertEq(upkeepNeeded, false);

        // advance to cycleEnd + 1
        vm.warp(block.timestamp + 1);

        vm.startPrank(address(0), address(0));
        (upkeepNeeded, performData) = donationModule.checkUpkeep("");
        vm.stopPrank();

        // TEST: no upkeep needed, cycleEnd + 2 days required
        assertEq(upkeepNeeded, false);

        vm.warp(block.timestamp + 2 days);

        vm.startPrank(address(0), address(0));
        (upkeepNeeded, performData) = donationModule.checkUpkeep("");
        vm.stopPrank();

        // TEST: upkeep needed
        assertEq(upkeepNeeded, true);
    }

    function _getFeeRecipientCollShares() private returns (uint256) {
        uint256 pendingShares = donationModule.ACTIVE_POOL().getSystemCollShares() - 
            donationModule.CDP_MANAGER().getSyncedSystemCollShares();
        return donationModule.ACTIVE_POOL().getFeeRecipientClaimableCollShares() + pendingShares;
    }

    function testSwapPathValidation() public {
        vm.prank(donationModule.GOVERNANCE());
        donationModule.setSwapPath(abi.encodePacked(
            0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
            uint24(100),
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            uint24(500),
            0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
            uint24(500),
            ebtcToken
        ));

        address gov = donationModule.GOVERNANCE();
        bytes memory path = abi.encodePacked(
            0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
            ebtcToken
        );

        // bad encoding
        vm.expectRevert();
        vm.prank(gov);
        donationModule.setSwapPath(path);
    }

    function testEbtcDonationCapped() public {
        vm.prank(depositor);
        stakedEbtc.deposit(10e18, depositor);

        uint256 sharesAvailable = _getFeeRecipientCollShares();

        vm.startPrank(address(0), address(0));
        (bool upkeepNeeded, bytes memory performData) = donationModule.checkUpkeep("");
        vm.stopPrank();

        (uint256 collSharesToClaim,) = abi.decode(performData, (uint256, uint256));

        // Shares to claim is less than shares available
        assertLt(collSharesToClaim, sharesAvailable);

        // Transfer 99.9% of collShares to treasury
        vm.prank(donationModule.GOVERNANCE());
        donationModule.claimFeeRecipientCollShares(sharesAvailable * 999 / 1000);

        vm.prank(donationModule.GOVERNANCE());
        donationModule.sendFeeRecipientCollSharesToTreasury(sharesAvailable * 999 / 1000);

        sharesAvailable = _getFeeRecipientCollShares();

        vm.startPrank(address(0), address(0));
        (upkeepNeeded, performData) = donationModule.checkUpkeep("");
        vm.stopPrank();

        (collSharesToClaim,) = abi.decode(performData, (uint256, uint256));

        // Shares to claim should be capped at sharesAvailable
        assertEq(collSharesToClaim, sharesAvailable);
    }

    function testSetKeeper() public {
        address newKeeper = vm.addr(0x22222);
        assertEq(donationModule.keeper(), keeper);

        vm.prank(donationModule.GOVERNANCE());
        donationModule.setKeeper(newKeeper);

        assertEq(donationModule.keeper(), newKeeper);
    }

    function testSendFeeToTreasury() public {
        vm.expectRevert(abi.encodeWithSelector(FeeRecipientDonationModule.NotGovernance.selector, depositor));
        vm.prank(depositor);
        donationModule.claimFeeRecipientCollShares(2e18);

        uint256 sharesBefore = collateralToken.sharesOf(address(donationModule.SAFE()));
        vm.prank(donationModule.GOVERNANCE());
        donationModule.claimFeeRecipientCollShares(2e18);
        uint256 sharesAfter = collateralToken.sharesOf(address(donationModule.SAFE()));

        uint256 sharesDiff = sharesAfter - sharesBefore;

        vm.expectRevert(abi.encodeWithSelector(FeeRecipientDonationModule.NotGovernance.selector, depositor));
        vm.prank(depositor);
        donationModule.sendFeeRecipientCollSharesToTreasury(sharesDiff);

        sharesBefore = collateralToken.sharesOf(donationModule.TREASURY());
        vm.prank(donationModule.GOVERNANCE());
        donationModule.sendFeeRecipientCollSharesToTreasury(sharesDiff);
        sharesAfter = collateralToken.sharesOf(donationModule.TREASURY());

        assertEq(sharesAfter - sharesBefore, 2e18);
    }

    function testSendEbtcToTreasury() public {
        address safeAddr = address(donationModule.SAFE());

        vm.prank(depositor);
        ebtcToken.transfer(safeAddr, 1e18);

        vm.expectRevert(abi.encodeWithSelector(FeeRecipientDonationModule.NotGovernance.selector, depositor));
        vm.prank(depositor);
        donationModule.sendEbtcToTreasury(1e18);   

        uint256 balBefore = ebtcToken.balanceOf(donationModule.TREASURY());
        vm.prank(donationModule.GOVERNANCE());
        donationModule.sendEbtcToTreasury(1e18);   
        uint256 balAfter = ebtcToken.balanceOf(donationModule.TREASURY());

        assertEq(balAfter - balBefore, 1e18);
    }

    function assertRevertReasonNotEqual(bytes memory returnData, string memory reason) internal {
        bool isEqual = _isRevertReasonEqual(returnData, reason);
        assertTrue(!isEqual);
    }

    function _isRevertReasonEqual(
        bytes memory returnData,
        string memory reason
    ) internal pure returns (bool) {
        return (keccak256(abi.encodePacked(_getRevertMsg(returnData))) ==
            keccak256(abi.encodePacked(reason)));
    }

    // https://ethereum.stackexchange.com/a/83577
    function _getRevertMsg(bytes memory returnData) internal pure returns (string memory) {
        // Check that the data has the right size: 4 bytes for signature + 32 bytes for panic code
        if (returnData.length == 4 + 32) {
            // Check that the data starts with the Panic signature
            bytes4 panicSignature = bytes4(keccak256(bytes("Panic(uint256)")));
            for (uint i = 0; i < 4; i++) {
                if (returnData[i] != panicSignature[i]) return "Undefined signature";
            }

            uint256 panicCode;
            for (uint i = 4; i < 36; i++) {
                panicCode = panicCode << 8;
                panicCode |= uint8(returnData[i]);
            }

            // Now convert the panic code into its string representation
            if (panicCode == 17) {
                return "Panic(17)";
            }

            // Add other panic codes as needed or return a generic "Unknown panic"
            return "Undefined panic code";
        }

        // If the returnData length is less than 68, then the transaction failed silently (without a revert message)
        if (returnData.length < 68) return "Transaction reverted silently";

        assembly {
            // Slice the sighash.
            returnData := add(returnData, 0x04)
        }
        return abi.decode(returnData, (string)); // All that remains is the revert string
    }
}
