// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {IEnergyBiddingMarket} from "../../src/interfaces/IEnergyBiddingMarket.sol";
import {
    EnergyBiddingMarket__NoClaimableBalance,
    EnergyBiddingMarket__InvalidAddress
} from "../../src/types/MarketTypes.sol";

/// @title ClaimBalance Unit Tests
/// @notice Tests for claimBalance and claimBalanceTo functionality
contract ClaimBalanceTest is BaseTest {
    address internal BIDDER2 = makeAddr("bidder2");

    function setUp() public override {
        super.setUp();
        vm.deal(BIDDER2, 100 ether);
    }

    // ============ claimBalance Tests ============

    function test_claimBalance_Success() public {
        // Place bid and cancel to generate claimable balance
        vm.prank(BIDDER);
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);

        vm.prank(BIDDER);
        market.cancelBid(correctHour, 0);

        uint256 expectedBalance = minimumPrice * 100;
        assertEq(market.claimableBalance(BIDDER), expectedBalance);

        uint256 bidderBalanceBefore = BIDDER.balance;

        vm.prank(BIDDER);
        market.claimBalance();

        assertEq(market.claimableBalance(BIDDER), 0);
        assertEq(BIDDER.balance, bidderBalanceBefore + expectedBalance);
    }

    function test_claimBalance_NoBalance() public {
        vm.prank(BIDDER);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__NoClaimableBalance.selector,
                BIDDER
            )
        );
        market.claimBalance();
    }

    // ============ claimBalanceTo Tests ============

    function test_claimBalanceTo_Success() public {
        // Place bid and cancel to generate claimable balance
        vm.prank(BIDDER);
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);

        vm.prank(BIDDER);
        market.cancelBid(correctHour, 0);

        uint256 expectedBalance = minimumPrice * 100;
        address payable recipient = payable(makeAddr("recipient"));
        uint256 recipientBalanceBefore = recipient.balance;

        vm.prank(BIDDER);
        market.claimBalanceTo(recipient);

        assertEq(market.claimableBalance(BIDDER), 0);
        assertEq(recipient.balance, recipientBalanceBefore + expectedBalance);
    }

    function test_claimBalanceTo_ZeroAddress() public {
        // Generate a claimable balance first
        vm.prank(BIDDER);
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);

        vm.prank(BIDDER);
        market.cancelBid(correctHour, 0);

        vm.prank(BIDDER);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__InvalidAddress.selector
            )
        );
        market.claimBalanceTo(payable(address(0)));
    }

    function test_claimBalanceTo_NoBalance() public {
        vm.prank(BIDDER);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__NoClaimableBalance.selector,
                BIDDER
            )
        );
        market.claimBalanceTo(payable(makeAddr("recipient")));
    }

    function test_claimBalanceTo_EmitsBalanceClaimed() public {
        // Place bid and cancel to generate claimable balance
        vm.prank(BIDDER);
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);

        vm.prank(BIDDER);
        market.cancelBid(correctHour, 0);

        uint256 expectedBalance = minimumPrice * 100;
        address payable recipient = payable(makeAddr("recipient"));

        vm.expectEmit(true, true, false, true);
        emit IEnergyBiddingMarket.BalanceClaimed(BIDDER, recipient, expectedBalance);

        vm.prank(BIDDER);
        market.claimBalanceTo(recipient);
    }

    function test_claimBalance_EmitsBalanceClaimed() public {
        // Place bid and cancel to generate claimable balance
        vm.prank(BIDDER);
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);

        vm.prank(BIDDER);
        market.cancelBid(correctHour, 0);

        uint256 expectedBalance = minimumPrice * 100;

        vm.expectEmit(true, true, false, true);
        emit IEnergyBiddingMarket.BalanceClaimed(BIDDER, BIDDER, expectedBalance);

        vm.prank(BIDDER);
        market.claimBalance();
    }

    // ============ claimBalanceTo After Market Clearing ============

    function test_claimBalanceTo_AfterMarketClearing() public {
        // Place bid
        vm.prank(BIDDER);
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);

        // Place ask
        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        // Clear market
        vm.warp(clearHour);
        market.clearMarket(correctHour);

        // RECEIVER1 (seller) should have claimable balance
        uint256 sellerBalance = market.claimableBalance(RECEIVER1);
        assertTrue(sellerBalance > 0);

        address payable sellerRecipient = payable(makeAddr("sellerRecipient"));
        uint256 recipientBalanceBefore = sellerRecipient.balance;

        vm.prank(RECEIVER1);
        market.claimBalanceTo(sellerRecipient);

        assertEq(market.claimableBalance(RECEIVER1), 0);
        assertEq(sellerRecipient.balance, recipientBalanceBefore + sellerBalance);
    }

    function test_claimBalanceTo_MultipleClaims() public {
        // Generate balance via two canceled bids
        vm.startPrank(BIDDER);
        market.placeBid{value: minimumPrice * 50}(correctHour, 50);
        market.placeBid{value: minimumPrice * 75}(correctHour, 75);
        market.cancelBid(correctHour, 0);
        market.cancelBid(correctHour, 1);
        vm.stopPrank();

        uint256 expectedBalance = minimumPrice * 125;
        assertEq(market.claimableBalance(BIDDER), expectedBalance);

        address payable recipient = payable(makeAddr("recipient"));

        vm.prank(BIDDER);
        market.claimBalanceTo(recipient);

        assertEq(market.claimableBalance(BIDDER), 0);
        assertEq(recipient.balance, expectedBalance);

        // Second claim should revert
        vm.prank(BIDDER);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__NoClaimableBalance.selector,
                BIDDER
            )
        );
        market.claimBalanceTo(recipient);
    }
}
