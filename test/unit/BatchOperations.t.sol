// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {
    AskInput,
    EnergyBiddingMarket__SellerIsNotWhitelisted,
    EnergyBiddingMarket__HourNotInPast,
    EnergyBiddingMarket__NoBidsOrAsksForThisHour,
    EnergyBiddingMarket__InvalidSellerAddress,
    EnergyBiddingMarket__AmountCannotBeZero,
    EnergyBiddingMarket__WrongHoursProvided
} from "../../src/types/MarketTypes.sol";

/// @title Batch Operations Unit Tests
/// @notice Tests for placeMultipleBids and placeAsksAndClearMarket
contract BatchOperationsTest is BaseTest {
    // ============ placeMultipleBids (range) Tests ============

    function test_placeMultipleBids_RangeSuccess() public {
        uint256 beginHour = correctHour;
        uint256 endHour = correctHour + 3600 * 3; // 3 bidHours
        uint256 amount = 100;

        uint256 totalHours = (endHour - beginHour) / 3600;
        uint256 totalValue = testPrice * amount * totalHours;

        market.placeMultipleBids{value: totalValue}(beginHour, endHour, amount);

        // Check each hour has a bid
        for (uint256 h = beginHour; h < endHour; h += 3600) {
            assertEq(market.totalBidsByHour(h), 1);
        }
    }

    function test_placeMultipleBids_RangeInvalidHours() public {
        uint256 beginHour = correctHour + 3600;
        uint256 endHour = correctHour; // End before begin

        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__WrongHoursProvided.selector,
                beginHour,
                endHour
            )
        );
        market.placeMultipleBids{value: testPrice * 100}(beginHour, endHour, 100);
    }

    // ============ placeMultipleBids (array) Tests ============

    function test_placeMultipleBids_ArraySuccess() public {
        uint256[] memory bidHours = new uint256[](3);
        bidHours[0] = correctHour;
        bidHours[1] = correctHour + 3600;
        bidHours[2] = correctHour + 7200;

        uint256 amount = 100;
        uint256 totalValue = testPrice * amount * 3;

        market.placeMultipleBids{value: totalValue}(bidHours, amount);

        for (uint256 i = 0; i < bidHours.length; i++) {
            assertEq(market.totalBidsByHour(bidHours[i]), 1);
        }
    }

    function test_placeMultipleBids_ArrayZeroAmount() public {
        uint256[] memory bidHours = new uint256[](2);
        bidHours[0] = correctHour;
        bidHours[1] = correctHour + 3600;

        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__AmountCannotBeZero.selector
            )
        );
        market.placeMultipleBids{value: testPrice * 100}(bidHours, 0);
    }

    // ============ placeAsksAndClearMarket Tests ============

    function test_placeAsksAndClearMarket_Success() public {
        // Place bids first
        market.placeBid{value: testPrice * 100}(correctHour, 100);
        market.placeBid{value: testPrice * 2 * 50}(correctHour, 50);

        vm.warp(clearHour);

        AskInput[] memory asks = new AskInput[](2);
        asks[0] = AskInput({receiver: RECEIVER1, amount: 80});
        asks[1] = AskInput({receiver: RECEIVER2, amount: 70});

        // Get sorted indices (descending by price)
        uint256[] memory sortedIndices = new uint256[](2);
        sortedIndices[0] = 1; // higher price first
        sortedIndices[1] = 0;

        vm.prank(SELLER);
        market.placeAsksAndClearMarket(correctHour, asks, sortedIndices);

        assertTrue(market.isMarketCleared(correctHour));
        assertEq(market.totalAsksByHour(correctHour), 2);
    }

    function test_placeAsksAndClearMarket_NotWhitelisted() public {
        market.placeBid{value: testPrice * 100}(correctHour, 100);

        vm.warp(clearHour);

        AskInput[] memory asks = new AskInput[](1);
        asks[0] = AskInput({receiver: RECEIVER1, amount: 100});

        uint256[] memory sortedIndices = new uint256[](1);
        sortedIndices[0] = 0;

        vm.prank(BIDDER);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__SellerIsNotWhitelisted.selector,
                BIDDER
            )
        );
        market.placeAsksAndClearMarket(correctHour, asks, sortedIndices);
    }

    function test_placeAsksAndClearMarket_HourNotPast() public {
        market.placeBid{value: testPrice * 100}(correctHour, 100);

        AskInput[] memory asks = new AskInput[](1);
        asks[0] = AskInput({receiver: RECEIVER1, amount: 100});

        uint256[] memory sortedIndices = new uint256[](1);
        sortedIndices[0] = 0;

        vm.prank(SELLER);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__HourNotInPast.selector,
                correctHour
            )
        );
        market.placeAsksAndClearMarket(correctHour, asks, sortedIndices);
    }

    function test_placeAsksAndClearMarket_NoBids() public {
        vm.warp(clearHour);

        AskInput[] memory asks = new AskInput[](1);
        asks[0] = AskInput({receiver: RECEIVER1, amount: 100});

        uint256[] memory sortedIndices = new uint256[](0);

        vm.prank(SELLER);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__NoBidsOrAsksForThisHour.selector,
                correctHour
            )
        );
        market.placeAsksAndClearMarket(correctHour, asks, sortedIndices);
    }

    function test_placeAsksAndClearMarket_InvalidReceiver() public {
        market.placeBid{value: testPrice * 100}(correctHour, 100);

        vm.warp(clearHour);

        AskInput[] memory asks = new AskInput[](1);
        asks[0] = AskInput({receiver: address(0), amount: 100});

        uint256[] memory sortedIndices = new uint256[](1);
        sortedIndices[0] = 0;

        vm.prank(SELLER);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__InvalidSellerAddress.selector
            )
        );
        market.placeAsksAndClearMarket(correctHour, asks, sortedIndices);
    }

    function test_placeAsksAndClearMarket_ZeroAmount() public {
        market.placeBid{value: testPrice * 100}(correctHour, 100);

        vm.warp(clearHour);

        AskInput[] memory asks = new AskInput[](1);
        asks[0] = AskInput({receiver: RECEIVER1, amount: 0});

        uint256[] memory sortedIndices = new uint256[](1);
        sortedIndices[0] = 0;

        vm.prank(SELLER);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__AmountCannotBeZero.selector
            )
        );
        market.placeAsksAndClearMarket(correctHour, asks, sortedIndices);
    }

    function test_placeAsksAndClearMarket_MultipleReceivers() public {
        market.placeBid{value: testPrice * 300}(correctHour, 300);

        vm.warp(clearHour);

        AskInput[] memory asks = new AskInput[](3);
        asks[0] = AskInput({receiver: RECEIVER1, amount: 100});
        asks[1] = AskInput({receiver: RECEIVER2, amount: 100});
        asks[2] = AskInput({receiver: makeAddr("receiver3"), amount: 100});

        uint256[] memory sortedIndices = new uint256[](1);
        sortedIndices[0] = 0;

        vm.prank(SELLER);
        market.placeAsksAndClearMarket(correctHour, asks, sortedIndices);

        assertTrue(market.isMarketCleared(correctHour));
        assertEq(market.totalAsksByHour(correctHour), 3);
    }
}
