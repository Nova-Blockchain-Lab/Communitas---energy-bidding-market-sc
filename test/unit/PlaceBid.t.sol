// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {
    EnergyBiddingMarket__WrongHourProvided,
    EnergyBiddingMarket__BidMinimumPriceNotMet,
    EnergyBiddingMarket__AmountCannotBeZero
} from "../../src/types/MarketTypes.sol";

/// @title PlaceBidTest
/// @notice Unit tests for placeBid and placeMultipleBids functions
contract PlaceBidTest is BaseTest {
    // ============ Single Bid Tests ============

    function test_placeBid_Success() public {
        market.placeBid{value: minimumPrice * bidAmount}(correctHour, bidAmount);

        (
            address bidder,
            uint88 amount,
            bool settled,
            uint88 price,
            bool canceled
        ) = market.bidsByHour(correctHour, 0);

        assertEq(amount, bidAmount);
        assertEq(price, minimumPrice);
        assertEq(settled, false);
        assertEq(bidder, address(this));
        assertEq(canceled, false);
    }

    function test_placeBid_wrongHour() public {
        uint256 wrongHour = correctHour + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__WrongHourProvided.selector,
                wrongHour
            )
        );
        market.placeBid{value: minimumPrice * bidAmount}(wrongHour, 100);
    }

    function test_placeBid_hourInPast() public {
        uint256 wrongHour = correctHour - 3600;
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__WrongHourProvided.selector,
                wrongHour
            )
        );
        market.placeBid{value: minimumPrice * bidAmount}(wrongHour, 100);
    }

    function test_placeBid_lessThanMinimumPrice() public {
        uint256 wrongPrice = 100;
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__BidMinimumPriceNotMet.selector,
                wrongPrice,
                minimumPrice
            )
        );
        market.placeBid{value: wrongPrice * bidAmount}(correctHour, bidAmount);
    }

    function test_placeBid_amountZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__AmountCannotBeZero.selector
            )
        );
        market.placeBid{value: minimumPrice * bidAmount}(correctHour, 0);
    }

    // ============ Multiple Bids Tests ============

    function test_placeMultipleRangedBids_Success() public {
        uint256 beginHour = correctHour;
        uint256 endHour = correctHour + 7200;

        market.placeMultipleBids{value: minimumPrice * bidAmount * 2}(beginHour, endHour, bidAmount);

        for (uint256 hour = beginHour; hour < endHour; hour += 3600) {
            (
                address bidder,
                uint88 actualBidAmount,
                bool settled,
                uint88 bidPrice,
                bool canceled
            ) = market.bidsByHour(hour, 0);

            assertEq(actualBidAmount, bidAmount);
            assertEq(bidPrice, minimumPrice);
            assertEq(settled, false);
            assertEq(bidder, address(this));
            assertEq(canceled, false);
        }
    }

    function test_placeMultipleBids_Success() public {
        uint256[] memory biddingHours = new uint256[](2);
        biddingHours[0] = correctHour;
        biddingHours[1] = correctHour + 3600;

        market.placeMultipleBids{value: minimumPrice * bidAmount * 2}(biddingHours, bidAmount);

        for (uint256 i = 0; i < biddingHours.length; i++) {
            (
                address bidder,
                uint88 actualBidAmount,
                bool settled,
                uint88 bidPrice,
                bool canceled
            ) = market.bidsByHour(biddingHours[i], 0);

            assertEq(actualBidAmount, bidAmount);
            assertEq(bidPrice, minimumPrice);
            assertEq(settled, false);
            assertEq(bidder, address(this));
            assertEq(canceled, false);
        }
    }

    function test_placeMultipleBids_AmountZero() public {
        uint256[] memory biddingHours = new uint256[](2);
        biddingHours[0] = correctHour;
        biddingHours[1] = correctHour + 3600;

        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__AmountCannotBeZero.selector
            )
        );
        market.placeMultipleBids{value: minimumPrice * 2}(biddingHours, 0);
    }

    function test_placeMultipleBids_InvalidHours() public {
        uint256[] memory biddingHours = new uint256[](2);
        biddingHours[0] = correctHour;
        biddingHours[1] = correctHour + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__WrongHourProvided.selector,
                correctHour + 1
            )
        );
        market.placeMultipleBids{value: minimumPrice * bidAmount * 2}(biddingHours, bidAmount);
    }

    function test_placeMultipleBids_LessThanMinimumPrice() public {
        uint256[] memory biddingHours = new uint256[](2);
        biddingHours[0] = correctHour;
        biddingHours[1] = correctHour + 3600;

        uint256 wrongPrice = minimumPrice - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__BidMinimumPriceNotMet.selector,
                wrongPrice,
                minimumPrice
            )
        );
        market.placeMultipleBids{value: wrongPrice * bidAmount * 2}(biddingHours, bidAmount);
    }

    // ============ Residual Tests ============

    function test_PlaceBidResiduals() public {
        uint256 currentHour = (block.timestamp / 3600) * 3600;
        uint256 hour = currentHour + 3600;

        uint256 energyAmount = 1779;
        uint256 ethAmount = 9999999000000022007;

        uint256 expectedPrice = ethAmount / energyAmount;

        vm.deal(BIDDER, ethAmount);
        vm.prank(BIDDER);
        market.placeBid{value: ethAmount}(hour, energyAmount);

        (, , , uint88 actualPrice,) = market.bidsByHour(hour, 0);

        assertEq(actualPrice, expectedPrice);

        uint256 expectedResidual = ethAmount - (expectedPrice * energyAmount);
        assertGt(expectedResidual, 0);

        assertEq(address(market).balance, ethAmount - expectedResidual);
    }

    function test_PlaceMultipleBidsResiduals() public {
        uint256 numHours = 18;
        uint256 energyAmount = 9;
        uint256 ethAmount = 9999838000000018636;

        uint256 currentHour = (block.timestamp / 3600) * 3600;
        uint256 beginHour = currentHour + 3600;
        uint256 endHour = beginHour + (numHours * 3600);

        vm.deal(BIDDER, ethAmount);
        vm.startPrank(BIDDER);
        market.placeMultipleBids{value: ethAmount}(beginHour, endHour, energyAmount);
        vm.stopPrank();

        uint256 totalUsed;
        for (uint256 hour = beginHour; hour < endHour; hour += 3600) {
            (, uint88 amount, , uint88 price,) = market.bidsByHour(hour, 0);
            totalUsed += uint256(amount) * uint256(price);
        }

        assertEq(address(market).balance, totalUsed);
        assertGt(ethAmount - totalUsed, 0);
    }

    function test_ArrayBulkBidResiduals() public {
        uint256[] memory hoursArray = new uint256[](17);
        uint256 currentHour = (block.timestamp / 3600) * 3600;
        for (uint256 i = 0; i < 17; i++) {
            hoursArray[i] = currentHour + 3600 * (i + 1);
        }

        uint256 energyAmount = 13;
        uint256 ethAmount = 9999999000000022007;

        vm.deal(BIDDER, ethAmount);
        vm.prank(BIDDER);
        market.placeMultipleBids{value: ethAmount}(hoursArray, energyAmount);

        uint256 totalUsed;
        for (uint256 i = 0; i < hoursArray.length; i++) {
            (, uint88 amount, , uint88 price,) = market.bidsByHour(hoursArray[i], 0);
            totalUsed += uint256(amount) * uint256(price);
        }

        assertGt(ethAmount - totalUsed, 0);
        assertEq(address(market).balance, totalUsed);
    }
}
