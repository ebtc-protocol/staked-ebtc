
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {TargetFunctions} from "./TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";
import {vm as hevm} from "@chimera/Hevm.sol";

contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();

        mockEbtc.mint(address(0x10000), MAX_EBTC);
        mockEbtc.mint(address(0x20000), MAX_EBTC);
        mockEbtc.mint(address(0x30000), MAX_EBTC);

        vm.prank(address(0x10000));
        mockEbtc.approve(address(stakedEbtc), type(uint256).max);
        vm.prank(address(0x20000));
        mockEbtc.approve(address(stakedEbtc), type(uint256).max);
        vm.prank(address(0x30000));
        mockEbtc.approve(address(stakedEbtc), type(uint256).max);
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

    function testRedeemBroken() public {
        deposit(256);
        deposit(256);
        deposit(256);
        rewardAccrual(48743027362908275024177206706784719477041320055056926501611499549379336479930);
        total_assets_below_total_balance();
        redeem(14081555324802609486282391161562502039823688373);
        redeem(115792089237316195423570947188336821530327016604520359646366510738258800234672);
        redeem(115792089237316195423570985008687907853269984665640564039457584007907629891202);
        redeem(28335242420548078672872055242204429141836419187246766682602465188520481368254);
        redeem(108050672534864268963763294832020623833014451888420460187005423476058046575279);
        redeem(115792089237316195423570985008687907853269984665640564038157584007913129640436);
    }

    function test_erc4626_roundtrip_invariant_g_0() public {    
        vm.roll(3004);
        vm.warp(148624);
        vm.prank(0x0000000000000000000000000000000000010000);
        deposit(12544);
        
        vm.roll(34391);
        vm.warp(431534);
        vm.prank(0x0000000000000000000000000000000000010000);
        rewardAccrual(1143187891282894459216654264527943167721948170762202453974184122553535599440);
        
        vm.roll(34584);
        vm.warp(432534);
        vm.prank(0x0000000000000000000000000000000000010000);
        redeem(56164884713939694059920037084599102845166771396506689451114067542464279432113);
        
        vm.roll(64663);
        vm.warp(648001);
        vm.prank(0x0000000000000000000000000000000000020000);
        redeem(61847903950205624519929759118702430785146852664522385223125300218711571934976); 

        vm.roll(71549);
        vm.warp(1008554);
        vm.prank(0x0000000000000000000000000000000000020000);
        erc4626_roundtrip_invariant_g(319);
    }

    function testSumInit() public {
        deposit(82548787732489930966595887242219430396922353139416759276498465888425098196844);
        donate(73035438358962359599247245535717644510293383980530700180393992014309840921968, true);
        redeem(97);
        sum_of_user_assets_equals_total_assets();
    }

    function testRedeemFailure() public {
        vm.roll(23759);
        vm.warp(260875);
        vm.prank(0x0000000000000000000000000000000000020000);
        deposit(256);
        
        vm.roll(47517);
        vm.warp(521749);
        vm.prank(0x0000000000000000000000000000000000020000);
        deposit(256);

        vm.roll(124727);
        vm.warp(1238521);
        vm.prank(0x0000000000000000000000000000000000020000);
        deposit(256);
 
        vm.roll(127654);
        vm.warp(1297022);
        vm.prank(0x0000000000000000000000000000000000020000);
        rewardAccrual(48743027362908275024177206706784719477041320055056926501611499549379336479930);

        vm.roll(325933);
        vm.warp(2831401);
        vm.prank(0x0000000000000000000000000000000000030000);
        total_assets_below_total_balance();

        vm.roll(340732);
        vm.warp(3191954);
        vm.prank(0x0000000000000000000000000000000000010000);
        redeem(14081555324802609486282391161562502039823688373);

        vm.roll(364422);
        vm.warp(3611742);
        vm.prank(0x0000000000000000000000000000000000030000);
        redeem(115792089237316195423570947188336821530327016604520359646366510738258800234672);

        vm.roll(365965);
        vm.warp(3972359);
        vm.prank(0x0000000000000000000000000000000000020000);
        redeem(115792089237316195423570985008687907853269984665640564039457584007907629891202);

        vm.roll(365965);
        vm.warp(3972359);
        vm.prank(0x0000000000000000000000000000000000030000);
        redeem(28335242420548078672872055242204429141836419187246766682602465188520481368254);

        vm.roll(367347);
        vm.warp(3978121);
        vm.prank(0x0000000000000000000000000000000000030000);
        redeem(108050672534864268963763294832020623833014451888420460187005423476058046575279);

        vm.roll(400353);
        vm.warp(4338713);
        vm.prank(0x0000000000000000000000000000000000020000);
        redeem(115792089237316195423570985008687907853269984665640564038157584007913129640436);
    }

    function testRoundTripInvariant() public {

        vm.roll(23759);
        vm.warp(260875);
        senderAddr = 0x0000000000000000000000000000000000020000;
        deposit(256);

        vm.roll(47517);
        vm.warp(521749);
        senderAddr = 0x0000000000000000000000000000000000020000;
        deposit(256);

        vm.roll(71275);
        vm.warp(782623);
        senderAddr = 0x0000000000000000000000000000000000020000;
        deposit(256);

        vm.roll(71491);
        vm.warp(1195991);
        senderAddr = 0x0000000000000000000000000000000000010000;
        erc4626_roundtrip_invariant_h(115792089237316195423570985008687907853269984665640564039457584007913129639933);

        vm.roll(71491);
        vm.warp(1195991);
        senderAddr = 0x0000000000000000000000000000000000010000;
        rewardAccrual(80741865125442704854688655610158325461472798165736249452570844820213047146924);

        vm.roll(78750);
        vm.warp(1341923);
        senderAddr = 0x0000000000000000000000000000000000010000;
        redeem(115792089237316195423570985008687907853269984665640564039457584007913129639740);

        vm.roll(126781);
        vm.warp(1391794);
        senderAddr = 0x0000000000000000000000000000000000020000;
        erc4626_roundtrip_invariant_e(32);

        vm.roll(187232);
        vm.warp(1859674);
        senderAddr = 0x0000000000000000000000000000000000020000;
        redeem(40030);

        vm.roll(211078);
        vm.warp(2063801);
        senderAddr = 0x0000000000000000000000000000000000030000;
        erc4626_roundtrip_invariant_b(255);

        vm.roll(225651);
        vm.warp(2421904);
        senderAddr = 0x0000000000000000000000000000000000030000;
        erc4626_roundtrip_invariant_f(24);
    }
}
