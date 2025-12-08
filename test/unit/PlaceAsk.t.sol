// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {
    EnergyBiddingMarket__SellerIsNotWhitelisted,
    EnergyBiddingMarket__InvalidSellerAddress,
    EnergyBiddingMarket__AmountCannotBeZero
} from "../../src/types/MarketTypes.sol";

/// @title PlaceAsk Unit Tests
/// @notice Tests for the placeAsk functionality
contract PlaceAskTest is BaseTest {
    function test_placeAsk_Success() public {
        vm.warp(askHour);
        uint256 askAmount = 100;

        vm.prank(SELLER);
        market.placeAsk(askAmount, RECEIVER1);

        (
            address seller,
            uint88 amount,
            bool settled,
            uint88 matchedAmount
        ) = market.asksByHour(correctHour, 0);

        assertEq(amount, askAmount);
        assertEq(settled, false);
        assertEq(seller, RECEIVER1);
        assertEq(matchedAmount, 0);
    }

    function test_placeAsk_NotWhitelisted() public {
        vm.warp(askHour);

        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__SellerIsNotWhitelisted.selector,
                BIDDER
            )
        );
        vm.prank(BIDDER);
        market.placeAsk(100, BIDDER);
    }

    function test_placeAsk_InvalidReceiver() public {
        vm.warp(askHour);

        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__InvalidSellerAddress.selector
            )
        );
        vm.prank(SELLER);
        market.placeAsk(100, address(0));
    }

    function test_placeAsk_ZeroAmount() public {
        vm.warp(askHour);

        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__AmountCannotBeZero.selector
            )
        );
        vm.prank(SELLER);
        market.placeAsk(0, RECEIVER1);
    }

    function test_placeAsk_MultipleAsks() public {
        vm.warp(askHour);

        vm.startPrank(SELLER);
        market.placeAsk(100, RECEIVER1);
        market.placeAsk(200, RECEIVER2);
        market.placeAsk(300, RECEIVER1);
        vm.stopPrank();

        assertEq(market.totalAsksByHour(correctHour), 3);
    }

    function test_placeAsk_MultipleSellers() public {
        vm.warp(askHour);

        // Whitelist second seller
        market.whitelistSeller(BIDDER, true);

        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        vm.prank(BIDDER);
        market.placeAsk(200, RECEIVER2);

        assertEq(market.totalAsksByHour(correctHour), 2);
    }

    function test_getAsksByHour() public {
        vm.warp(askHour);

        vm.startPrank(SELLER);
        market.placeAsk(100, RECEIVER1);
        market.placeAsk(200, RECEIVER2);
        vm.stopPrank();

        // Note: This test would require getAsksByHour view function
        // Currently we verify via totalAsksByHour
        assertEq(market.totalAsksByHour(correctHour), 2);
    }

    function test_getAsksByAddress() public {
        vm.warp(askHour);

        vm.startPrank(SELLER);
        market.placeAsk(100, RECEIVER1);
        market.placeAsk(200, RECEIVER1);
        market.placeAsk(300, RECEIVER2);
        vm.stopPrank();

        // Note: This test would require getAsksByAddress view function
        // Currently verifying the asks were placed correctly
        assertEq(market.totalAsksByHour(correctHour), 3);
    }
}
