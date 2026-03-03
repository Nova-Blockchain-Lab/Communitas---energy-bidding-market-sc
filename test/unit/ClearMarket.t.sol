// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {
    EnergyBiddingMarket__HourNotInPast,
    EnergyBiddingMarket__NoBidsOrAsksForThisHour,
    EnergyBiddingMarket__MarketAlreadyClearedForThisHour,
    EnergyBiddingMarket__InvalidSortOrder,
    EnergyBiddingMarket__BidDoesNotExist
} from "../../src/types/MarketTypes.sol";

/// @title ClearMarket Unit Tests
/// @notice Tests for market clearing functionality
contract ClearMarketTest is BaseTest {
    function test_clearMarket_Success() public {
        // Place bid
        market.placeBid{value: defaultTestPrice * 100}(correctHour, 100);

        // Place ask
        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        // Clear market
        vm.warp(clearHour);
        market.clearMarket(correctHour);

        assertTrue(market.isMarketCleared(correctHour));
    }

    function test_clearMarket_WrongHour() public {
        uint256 futureHour = correctHour + 7200;
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__HourNotInPast.selector,
                futureHour
            )
        );
        market.clearMarket(futureHour);
    }

    function test_clearMarket_NoBidsOrAsks() public {
        vm.warp(clearHour);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__NoBidsOrAsksForThisHour.selector,
                correctHour
            )
        );
        market.clearMarket(correctHour);
    }

    function test_clearMarket_AlreadyCleared() public {
        market.placeBid{value: defaultTestPrice * 100}(correctHour, 100);

        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        vm.warp(clearHour);
        market.clearMarket(correctHour);

        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__MarketAlreadyClearedForThisHour.selector,
                correctHour
            )
        );
        market.clearMarket(correctHour);
    }

    function test_clearMarketPastHour() public {
        market.placeBid{value: defaultTestPrice * 100}(correctHour, 100);

        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        vm.warp(clearHour);
        market.clearMarketPastHour();

        assertTrue(market.isMarketCleared(correctHour));
    }

    // ============ Off-chain Sorting Tests ============

    function test_clearMarketWithSortedBids_Success() public {
        // Place bids with different prices
        vm.prank(BIDDER);
        market.placeBid{value: defaultTestPrice * 100}(correctHour, 100); // index 0, price = defaultTestPrice
        market.placeBid{value: defaultTestPrice * 2 * 50}(correctHour, 50);  // index 1, price = defaultTestPrice * 2
        market.placeBid{value: defaultTestPrice * 3 * 30}(correctHour, 30);  // index 2, price = defaultTestPrice * 3

        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        vm.warp(clearHour);

        // Sorted indices: [2, 1, 0] (highest price first)
        uint256[] memory sortedIndices = new uint256[](3);
        sortedIndices[0] = 2; // highest price
        sortedIndices[1] = 1;
        sortedIndices[2] = 0; // lowest price

        market.clearMarketWithSortedBids(correctHour, sortedIndices);

        assertTrue(market.isMarketCleared(correctHour));
    }

    function test_clearMarketWithSortedBids_InvalidOrder() public {
        // Place bids with different prices
        market.placeBid{value: defaultTestPrice * 100}(correctHour, 100);
        market.placeBid{value: defaultTestPrice * 2 * 50}(correctHour, 50);

        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        vm.warp(clearHour);

        // Wrong order: [0, 1] instead of [1, 0]
        uint256[] memory sortedIndices = new uint256[](2);
        sortedIndices[0] = 0; // lower price first - WRONG
        sortedIndices[1] = 1;

        vm.expectRevert(
            abi.encodeWithSelector(EnergyBiddingMarket__InvalidSortOrder.selector)
        );
        market.clearMarketWithSortedBids(correctHour, sortedIndices);
    }

    function test_clearMarketWithSortedBids_MissingBid() public {
        // Place 3 bids
        market.placeBid{value: defaultTestPrice * 100}(correctHour, 100);
        market.placeBid{value: defaultTestPrice * 50}(correctHour, 50);
        market.placeBid{value: defaultTestPrice * 30}(correctHour, 30);

        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        vm.warp(clearHour);

        // Only include 2 of 3 bids - should fail
        uint256[] memory sortedIndices = new uint256[](2);
        sortedIndices[0] = 0;
        sortedIndices[1] = 1;

        vm.expectRevert(
            abi.encodeWithSelector(EnergyBiddingMarket__InvalidSortOrder.selector)
        );
        market.clearMarketWithSortedBids(correctHour, sortedIndices);
    }

    function test_clearMarketWithSortedBids_InvalidIndex() public {
        market.placeBid{value: defaultTestPrice * 100}(correctHour, 100);

        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        vm.warp(clearHour);

        // Invalid index (out of bounds)
        uint256[] memory sortedIndices = new uint256[](1);
        sortedIndices[0] = 999;

        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__BidDoesNotExist.selector,
                correctHour,
                999
            )
        );
        market.clearMarketWithSortedBids(correctHour, sortedIndices);
    }

    function test_clearMarketWithSortedBids_GasSavings() public {
        // Place many bids to demonstrate gas savings
        for (uint256 i = 0; i < 20; i++) {
            market.placeBid{value: (defaultTestPrice + i) * 10}(correctHour, 10);
        }

        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        vm.warp(clearHour);

        // Pre-sort indices (descending by price)
        uint256[] memory sortedIndices = new uint256[](20);
        for (uint256 i = 0; i < 20; i++) {
            sortedIndices[i] = 19 - i; // Reverse order since higher index = higher price
        }

        market.clearMarketWithSortedBids(correctHour, sortedIndices);
        assertTrue(market.isMarketCleared(correctHour));
    }

    // ============ Clearing Price Tests ============

    function test_clearingPrice_UniformPriceAuction() public {
        // Bidder 1: 100 Watts at 2x minimum price
        market.placeBid{value: defaultTestPrice * 2 * 100}(correctHour, 100);
        // Bidder 2: 50 Watts at 3x minimum price
        market.placeBid{value: defaultTestPrice * 3 * 50}(correctHour, 50);

        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(120, RECEIVER1); // Only 120 available

        vm.warp(clearHour);
        market.clearMarket(correctHour);

        // Clearing price should be 2x minimum (marginal bid)
        uint256 clearingPrice = market.clearingPricePerHour(correctHour);
        assertEq(clearingPrice, defaultTestPrice * 2);
    }

    function test_clearingPrice_AllBidsFulfilled() public {
        // Single bid
        market.placeBid{value: defaultTestPrice * 100}(correctHour, 100);

        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(200, RECEIVER1); // More energy than bid

        vm.warp(clearHour);
        market.clearMarket(correctHour);

        uint256 clearingPrice = market.clearingPricePerHour(correctHour);
        assertEq(clearingPrice, defaultTestPrice);
    }
}
