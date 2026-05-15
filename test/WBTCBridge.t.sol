// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/WBTC.sol";
import "../src/MyrxBTCBridge.sol";

contract WBTCBridgeTest is Test {

    WBTC          internal wbtc;
    MyrxBTCBridge internal bridge;

    address internal owner   = address(this);
    address internal relayer = address(0x1);
    address internal alice   = address(0x2);
    address internal bob     = address(0x3);

    bytes32 internal constant TX1 = keccak256("btc_tx_1");
    bytes32 internal constant TX2 = keccak256("btc_tx_2");
    bytes32 internal constant TX3 = keccak256("btc_tx_3");

    function setUp() public {
        wbtc   = new WBTC();
        bridge = new MyrxBTCBridge(address(wbtc), relayer, "bc1qcustody000");
        wbtc.setBridge(address(bridge));
    }

    // ─── Mint tests ──────────────────────────────────────────────────────────

    function test_Mint_Success() public {
        vm.prank(relayer);
        bridge.mintWBTC(alice, 100_000, TX1);
        assertEq(wbtc.balanceOf(alice), 100_000);
    }

    function test_Mint_ReplayReverts() public {
        vm.prank(relayer);
        bridge.mintWBTC(alice, 100_000, TX1);

        vm.prank(relayer);
        vm.expectRevert("BTC:replay");
        bridge.mintWBTC(alice, 100_000, TX1);
    }

    function test_Mint_OnlyRelayer() public {
        vm.prank(alice);
        vm.expectRevert("BTC:relayer");
        bridge.mintWBTC(alice, 100_000, TX1);
    }

    function test_Mint_BelowMinReverts() public {
        vm.prank(relayer);
        vm.expectRevert("BTC:below_min");
        bridge.mintWBTC(alice, 9_999, TX1);
    }

    function test_Mint_DailyCap() public {
        uint256 cap = bridge.dailyMintCap();

        vm.prank(relayer);
        bridge.mintWBTC(alice, cap, TX1);

        vm.prank(relayer);
        vm.expectRevert("BTC:daily_cap");
        bridge.mintWBTC(alice, 10_000, TX2);
    }

    function test_Mint_DailyCapResetsAfter24h() public {
        uint256 cap = bridge.dailyMintCap();

        vm.prank(relayer);
        bridge.mintWBTC(alice, cap, TX1);

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(relayer);
        bridge.mintWBTC(alice, 100_000, TX2);
        assertEq(wbtc.balanceOf(alice), cap + 100_000);
    }

    function test_Mint_MultipleTxDifferentHashes() public {
        vm.prank(relayer);
        bridge.mintWBTC(alice, 100_000, TX1);
        vm.prank(relayer);
        bridge.mintWBTC(alice, 200_000, TX2);
        assertEq(wbtc.balanceOf(alice), 300_000);
    }

    // ─── Redeem tests ────────────────────────────────────────────────────────

    function test_Redeem_InitiateSuccess() public {
        vm.prank(relayer);
        bridge.mintWBTC(alice, 500_000, TX1);

        vm.prank(alice);
        bridge.initiateRedemption(200_000, "bc1qdest000");

        assertEq(wbtc.balanceOf(alice), 300_000);
    }

    function test_Redeem_InsufficientWBTC() public {
        vm.prank(relayer);
        bridge.mintWBTC(alice, 100_000, TX1);

        vm.prank(alice);
        vm.expectRevert("WBTC:insufficient_balance");
        bridge.initiateRedemption(200_000, "bc1qdest000");
    }

    function test_Redeem_ConfirmSuccess() public {
        vm.prank(relayer);
        bridge.mintWBTC(alice, 500_000, TX1);

        vm.prank(alice);
        bridge.initiateRedemption(200_000, "bc1qdest000");

        vm.prank(relayer);
        bridge.confirmRedemption(0, TX2);

        (,,,, bytes32 txh, bool confirmed) = bridge.redemptions(0);
        assertTrue(confirmed);
        assertEq(txh, TX2);
    }

    function test_Redeem_DoubleConfirmReverts() public {
        vm.prank(relayer);
        bridge.mintWBTC(alice, 500_000, TX1);
        vm.prank(alice);
        bridge.initiateRedemption(200_000, "bc1qdest000");
        vm.prank(relayer);
        bridge.confirmRedemption(0, TX2);

        vm.prank(relayer);
        vm.expectRevert("BTC:already_confirmed");
        bridge.confirmRedemption(0, TX3);
    }

    function test_Redeem_NonRelayerConfirmReverts() public {
        vm.prank(relayer);
        bridge.mintWBTC(alice, 500_000, TX1);
        vm.prank(alice);
        bridge.initiateRedemption(200_000, "bc1qdest000");

        vm.prank(alice);
        vm.expectRevert("BTC:relayer");
        bridge.confirmRedemption(0, TX2);
    }

    function test_Redeem_TxHashReusedInConfirmReverts() public {
        vm.prank(relayer);
        bridge.mintWBTC(alice, 500_000, TX1);
        vm.prank(alice);
        bridge.initiateRedemption(200_000, "bc1qdest000");

        // TX1 was used in mint — can't reuse as confirm hash
        vm.prank(relayer);
        vm.expectRevert("BTC:replay");
        bridge.confirmRedemption(0, TX1);
    }

    // ─── Pause tests ─────────────────────────────────────────────────────────

    function test_Pause_BlocksMint() public {
        bridge.setPaused(true);
        vm.prank(relayer);
        vm.expectRevert("BTC:paused");
        bridge.mintWBTC(alice, 100_000, TX1);
    }

    function test_Pause_BlocksRedeem() public {
        vm.prank(relayer);
        bridge.mintWBTC(alice, 500_000, TX1);
        bridge.setPaused(true);

        vm.prank(alice);
        vm.expectRevert("BTC:paused");
        bridge.initiateRedemption(200_000, "bc1qdest000");
    }

    function test_OnlyOwnerCanPause() public {
        vm.prank(alice);
        vm.expectRevert("BTC:owner");
        bridge.setPaused(true);
    }

    // ─── Admin tests ─────────────────────────────────────────────────────────

    function test_SetRelayer() public {
        bridge.setRelayer(bob);
        assertEq(bridge.relayer(), bob);
    }

    function test_SetRelayer_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert("BTC:owner");
        bridge.setRelayer(bob);
    }

    function test_SetDailyCap() public {
        bridge.setDailyMintCap(500_000_000);
        assertEq(bridge.dailyMintCap(), 500_000_000);
    }

    // ─── WBTC standalone tests ───────────────────────────────────────────────

    function test_WBTC_OnlyBridgeMint() public {
        vm.prank(alice);
        vm.expectRevert("WBTC:bridge_only");
        wbtc.mint(alice, 100_000);
    }

    function test_WBTC_OnlyBridgeBurn() public {
        vm.prank(relayer);
        bridge.mintWBTC(alice, 100_000, TX1);

        vm.prank(alice);
        vm.expectRevert("WBTC:bridge_only");
        wbtc.burn(alice, 100_000);
    }

    function test_WBTC_Transfer() public {
        vm.prank(relayer);
        bridge.mintWBTC(alice, 100_000, TX1);

        vm.prank(alice);
        wbtc.transfer(bob, 40_000);

        assertEq(wbtc.balanceOf(alice), 60_000);
        assertEq(wbtc.balanceOf(bob),   40_000);
    }

    function test_WBTC_Approve_TransferFrom() public {
        vm.prank(relayer);
        bridge.mintWBTC(alice, 100_000, TX1);

        vm.prank(alice);
        wbtc.approve(bob, 50_000);

        vm.prank(bob);
        wbtc.transferFrom(alice, bob, 50_000);

        assertEq(wbtc.balanceOf(alice), 50_000);
        assertEq(wbtc.balanceOf(bob),   50_000);
    }
}
