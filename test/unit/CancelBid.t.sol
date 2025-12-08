// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {
    EnergyBiddingMarket__BidIsAlreadyCanceled,
    EnergyBiddingMarket__OnlyBidOwnerCanCancel,
    EnergyBiddingMarket__MarketAlreadyClearedForThisHour,
    EnergyBiddingMarket__BidDoesNotExist
} from "../../src/types/MarketTypes.sol";

/// @title CancelBid Unit Tests
/// @notice Tests for the cancelBid functionality
contract CancelBidTest is BaseTest {
    function test_cancelBid_Success() public {
        uint256 bidAmount = 100;
        uint256 totalValue = minimumPrice * bidAmount;

        // Fund this contract
        vm.deal(address(this), totalValue * 2);

        market.placeBid{value: totalValue}(correctHour, bidAmount);

        market.cancelBid(correctHour, 0);

        // Check bid is canceled
        (, , , , bool canceled) = market.bidsByHour(correctHour, 0);
        assertTrue(canceled);

        // Refund goes to claimableBalance, not direct transfer
        assertEq(market.claimableBalance(address(this)), totalValue);

        // Claim the balance
        uint256 balanceBefore = address(this).balance;
        market.claimBalance();
        uint256 balanceAfter = address(this).balance;
        assertEq(balanceAfter - balanceBefore, totalValue);
    }

    // Required for receiving refunds
    receive() external payable {}

    function test_cancelBid_NotOwner() public {
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);

        vm.prank(BIDDER);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__OnlyBidOwnerCanCancel.selector,
                correctHour,
                BIDDER
            )
        );
        market.cancelBid(correctHour, 0);
    }

    function test_cancelBid_AlreadyCanceled() public {
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);
        market.cancelBid(correctHour, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__BidIsAlreadyCanceled.selector,
                correctHour,
                0
            )
        );
        market.cancelBid(correctHour, 0);
    }

    function test_cancelBid_MarketCleared() public {
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);

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
        market.cancelBid(correctHour, 0);
    }

    function test_cancelBid_DoesNotExist() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__BidDoesNotExist.selector,
                correctHour,
                0
            )
        );
        market.cancelBid(correctHour, 0);
    }

    function test_cancelBid_MultipleBids() public {
        // Place 3 bids
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);
        market.placeBid{value: minimumPrice * 200}(correctHour, 200);
        market.placeBid{value: minimumPrice * 300}(correctHour, 300);

        // Cancel the middle one
        market.cancelBid(correctHour, 1);

        // Check states
        (, , , , bool canceled0) = market.bidsByHour(correctHour, 0);
        (, , , , bool canceled1) = market.bidsByHour(correctHour, 1);
        (, , , , bool canceled2) = market.bidsByHour(correctHour, 2);

        assertFalse(canceled0);
        assertTrue(canceled1);
        assertFalse(canceled2);
    }

    function test_cancelBid_ExcludedFromClearing() public {
        // Place 2 bids
        market.placeBid{value: minimumPrice * 2 * 100}(correctHour, 100); // Higher price
        market.placeBid{value: minimumPrice * 50}(correctHour, 50); // Lower price

        // Cancel the higher price bid
        market.cancelBid(correctHour, 0);

        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        vm.warp(clearHour);
        market.clearMarket(correctHour);

        // Clearing price should be based on the remaining bid
        uint256 clearingPrice = market.clearingPricePerHour(correctHour);
        assertEq(clearingPrice, minimumPrice);
    }
}
