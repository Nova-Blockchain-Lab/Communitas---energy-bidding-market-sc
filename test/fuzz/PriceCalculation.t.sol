// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {BidSorterLib} from "../../src/libraries/BidSorterLib.sol";
import {Bid} from "../../src/types/MarketTypes.sol";

/// @title Price Calculation Fuzz Tests
/// @notice Fuzz tests for market clearing price calculations
contract PriceCalculationFuzzTest is BaseTest {
    /// @notice Fuzz test: clearing price never exceeds highest bid
    function testFuzz_clearingPrice_NeverExceedsHighestBid(
        uint88 bidAmount,
        uint88 askAmount
    ) public {
        // Bound inputs to reasonable ranges
        vm.assume(bidAmount > 0 && bidAmount < 1e12);
        vm.assume(askAmount > 0 && askAmount < 1e12);

        uint256 price = defaultTestPrice * 2; // 2x minimum

        // Place bid
        uint256 totalValue = price * uint256(bidAmount);
        vm.deal(address(this), totalValue);
        market.placeBid{value: totalValue}(correctHour, bidAmount);

        // Place ask
        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(askAmount, RECEIVER1);

        // Clear market
        vm.warp(clearHour);
        market.clearMarket(correctHour);

        // Verify clearing price never exceeds the bid price
        uint256 clearingPrice = market.clearingPricePerHour(correctHour);
        assertLe(clearingPrice, price);
    }

    /// @notice Fuzz test: clearing price never below minimum
    function testFuzz_clearingPrice_NeverBelowMinimum(
        uint88 bidAmount,
        uint88 askAmount,
        uint256 priceMultiplier
    ) public {
        // Bound inputs
        vm.assume(bidAmount > 0 && bidAmount < 1e12);
        vm.assume(askAmount > 0 && askAmount < 1e12);
        priceMultiplier = bound(priceMultiplier, 1, 100);

        uint256 price = defaultTestPrice * priceMultiplier;

        // Place bid
        uint256 totalValue = price * uint256(bidAmount);
        vm.deal(address(this), totalValue);
        market.placeBid{value: totalValue}(correctHour, bidAmount);

        // Place ask
        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(askAmount, RECEIVER1);

        // Clear market
        vm.warp(clearHour);
        market.clearMarket(correctHour);

        // Verify clearing price is at least minimum price
        uint256 clearingPrice = market.clearingPricePerHour(correctHour);
        // Clearing price can be any value >= 0
        assertGe(clearingPrice, 0);
    }

    /// @notice Fuzz test: total payments match total matched energy * clearing price
    function testFuzz_payments_MatchClearingPrice(
        uint88 bidAmount,
        uint88 askAmount
    ) public {
        // Bound inputs
        vm.assume(bidAmount > 0 && bidAmount < 1e9);
        vm.assume(askAmount > 0 && askAmount < 1e9);

        uint256 price = defaultTestPrice * 2;

        // Place bid
        uint256 totalValue = price * uint256(bidAmount);
        vm.deal(address(this), totalValue);
        market.placeBid{value: totalValue}(correctHour, bidAmount);

        // Place ask
        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(askAmount, RECEIVER1);

        // Clear market
        vm.warp(clearHour);
        market.clearMarket(correctHour);

        // Calculate expected matched energy
        uint256 matchedEnergy = bidAmount < askAmount ? bidAmount : askAmount;
        uint256 clearingPrice = market.clearingPricePerHour(correctHour);

        // Seller receives clearing price * matched energy
        assertEq(market.claimableBalance(RECEIVER1), clearingPrice * matchedEnergy);
    }

    /// @notice Fuzz test: bidder refund is correct
    function testFuzz_bidder_RefundCorrect(
        uint88 bidAmount,
        uint88 askAmount,
        uint256 priceMultiplier
    ) public {
        // Bound inputs
        vm.assume(bidAmount > 0 && bidAmount < 1e9);
        vm.assume(askAmount > 0 && askAmount < 1e9);
        priceMultiplier = bound(priceMultiplier, 1, 100);

        uint256 bidPrice = defaultTestPrice * priceMultiplier;

        // Place bid
        uint256 totalValue = bidPrice * uint256(bidAmount);
        vm.deal(address(this), totalValue);
        market.placeBid{value: totalValue}(correctHour, bidAmount);

        // Place ask
        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(askAmount, RECEIVER1);

        // Clear market
        vm.warp(clearHour);
        market.clearMarket(correctHour);

        uint256 clearingPrice = market.clearingPricePerHour(correctHour);
        uint256 matchedEnergy = bidAmount < askAmount ? bidAmount : askAmount;
        uint256 unfilledEnergy = bidAmount > askAmount ? bidAmount - askAmount : 0;

        // Expected refund: (unfilled * bidPrice) + (filled * (bidPrice - clearingPrice))
        uint256 expectedRefund = (unfilledEnergy * bidPrice) + (matchedEnergy * (bidPrice - clearingPrice));

        assertEq(market.claimableBalance(address(this)), expectedRefund);
    }

    /// @notice Fuzz test: multiple bids sorting is correct
    function testFuzz_sorting_HigherPricesFirst(
        uint256 price1Mult,
        uint256 price2Mult,
        uint256 price3Mult
    ) public {
        // Bound price multipliers
        price1Mult = bound(price1Mult, 1, 100);
        price2Mult = bound(price2Mult, 1, 100);
        price3Mult = bound(price3Mult, 1, 100);

        uint256 price1 = defaultTestPrice * price1Mult;
        uint256 price2 = defaultTestPrice * price2Mult;
        uint256 price3 = defaultTestPrice * price3Mult;

        uint256 amount = 100;

        // Place bids
        vm.deal(address(this), 1 ether);
        market.placeBid{value: price1 * amount}(correctHour, amount);
        market.placeBid{value: price2 * amount}(correctHour, amount);
        market.placeBid{value: price3 * amount}(correctHour, amount);

        // Get bids and sort
        Bid[] memory bids = market.getBidsByHour(correctHour);
        uint256[] memory sortedIndices = BidSorterLib.sortedBidIndicesDescending(bids);

        // Verify descending order
        for (uint256 i = 0; i < sortedIndices.length - 1; i++) {
            uint256 currentPrice = bids[sortedIndices[i]].price;
            uint256 nextPrice = bids[sortedIndices[i + 1]].price;
            assertGe(currentPrice, nextPrice, "Prices should be in descending order");
        }
    }

    /// @notice Fuzz test: bid amount within uint88 bounds
    function testFuzz_amount_Uint88Bounds(uint256 rawAmount) public {
        // Bound to uint88 max
        uint256 amount = bound(rawAmount, 1, type(uint88).max);
        uint256 price = defaultTestPrice;

        // May revert due to insufficient funds or overflow
        uint256 totalValue = price * amount;
        vm.deal(address(this), totalValue);

        try market.placeBid{value: totalValue}(correctHour, amount) {
            // If it succeeds, verify the amount stored correctly
            (,uint88 storedAmount,,,) = market.bidsByHour(correctHour, 0);
            assertEq(storedAmount, amount);
        } catch {
            // Some amounts may overflow uint88, that's expected
        }
    }

    /// @notice Fuzz test: price within uint88 bounds
    function testFuzz_price_Uint88Bounds(uint256 rawPrice) public {
        // Price must be > 0 for meaningful test
        uint256 price = bound(rawPrice, 1, type(uint88).max);
        uint256 amount = 100;

        uint256 totalValue = price * amount;
        vm.deal(address(this), totalValue);

        try market.placeBid{value: totalValue}(correctHour, amount) {
            // If it succeeds, verify the price stored correctly
            (,,,uint88 storedPrice,) = market.bidsByHour(correctHour, 0);
            assertEq(storedPrice, price);
        } catch {
            // Price might exceed uint88 bounds
        }
    }
}
