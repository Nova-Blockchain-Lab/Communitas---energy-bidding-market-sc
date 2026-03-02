// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {IEnergyBiddingMarket} from "../../src/interfaces/IEnergyBiddingMarket.sol";
import {AskInput} from "../../src/types/MarketTypes.sol";

/// @title Event Emissions Unit Tests
/// @notice Tests that all events are emitted correctly
contract EventEmissionsTest is BaseTest {
    address internal BIDDER2 = makeAddr("bidder2");

    function setUp() public override {
        super.setUp();
        vm.deal(BIDDER2, 100 ether);
    }

    // ============ BidPlaced Event Tests ============

    function test_BidPlaced_SingleBid() public {
        vm.expectEmit(true, true, false, true);
        emit IEnergyBiddingMarket.BidPlaced(address(this), correctHour, 100, minimumPrice);

        market.placeBid{value: minimumPrice * 100}(correctHour, 100);
    }

    function test_BidPlaced_MultipleBidsRange() public {
        uint256 endHour = correctHour + 7200;

        vm.expectEmit(true, true, false, true);
        emit IEnergyBiddingMarket.BidPlaced(address(this), correctHour, 100, minimumPrice);
        vm.expectEmit(true, true, false, true);
        emit IEnergyBiddingMarket.BidPlaced(address(this), correctHour + 3600, 100, minimumPrice);

        market.placeMultipleBids{value: minimumPrice * 100 * 2}(correctHour, endHour, 100);
    }

    function test_BidPlaced_MultipleBidsArray() public {
        uint256[] memory biddingHours = new uint256[](2);
        biddingHours[0] = correctHour;
        biddingHours[1] = correctHour + 3600;

        vm.expectEmit(true, true, false, true);
        emit IEnergyBiddingMarket.BidPlaced(address(this), correctHour, 100, minimumPrice);
        vm.expectEmit(true, true, false, true);
        emit IEnergyBiddingMarket.BidPlaced(address(this), correctHour + 3600, 100, minimumPrice);

        market.placeMultipleBids{value: minimumPrice * 100 * 2}(biddingHours, 100);
    }

    // ============ AskPlaced Event Tests ============

    function test_AskPlaced_SingleAsk() public {
        vm.warp(askHour);

        vm.expectEmit(true, true, false, true);
        emit IEnergyBiddingMarket.AskPlaced(RECEIVER1, correctHour, 100);

        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);
    }

    function test_AskPlaced_BatchAsk() public {
        market.placeBid{value: minimumPrice * 200}(correctHour, 200);
        vm.warp(clearHour);

        AskInput[] memory asks = new AskInput[](2);
        asks[0] = AskInput({receiver: RECEIVER1, amount: 100});
        asks[1] = AskInput({receiver: RECEIVER2, amount: 50});

        uint256[] memory sortedIndices = new uint256[](1);
        sortedIndices[0] = 0;

        vm.expectEmit(true, true, false, true);
        emit IEnergyBiddingMarket.AskPlaced(RECEIVER1, correctHour, 100);
        vm.expectEmit(true, true, false, true);
        emit IEnergyBiddingMarket.AskPlaced(RECEIVER2, correctHour, 50);

        vm.prank(SELLER);
        market.placeAsksAndClearMarket(correctHour, asks, sortedIndices);
    }

    // ============ BidCanceled Event Tests ============

    function test_BidCanceled_Event() public {
        vm.prank(BIDDER);
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);

        uint256 expectedRefund = minimumPrice * 100;

        vm.expectEmit(true, true, true, true);
        emit IEnergyBiddingMarket.BidCanceled(correctHour, 0, BIDDER, expectedRefund);

        vm.prank(BIDDER);
        market.cancelBid(correctHour, 0);
    }

    // ============ MarketCleared Event Tests ============

    function test_MarketCleared_Event() public {
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);

        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        vm.expectEmit(true, false, false, true);
        emit IEnergyBiddingMarket.MarketCleared(correctHour, minimumPrice);

        vm.warp(clearHour);
        market.clearMarket(correctHour);
    }

    function test_MarketCleared_ViaSortedBids() public {
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);

        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        vm.warp(clearHour);

        uint256[] memory sortedIndices = new uint256[](1);
        sortedIndices[0] = 0;

        vm.expectEmit(true, false, false, true);
        emit IEnergyBiddingMarket.MarketCleared(correctHour, minimumPrice);

        market.clearMarketWithSortedBids(correctHour, sortedIndices);
    }

    function test_MarketCleared_ViaPastHour() public {
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);

        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        vm.warp(clearHour);

        vm.expectEmit(true, false, false, true);
        emit IEnergyBiddingMarket.MarketCleared(correctHour, minimumPrice);

        market.clearMarketPastHour();
    }

    // ============ BalanceClaimed Event Tests ============

    function test_BalanceClaimed_ViaClaimBalance() public {
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

    function test_BalanceClaimed_ViaClaimBalanceTo() public {
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

    // ============ BidRefunded Event Tests ============

    function test_BidRefunded_NoEnergy() public {
        // Place bid but no asks -> all bids get refunded
        vm.prank(BIDDER);
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);

        uint256 expectedRefund = minimumPrice * 100;

        vm.expectEmit(true, true, true, true);
        emit IEnergyBiddingMarket.BidRefunded(correctHour, 0, BIDDER, expectedRefund);

        vm.warp(clearHour);
        market.clearMarket(correctHour);
    }

    function test_BidRefunded_PartialEnergy() public {
        // Place 2 bids, but only enough energy for 1
        vm.prank(BIDDER);
        market.placeBid{value: minimumPrice * 2 * 100}(correctHour, 100); // higher price, index 0
        vm.prank(BIDDER2);
        market.placeBid{value: minimumPrice * 50}(correctHour, 50); // lower price, index 1

        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1); // only 100 energy, bid 0 gets it all

        vm.warp(clearHour);

        // Bid 1 (BIDDER2) should be refunded since all energy goes to bid 0
        uint256 expectedRefund = minimumPrice * 50;

        vm.expectEmit(true, true, true, true);
        emit IEnergyBiddingMarket.BidRefunded(correctHour, 1, BIDDER2, expectedRefund);

        market.clearMarket(correctHour);
    }

    function test_BidRefunded_MultipleRefunds() public {
        // Place 3 bids at different prices
        vm.prank(BIDDER);
        market.placeBid{value: minimumPrice * 3 * 30}(correctHour, 30); // index 0, price 3x
        vm.prank(BIDDER2);
        market.placeBid{value: minimumPrice * 2 * 40}(correctHour, 40); // index 1, price 2x
        market.placeBid{value: minimumPrice * 50}(correctHour, 50);     // index 2, price 1x

        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(30, RECEIVER1); // only 30 energy

        vm.warp(clearHour);

        // Record logs to count BidRefunded events
        vm.recordLogs();
        market.clearMarket(correctHour);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 bidRefundedTopic = keccak256("BidRefunded(uint256,uint256,address,uint256)");
        uint256 refundCount;
        for (uint256 i; i < entries.length; i++) {
            if (entries[i].topics[0] == bidRefundedTopic) {
                refundCount++;
            }
        }

        // Bids 1 and 2 should be refunded (only 30 energy available for 30+40+50=120 demand)
        assertEq(refundCount, 2, "Should emit 2 BidRefunded events");
    }

    // ============ SellerWhitelistUpdated Event Tests ============

    function test_SellerWhitelistUpdated_Enable() public {
        address newSeller = makeAddr("newSeller");

        vm.expectEmit(true, false, false, true);
        emit IEnergyBiddingMarket.SellerWhitelistUpdated(newSeller, true);

        market.whitelistSeller(newSeller, true);
    }

    function test_SellerWhitelistUpdated_Disable() public {
        vm.expectEmit(true, false, false, true);
        emit IEnergyBiddingMarket.SellerWhitelistUpdated(SELLER, false);

        market.whitelistSeller(SELLER, false);
    }
}
