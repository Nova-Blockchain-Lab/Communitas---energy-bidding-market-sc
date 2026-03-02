// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {EnergyBiddingMarket} from "../src/EnergyBiddingMarket.sol";
import {BidSorterLib} from "../src/libraries/BidSorterLib.sol";
import {
    Bid,
    Ask,
    AskInput,
    EnergyBiddingMarket__WrongHourProvided,
    EnergyBiddingMarket__BidMinimumPriceNotMet,
    EnergyBiddingMarket__AmountCannotBeZero,
    EnergyBiddingMarket__NoClaimableBalance,
    EnergyBiddingMarket__BidIsAlreadyCanceled,
    EnergyBiddingMarket__MarketAlreadyClearedForThisHour,
    EnergyBiddingMarket__OnlyBidOwnerCanCancel,
    EnergyBiddingMarket__NoBidsOrAsksForThisHour,
    EnergyBiddingMarket__SellerIsNotWhitelisted,
    EnergyBiddingMarket__InvalidSellerAddress,
    EnergyBiddingMarket__HourNotInPast,
    EnergyBiddingMarket__BidDoesNotExist,
    EnergyBiddingMarket__InvalidSortOrder,
    EnergyBiddingMarket__EmptyAsksArray
} from "../src/types/MarketTypes.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {DeployerEnergyBiddingMarket} from "../script/Deploy.s.sol";

contract EnergyBiddingMarketTest is Test {
    address BIDDER = makeAddr("bidder");
    address ASKER = makeAddr("asker");
    address SELLER = makeAddr("seller");
    address RECEIVER1 = makeAddr("receiver1");
    address RECEIVER2 = makeAddr("receiver2");
    address OWNER;

    EnergyBiddingMarket market;
    uint256 correctHour;
    uint256 askHour;
    uint256 clearHour;
    uint256 minimumPrice;
    uint256 bidAmount;

    function setUp() public {
        DeployerEnergyBiddingMarket deployer = new DeployerEnergyBiddingMarket();
        market = deployer.run();

        OWNER = address(this);

        correctHour = (block.timestamp / 3600) * 3600 + 3600;
        askHour = correctHour + 1;
        clearHour = askHour + 3600;
        minimumPrice = market.MIN_PRICE();
        bidAmount = 100;

        vm.deal(address(0xBEEF), 1000 ether);
        vm.deal(BIDDER, 100 ether);
        vm.deal(ASKER, 100 ether);
        vm.deal(SELLER, 100 ether);

        // Whitelist the seller for tests
        market.whitelistSeller(SELLER, true);
    }

    // ============ Bid Tests ============

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

    // ============ Ask Tests (Whitelist Required) ============

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
                address(this)
            )
        );
        market.placeAsk(100, RECEIVER1);
    }

    function test_placeAsk_AmountZero() public {
        vm.warp(askHour);

        vm.prank(SELLER);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__AmountCannotBeZero.selector
            )
        );
        market.placeAsk(0, RECEIVER1);
    }

    function test_placeAsk_InvalidReceiver() public {
        vm.warp(askHour);

        vm.prank(SELLER);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__InvalidSellerAddress.selector
            )
        );
        market.placeAsk(100, address(0));
    }

    // ============ Off-chain Sorting Tests ============

    function test_clearMarketWithSortedBids_Success() public {
        // Place bids with different prices
        vm.prank(BIDDER);
        market.placeBid{value: minimumPrice * 100}(correctHour, 100); // index 0, price = minimumPrice
        market.placeBid{value: minimumPrice * 2 * 50}(correctHour, 50);  // index 1, price = minimumPrice * 2
        market.placeBid{value: minimumPrice * 3 * 30}(correctHour, 30);  // index 2, price = minimumPrice * 3

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
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);
        market.placeBid{value: minimumPrice * 2 * 50}(correctHour, 50);

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
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);
        market.placeBid{value: minimumPrice * 50}(correctHour, 50);
        market.placeBid{value: minimumPrice * 30}(correctHour, 30);

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

    function test_clearMarketWithSortedBids_GasSavings() public {
        // Place many bids to demonstrate gas savings
        for (uint256 i = 0; i < 20; i++) {
            market.placeBid{value: (minimumPrice + i) * 10}(correctHour, 10);
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

    // ============ Batch Ask and Clear Market Tests ============

    function test_placeAsksAndClearMarket_Success() public {
        // Place bids first
        market.placeBid{value: minimumPrice * 200}(correctHour, 200);

        // Warp to after the hour
        vm.warp(clearHour);

        // Create batch asks
        AskInput[] memory asks = new AskInput[](2);
        asks[0] = AskInput({receiver: RECEIVER1, amount: 100});
        asks[1] = AskInput({receiver: RECEIVER2, amount: 50});

        // Get sorted indices
        uint256[] memory sortedIndices = new uint256[](1);
        sortedIndices[0] = 0;

        vm.prank(SELLER);
        market.placeAsksAndClearMarket(correctHour, asks, sortedIndices);

        // Check market is cleared
        assertTrue(market.isMarketCleared(correctHour));

        // Check asks were placed
        assertEq(market.totalAsksByHour(correctHour), 2);

        // Check receivers have claimable balances
        assertTrue(market.claimableBalance(RECEIVER1) > 0);
        assertTrue(market.claimableBalance(RECEIVER2) > 0);
    }

    function test_placeAsksAndClearMarket_NotWhitelisted() public {
        vm.warp(clearHour);

        AskInput[] memory asks = new AskInput[](1);
        asks[0] = AskInput({receiver: RECEIVER1, amount: 100});

        uint256[] memory sortedIndices = new uint256[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__SellerIsNotWhitelisted.selector,
                address(this)
            )
        );
        market.placeAsksAndClearMarket(correctHour, asks, sortedIndices);
    }

    function test_placeAsksAndClearMarket_HourNotInPast() public {
        AskInput[] memory asks = new AskInput[](1);
        asks[0] = AskInput({receiver: RECEIVER1, amount: 100});

        uint256[] memory sortedIndices = new uint256[](0);

        vm.prank(SELLER);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__HourNotInPast.selector,
                correctHour
            )
        );
        market.placeAsksAndClearMarket(correctHour, asks, sortedIndices);
    }

    function test_placeAsksAndClearMarket_EmptyArray() public {
        vm.warp(clearHour);

        AskInput[] memory asks = new AskInput[](0);
        uint256[] memory sortedIndices = new uint256[](0);

        vm.prank(SELLER);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__EmptyAsksArray.selector
            )
        );
        market.placeAsksAndClearMarket(correctHour, asks, sortedIndices);
    }

    function test_placeAsksAndClearMarket_InvalidReceiver() public {
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);
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
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);
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

    // ============ Whitelist Tests ============

    function test_whitelistSeller_Success() public {
        address newSeller = makeAddr("newSeller");

        assertFalse(market.isSellerWhitelisted(newSeller));

        market.whitelistSeller(newSeller, true);
        assertTrue(market.isSellerWhitelisted(newSeller));

        market.whitelistSeller(newSeller, false);
        assertFalse(market.isSellerWhitelisted(newSeller));
    }

    function test_whitelistSeller_OnlyOwner() public {
        address newSeller = makeAddr("newSeller");

        vm.prank(BIDDER);
        vm.expectRevert();
        market.whitelistSeller(newSeller, true);
    }

    function test_whitelistSeller_InvalidAddress() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__InvalidSellerAddress.selector
            )
        );
        market.whitelistSeller(address(0), true);
    }

    // ============ Claim Balance Tests ============

    function test_claimBalance_NoBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__NoClaimableBalance.selector,
                address(this)
            )
        );
        market.claimBalance();
    }

    // ============ Clear Market Tests ============

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

    function test_clearMarket_NoBids() public {
        vm.warp(askHour);
        uint256 amount = 1000;

        vm.prank(SELLER);
        market.placeAsk(amount, RECEIVER1);

        vm.warp(clearHour);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__NoBidsOrAsksForThisHour.selector,
                correctHour
            )
        );
        market.clearMarket(correctHour);
    }

    function test_clearMarket_NoAsks() public {
        uint256 amount = 1000;
        market.placeBid{value: minimumPrice * amount}(correctHour, amount);

        vm.warp(clearHour);
        market.clearMarket(correctHour);
        assertEq(market.balanceOf(address(this)), minimumPrice * amount);
    }

    function test_clearMarket_bigAskSmallBids() public {
        uint256 smallBidAmount = 100;
        uint256 bidPrice = market.MIN_PRICE();

        for (uint256 i = 0; i < 50; i++) {
            market.placeBid{value: bidPrice * smallBidAmount}(correctHour, smallBidAmount);
        }

        vm.warp(askHour);
        uint256 bigAskAmount = 10000;

        vm.prank(SELLER);
        market.placeAsk(bigAskAmount, RECEIVER1);

        vm.warp(clearHour);
        market.clearMarket(correctHour);

        uint256 expectedMatchedAmount = 5000;

        (, , bool settled, uint88 matchedAmount) = market.asksByHour(correctHour, 0);
        assertEq(settled, false);
        assertEq(matchedAmount, expectedMatchedAmount);

        for (uint256 i = 0; i < 50; i++) {
            (, , bool bidSettled, ,) = market.bidsByHour(correctHour, i);
            assertEq(bidSettled, true);
        }
    }

    function test_clearMarket_smallBidSmallAsks() public {
        uint256 bigBidAmount = 1000;
        uint256 bidPrice = market.MIN_PRICE();
        market.placeBid{value: bidPrice * bigBidAmount}(correctHour, bigBidAmount);

        vm.warp(askHour);
        uint256 smallAskAmount = 100;

        vm.startPrank(SELLER);
        for (uint256 i = 0; i < 50; i++) {
            market.placeAsk(smallAskAmount, RECEIVER1);
        }
        vm.stopPrank();

        vm.warp(clearHour);
        market.clearMarket(correctHour);

        (, , bool bidSettled, ,) = market.bidsByHour(correctHour, 0);
        assertEq(bidSettled, true);

        for (uint256 i = 0; i < 10; i++) {
            (, , bool askSettled, uint88 amountMatched) = market.asksByHour(correctHour, i);
            assertEq(askSettled, true);
            assertEq(amountMatched, smallAskAmount);
        }

        for (uint256 i = 10; i < 50; i++) {
            (, , bool askSettled, uint88 amountMatched) = market.asksByHour(correctHour, i);
            assertEq(askSettled, false);
            assertEq(amountMatched, 0);
        }
    }

    function test_clearMarket_randomBidsAndAsks() public {
        uint256 loops = 100;
        uint256 totalBidAmount = 0;
        uint256 bidPrice = market.MIN_PRICE();
        uint256 smallAskAmount = 10;
        uint256 smallBidAmount = 20;

        for (uint256 i = 0; i < loops; i++) {
            uint256 randomBidAmount = smallBidAmount + (i * 2);
            market.placeBid{value: (bidPrice + i) * randomBidAmount}(correctHour, randomBidAmount);
            totalBidAmount += randomBidAmount;
        }

        vm.warp(askHour);
        vm.startPrank(SELLER);
        for (uint256 i = 0; i < loops; i++) {
            uint256 randomAskAmount = smallAskAmount + i;
            market.placeAsk(randomAskAmount, RECEIVER1);
        }
        vm.stopPrank();

        vm.warp(clearHour);
        market.clearMarket(correctHour);

        uint256 totalMatchedAmount = 0;
        for (uint256 i = 0; i < loops; i++) {
            (, , bool settled, ,) = market.bidsByHour(correctHour, i);
            if (settled) {
                (, uint88 actualBidAmount, , ,) = market.bidsByHour(correctHour, i);
                totalMatchedAmount += actualBidAmount;
            }
        }

        assert(totalMatchedAmount <= totalBidAmount);
    }

    // ============ View Function Tests ============

    function test_getBidsByHour() public {
        uint256 bidPrice = market.MIN_PRICE();
        market.placeBid{value: bidPrice * bidAmount}(correctHour, bidAmount);

        Bid[] memory bids = market.getBidsByHour(correctHour);

        assertEq(bids[0].bidder, address(this));
        assertEq(bids[0].amount, bidAmount);
        assertEq(bids[0].price, bidPrice);
        assertEq(bids[0].settled, false);
        assertEq(bids.length, 1);
    }

    function test_getAsksByHour() public {
        vm.warp(askHour);
        uint256 amount = 100;

        vm.prank(SELLER);
        market.placeAsk(amount, RECEIVER1);

        Ask[] memory asks = market.getAsksByHour(correctHour);

        assertEq(asks[0].seller, RECEIVER1);
        assertEq(asks[0].amount, amount);
        assertEq(asks[0].settled, false);
        assertEq(asks.length, 1);
    }

    function test_getAsksByAddress() public {
        vm.warp(askHour);

        vm.startPrank(SELLER);
        market.placeAsk(100, RECEIVER1);
        market.placeAsk(200, RECEIVER2);
        market.placeAsk(50, RECEIVER1);
        vm.stopPrank();

        Ask[] memory receiver1Asks = market.getAsksByAddress(correctHour, RECEIVER1);

        assertEq(receiver1Asks.length, 2);
        assertEq(receiver1Asks[0].seller, RECEIVER1);
        assertEq(receiver1Asks[0].amount, 100);
        assertEq(receiver1Asks[1].seller, RECEIVER1);
        assertEq(receiver1Asks[1].amount, 50);
    }

    function test_getBidsByAddress() public {
        vm.prank(address(0xBEEF));
        market.placeBid{value: minimumPrice * bidAmount}(correctHour, bidAmount);

        market.placeBid{value: 200 * minimumPrice}(correctHour, 200);

        vm.prank(address(0xBEEF));
        market.placeBid{value: minimumPrice * 50}(correctHour, 50);

        Bid[] memory beefBids = market.getBidsByAddress(correctHour, address(0xBEEF));

        assertEq(beefBids.length, 2);
        assertEq(beefBids[0].bidder, address(0xBEEF));
        assertEq(beefBids[0].amount, 100);
        assertEq(beefBids[1].bidder, address(0xBEEF));
        assertEq(beefBids[1].amount, 50);
    }

    // ============ Multiple Bid Tests ============

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

    // ============ Cancel Bid Tests ============

    function test_cancelBid_Success() public {
        market.placeBid{value: minimumPrice * bidAmount}(correctHour, bidAmount);
        market.cancelBid(correctHour, 0);

        (, , , , bool canceled) = market.bidsByHour(correctHour, 0);
        assertEq(canceled, true);

        uint256 expectedBalance = bidAmount * minimumPrice;
        assertEq(market.claimableBalance(address(this)), expectedBalance);
    }

    function test_cancelBid_NotBidOwner() public {
        vm.prank(address(0xBEEF));
        market.placeBid{value: minimumPrice * bidAmount}(correctHour, bidAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__OnlyBidOwnerCanCancel.selector,
                correctHour,
                address(this)
            )
        );
        market.cancelBid(correctHour, 0);
    }

    function test_cancelBid_MarketCleared() public {
        market.placeBid{value: minimumPrice * bidAmount}(correctHour, bidAmount);
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

    function test_cancelBid_AlreadyCanceled() public {
        market.placeBid{value: minimumPrice * bidAmount}(correctHour, bidAmount);
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

    // ============ Sorting Tests ============

    function test_IncorrectSorting() public {
        uint256 hour = market.getCurrentHourTimestamp() + 3600;

        uint256 numberOfBids = 5;
        uint256[] memory energyAmounts = new uint256[](numberOfBids);
        uint256[] memory ethAmounts = new uint256[](numberOfBids);

        energyAmounts[0] = 5791;
        energyAmounts[1] = 8472;
        energyAmounts[2] = 953;
        energyAmounts[3] = 8403;
        energyAmounts[4] = 9565;

        ethAmounts[0] = 479008935626859662;
        ethAmounts[1] = 276139232672438773;
        ethAmounts[2] = 743742146016760527;
        ethAmounts[3] = 33642988462095454;
        ethAmounts[4] = 350037435968563937;

        vm.startPrank(BIDDER);
        for (uint256 i; i < numberOfBids; ++i) {
            market.placeBid{value: ethAmounts[i]}(hour, energyAmounts[i]);
        }
        vm.stopPrank();

        Bid[] memory unsortedBids = market.getBidsByHour(hour);
        uint256[] memory sortedIndices = BidSorterLib.sortedBidIndicesDescending(unsortedBids);

        Bid[] memory sortedBids = new Bid[](sortedIndices.length);
        for (uint256 j; j < sortedIndices.length; j++) {
            sortedBids[j] = unsortedBids[sortedIndices[j]];
        }

        bool isSorted = true;
        for (uint256 k = 1; k < numberOfBids; ++k) {
            if (sortedBids[k].price > sortedBids[k - 1].price) {
                isSorted = false;
                break;
            }
        }

        assertTrue(isSorted);
    }

    function test_canceledBidsAreNotFulfilledInClearedMarket() public {
        uint256 numberOfBids = 5;
        uint256[] memory energyAmounts = new uint256[](numberOfBids);
        uint256[] memory ethAmounts = new uint256[](numberOfBids);

        energyAmounts[0] = 5791;
        energyAmounts[1] = 8472;
        energyAmounts[2] = 953;
        energyAmounts[3] = 8403;
        energyAmounts[4] = 9565;

        ethAmounts[0] = 479008935626859662;
        ethAmounts[1] = 276139232672438773;
        ethAmounts[2] = 743742146016760527;
        ethAmounts[3] = 33642988462095454;
        ethAmounts[4] = 350037435968563937;

        vm.startPrank(BIDDER);
        for (uint256 i = 0; i < numberOfBids; i++) {
            market.placeBid{value: ethAmounts[i]}(correctHour, energyAmounts[i]);
        }

        Bid[] memory bids = market.getBidsByHour(correctHour);
        uint256 firstMaxIndex;
        uint256 secondMaxIndex;
        uint256 maxPrice = 0;
        uint256 secondMaxPrice = 0;

        for (uint256 i = 0; i < numberOfBids; i++) {
            uint256 price = bids[i].price;
            if (price > maxPrice) {
                secondMaxPrice = maxPrice;
                secondMaxIndex = firstMaxIndex;
                maxPrice = price;
                firstMaxIndex = i;
            } else if (price > secondMaxPrice) {
                secondMaxPrice = price;
                secondMaxIndex = i;
            }
        }

        market.cancelBid(correctHour, firstMaxIndex);
        market.cancelBid(correctHour, secondMaxIndex);
        vm.stopPrank();

        vm.warp(askHour);
        uint256 totalEnergy = 0;
        for (uint256 i = 0; i < numberOfBids; i++) {
            if (i != firstMaxIndex && i != secondMaxIndex) {
                totalEnergy += energyAmounts[i];
            }
        }

        vm.prank(SELLER);
        market.placeAsk(totalEnergy, RECEIVER1);

        vm.warp(clearHour);
        market.clearMarket(correctHour);

        bids = market.getBidsByHour(correctHour);
        uint256[] memory sortedIndices = BidSorterLib.sortedBidIndicesDescending(bids);
        assertEq(sortedIndices.length, 3);

        for (uint256 i = 0; i < numberOfBids; i++) {
            (, , bool settled, , bool canceled) = market.bidsByHour(correctHour, i);
            if (i == firstMaxIndex || i == secondMaxIndex) {
                assertTrue(canceled);
                assertFalse(settled);
            } else {
                assertFalse(canceled);
                assertTrue(settled);
            }
        }

        (, uint88 askAmount, , uint88 matchedAmount) = market.asksByHour(correctHour, 0);
        assertEq(matchedAmount, askAmount);
        assertEq(matchedAmount, totalEnergy);
    }

    function test_multipleBidsPricedAtClearingPrice() public {
        vm.startPrank(BIDDER);
        market.placeBid{value: 1 ether}(correctHour, 100);
        market.placeBid{value: 1 ether}(correctHour, 100);
        vm.stopPrank();

        vm.warp(askHour);

        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        vm.warp(clearHour);
        market.clearMarket(correctHour);

        Bid[] memory bids = market.getBidsByHour(correctHour);

        // Both bids are marked settled: one fulfilled, one refunded
        assertTrue(bids[0].settled);
        assertTrue(bids[1].settled);
        assertEq(market.claimableBalance(BIDDER), 1 ether);
        assertEq(market.claimableBalance(RECEIVER1), 1 ether);
        assertEq(address(market).balance, 2 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__MarketAlreadyClearedForThisHour.selector,
                correctHour
            )
        );
        vm.prank(BIDDER);
        market.cancelBid(correctHour, 1);
    }

    // ============ Upgrade Tests ============

    function test_proxyUpgradability() public {
        EnergyBiddingMarket newImplementation = new EnergyBiddingMarket();

        UnsafeUpgrades.upgradeProxy(address(market), address(newImplementation), "");

        bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 slotValue = vm.load(address(market), IMPLEMENTATION_SLOT);
        address retrievedImplementation = address(uint160(uint256(slotValue)));

        assertEq(retrievedImplementation, address(newImplementation));
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

    // ============ Helper Functions ============

    function _logBidPrices(Bid[] memory bids) private pure {
        for (uint256 i; i < bids.length; ++i) {
            console.log("Price of bid #%d : %18e ETH", i, bids[i].price);
        }
        console.log("");
    }
}
