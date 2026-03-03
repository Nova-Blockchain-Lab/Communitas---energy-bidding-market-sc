// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {AskInput} from "../../src/types/MarketTypes.sol";

/// @title Full Market Cycle Integration Tests
/// @notice End-to-end tests for complete market cycles
contract FullMarketCycleTest is BaseTest {
    function test_fullCycle_SingleBidderSingleSeller() public {
        // 1. Bidder places bid
        uint256 bidAmount = 100;
        uint256 bidPrice = testPrice * 2;
        market.placeBid{value: bidPrice * bidAmount}(correctHour, bidAmount);

        // 2. Seller places ask
        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(bidAmount, RECEIVER1);

        // 3. Market clears
        vm.warp(clearHour);
        market.clearMarket(correctHour);

        // 4. Verify outcomes
        assertTrue(market.isMarketCleared(correctHour));
        uint256 clearingPrice = market.clearingPricePerHour(correctHour);
        assertEq(clearingPrice, bidPrice);

        // 5. Check claimable balances
        // Bidder gets refund of (bid price - clearing price) * amount = 0
        assertEq(market.claimableBalance(address(this)), 0);
        // Seller receives clearing price * amount
        assertEq(market.claimableBalance(RECEIVER1), clearingPrice * bidAmount);
    }

    function test_fullCycle_MultipleBiddersPartialFill() public {
        // 1. Multiple bidders place bids
        vm.prank(BIDDER);
        market.placeBid{value: testPrice * 3 * 50}(correctHour, 50); // High price, 50 Watts

        market.placeBid{value: testPrice * 2 * 75}(correctHour, 75); // Medium price, 75 Watts

        address bidder3 = makeAddr("bidder3");
        vm.deal(bidder3, 1 ether);
        vm.prank(bidder3);
        market.placeBid{value: testPrice * 100}(correctHour, 100); // Low price, 100 Watts

        // 2. Seller places limited ask (only 100 Watts available)
        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        // 3. Clear market
        vm.warp(clearHour);
        market.clearMarket(correctHour);

        // 4. Verify clearing price (marginal bid price)
        uint256 clearingPrice = market.clearingPricePerHour(correctHour);
        assertEq(clearingPrice, testPrice * 2);

        // 5. Bidder 1 (50 Watts at 3x) gets: refund of (3x - 2x) * 50 = 1x * 50
        assertEq(market.claimableBalance(BIDDER), testPrice * 50);

        // 6. Bidder 2 (75 Watts at 2x) gets partial fill: 50 Watts matched
        // Refund: unfilled 25 Watts * 2x + filled 50 Watts * (2x - 2x) = 50 * testPrice
        assertEq(market.claimableBalance(address(this)), testPrice * 2 * 25);
    }

    function test_fullCycle_MoreSupplyThanDemand() public {
        // 1. Place single bid
        market.placeBid{value: testPrice * 50}(correctHour, 50);

        // 2. Place more supply than demand
        vm.warp(askHour);
        vm.startPrank(SELLER);
        market.placeAsk(100, RECEIVER1);
        market.placeAsk(100, RECEIVER2);
        vm.stopPrank();

        // 3. Clear market
        vm.warp(clearHour);
        market.clearMarket(correctHour);

        // 4. Verify clearing price
        uint256 clearingPrice = market.clearingPricePerHour(correctHour);
        assertEq(clearingPrice, testPrice);

        // 5. Only 50 Watts should be matched
        assertEq(market.claimableBalance(RECEIVER1), testPrice * 50);
        assertEq(market.claimableBalance(RECEIVER2), 0); // Second ask not matched
    }

    function test_fullCycle_MultipleSellers() public {
        // Whitelist second seller
        market.whitelistSeller(BIDDER, true);

        // 1. Place bid
        address bidder = makeAddr("mainBidder");
        vm.deal(bidder, 1 ether);
        vm.prank(bidder);
        market.placeBid{value: testPrice * 150}(correctHour, 150);

        // 2. Multiple sellers place asks
        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(80, RECEIVER1);

        vm.prank(BIDDER);
        market.placeAsk(100, RECEIVER2);

        // 3. Clear market
        vm.warp(clearHour);
        market.clearMarket(correctHour);

        // 4. Verify both sellers receive payments
        assertEq(market.claimableBalance(RECEIVER1), testPrice * 80);
        assertEq(market.claimableBalance(RECEIVER2), testPrice * 70); // Only 70 matched
    }

    function test_fullCycle_WithCanceledBids() public {
        // 1. Place multiple bids
        market.placeBid{value: testPrice * 3 * 100}(correctHour, 100); // index 0
        market.placeBid{value: testPrice * 2 * 100}(correctHour, 100); // index 1

        // 2. Cancel the higher bid
        market.cancelBid(correctHour, 0);

        // 3. Place ask
        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        // 4. Clear market with sorted indices (excluding canceled)
        vm.warp(clearHour);

        uint256[] memory sortedIndices = new uint256[](1);
        sortedIndices[0] = 1; // Only include non-canceled bid

        market.clearMarketWithSortedBids(correctHour, sortedIndices);

        // 5. Clearing price based on remaining bid
        assertEq(market.clearingPricePerHour(correctHour), testPrice * 2);
    }

    function test_fullCycle_ClaimBalance() public {
        // 1. Setup and clear market
        market.placeBid{value: testPrice * 2 * 100}(correctHour, 100);

        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        vm.warp(clearHour);
        market.clearMarket(correctHour);

        // 2. Get claimable balance
        uint256 claimable = market.claimableBalance(RECEIVER1);
        assertGt(claimable, 0);

        // 3. Claim balance
        uint256 balanceBefore = RECEIVER1.balance;
        vm.prank(RECEIVER1);
        market.claimBalance();
        uint256 balanceAfter = RECEIVER1.balance;

        // 4. Verify claim
        assertEq(balanceAfter - balanceBefore, claimable);
        assertEq(market.claimableBalance(RECEIVER1), 0);
    }

    function test_fullCycle_BatchAsksAndClear() public {
        // 1. Place bids
        market.placeBid{value: testPrice * 2 * 100}(correctHour, 100);
        market.placeBid{value: testPrice * 50}(correctHour, 50);

        vm.warp(clearHour);

        // 2. Prepare batch asks with sorted indices
        AskInput[] memory asks = new AskInput[](2);
        asks[0] = AskInput({receiver: RECEIVER1, amount: 80});
        asks[1] = AskInput({receiver: RECEIVER2, amount: 70});

        uint256[] memory sortedIndices = new uint256[](2);
        sortedIndices[0] = 0; // Higher price first
        sortedIndices[1] = 1;

        // 3. Place asks and clear in one transaction
        vm.prank(SELLER);
        market.placeAsksAndClearMarket(correctHour, asks, sortedIndices);

        // 4. Verify market cleared
        assertTrue(market.isMarketCleared(correctHour));
    }

    function test_fullCycle_MultipleHours() public {
        // Test that different hours are independent

        // Hour 1
        market.placeBid{value: testPrice * 100}(correctHour, 100);
        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        // Hour 2 (next hour)
        uint256 hour2 = correctHour + 3600;
        market.placeBid{value: testPrice * 2 * 50}(hour2, 50);
        vm.warp(askHour + 3600);
        vm.prank(SELLER);
        market.placeAsk(50, RECEIVER2);

        // Clear both hours
        vm.warp(clearHour + 3600);
        market.clearMarket(correctHour);
        market.clearMarket(hour2);

        // Verify independent clearing prices
        assertEq(market.clearingPricePerHour(correctHour), testPrice);
        assertEq(market.clearingPricePerHour(hour2), testPrice * 2);
    }
}
