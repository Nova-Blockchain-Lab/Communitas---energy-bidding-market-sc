// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {IEnergyBiddingMarket} from "../../src/interfaces/IEnergyBiddingMarket.sol";
import {AskInput} from "../../src/types/MarketTypes.sol";

/// @title EnergyTraded Event Unit Tests
/// @notice Tests that the EnergyTraded event is emitted correctly during market clearing
contract EnergyTradedTest is BaseTest {
    address internal BIDDER2 = makeAddr("bidder2");
    address internal SELLER2 = makeAddr("seller2");

    function setUp() public override {
        super.setUp();
        vm.deal(BIDDER2, 100 ether);
        market.whitelistSeller(SELLER2, true);
    }

    /// @notice 1 bid, 1 ask, exact match -> 1 EnergyTraded event
    function test_energyTraded_SingleBidSingleAsk() public {
        // Place bid: 100 kWh at minimumPrice
        vm.prank(BIDDER);
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);

        // Place ask: 100 kWh
        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        // Expect EnergyTraded event
        vm.expectEmit(true, true, true, true);
        emit IEnergyBiddingMarket.EnergyTraded(correctHour, BIDDER, RECEIVER1, 100, minimumPrice);

        // Clear market
        vm.warp(clearHour);
        market.clearMarket(correctHour);
    }

    /// @notice 1 bid consuming 2 asks -> 2 events, same buyer, different sellers
    function test_energyTraded_SingleBidMultipleAsks() public {
        // Place bid: 150 kWh
        vm.prank(BIDDER);
        market.placeBid{value: minimumPrice * 150}(correctHour, 150);

        // Place 2 asks: 80 + 70 kWh
        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(80, RECEIVER1);
        vm.prank(SELLER2);
        market.placeAsk(70, RECEIVER2);

        // Expect 2 EnergyTraded events
        vm.expectEmit(true, true, true, true);
        emit IEnergyBiddingMarket.EnergyTraded(correctHour, BIDDER, RECEIVER1, 80, minimumPrice);
        vm.expectEmit(true, true, true, true);
        emit IEnergyBiddingMarket.EnergyTraded(correctHour, BIDDER, RECEIVER2, 70, minimumPrice);

        vm.warp(clearHour);
        market.clearMarket(correctHour);
    }

    /// @notice 2 bids matched against 1 ask (partial) -> 2 events, different buyers, same seller
    function test_energyTraded_MultipleBidsSingleAsk() public {
        // Place 2 bids at same price: 60 + 40 kWh
        vm.prank(BIDDER);
        market.placeBid{value: minimumPrice * 60}(correctHour, 60);
        vm.prank(BIDDER2);
        market.placeBid{value: minimumPrice * 40}(correctHour, 40);

        // Place ask: 100 kWh (exactly enough for both)
        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        // Both bids at same price, sorted order may vary.
        // We expect 2 EnergyTraded events with RECEIVER1 as seller
        vm.warp(clearHour);

        // Record logs to verify events
        vm.recordLogs();
        market.clearMarket(correctHour);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Count EnergyTraded events
        bytes32 energyTradedTopic = keccak256("EnergyTraded(uint256,address,address,uint256,uint256)");
        uint256 eventCount;
        uint256 totalTraded;
        for (uint256 i; i < entries.length; i++) {
            if (entries[i].topics[0] == energyTradedTopic) {
                // Verify seller is RECEIVER1 (topic[3])
                assertEq(address(uint160(uint256(entries[i].topics[3]))), RECEIVER1);
                // Decode amount from data
                (uint256 amount,) = abi.decode(entries[i].data, (uint256, uint256));
                totalTraded += amount;
                eventCount++;
            }
        }
        assertEq(eventCount, 2, "Should emit 2 EnergyTraded events");
        assertEq(totalTraded, 100, "Total traded should equal 100");
    }

    /// @notice Bid larger than supply -> event amount matches partial fill, not full bid
    function test_energyTraded_PartialFill() public {
        // Place bid: 200 kWh
        vm.prank(BIDDER);
        market.placeBid{value: minimumPrice * 200}(correctHour, 200);

        // Place ask: only 50 kWh available
        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(50, RECEIVER1);

        // Event should show 50, not 200
        vm.expectEmit(true, true, true, true);
        emit IEnergyBiddingMarket.EnergyTraded(correctHour, BIDDER, RECEIVER1, 50, minimumPrice);

        vm.warp(clearHour);
        market.clearMarket(correctHour);
    }

    /// @notice Supply is 0 -> no EnergyTraded events emitted
    function test_energyTraded_NoMatch() public {
        // Place bid only, no asks
        vm.prank(BIDDER);
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);

        // Place ask with 0 supply by not placing any asks at all
        // We need at least 1 bid to clear. Since totalAvailableEnergy == 0,
        // clearingPrice == 0, and all bids get refunded with no matching.
        // But clearMarket requires bids to exist for sorting.
        // Place a tiny ask so market can clear, but bid won't match at 0 energy
        vm.warp(askHour);
        // Actually: with no asks, totalAvailableEnergy == 0, clearingPrice == 0,
        // all bids get refunded. No EnergyTraded should be emitted.
        // We need at least one ask placed to have a valid market to clear.
        // Let's place an ask but check no trade events when bid price is below clearing.
        // Simplest: place ask with 0 total supply - but placeAsk rejects 0.
        // Instead: verify via recordLogs that no EnergyTraded is emitted
        // when we have an ask but clearing price ends up refunding the bid.
        // Actually the simplest no-match scenario: bid at min price, ask exists,
        // but clearing price is 0 because totalAvailableEnergy is 0 won't work.
        //
        // Let's just use a scenario where we have bids but cancel them all,
        // but that reverts. Simplest: no asks means clearingPrice = 0, all bids refunded.
        // We need at least 1 bid (non-canceled) for clearMarket to not revert.
        // With no asks: totalAvailableEnergy = 0, clearingPrice = 0, all bids refunded.
        vm.warp(clearHour);

        vm.recordLogs();
        market.clearMarket(correctHour);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 energyTradedTopic = keccak256("EnergyTraded(uint256,address,address,uint256,uint256)");
        for (uint256 i; i < entries.length; i++) {
            assertTrue(entries[i].topics[0] != energyTradedTopic, "No EnergyTraded events should be emitted");
        }
    }

    /// @notice Events fire through placeAsksAndClearMarket path
    function test_energyTraded_ViaBatchAsksAndClear() public {
        // Place bid
        vm.prank(BIDDER);
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);

        vm.warp(clearHour);

        AskInput[] memory asks = new AskInput[](1);
        asks[0] = AskInput({receiver: RECEIVER1, amount: 100});

        uint256[] memory sortedIndices = new uint256[](1);
        sortedIndices[0] = 0;

        vm.expectEmit(true, true, true, true);
        emit IEnergyBiddingMarket.EnergyTraded(correctHour, BIDDER, RECEIVER1, 100, minimumPrice);

        vm.prank(SELLER);
        market.placeAsksAndClearMarket(correctHour, asks, sortedIndices);
    }

    /// @notice Events fire through clearMarketWithSortedBids path
    function test_energyTraded_ViaSortedBids() public {
        // Place bid
        vm.prank(BIDDER);
        market.placeBid{value: minimumPrice * 100}(correctHour, 100);

        // Place ask
        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        vm.warp(clearHour);

        uint256[] memory sortedIndices = new uint256[](1);
        sortedIndices[0] = 0;

        vm.expectEmit(true, true, true, true);
        emit IEnergyBiddingMarket.EnergyTraded(correctHour, BIDDER, RECEIVER1, 100, minimumPrice);

        market.clearMarketWithSortedBids(correctHour, sortedIndices);
    }

    /// @notice Sum of all EnergyTraded amounts equals total matched energy and seller payments
    function test_energyTraded_AmountsMatchSettlement() public {
        // Place 2 bids at different prices
        vm.prank(BIDDER);
        market.placeBid{value: minimumPrice * 2 * 80}(correctHour, 80);
        vm.prank(BIDDER2);
        market.placeBid{value: minimumPrice * 50}(correctHour, 50);

        // Place 2 asks totaling 100 kWh
        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(60, RECEIVER1);
        vm.prank(SELLER2);
        market.placeAsk(40, RECEIVER2);

        vm.warp(clearHour);

        // Record balances before
        uint256 receiver1BalanceBefore = market.claimableBalance(RECEIVER1);
        uint256 receiver2BalanceBefore = market.claimableBalance(RECEIVER2);

        vm.recordLogs();
        market.clearMarket(correctHour);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 clearingPrice = market.clearingPricePerHour(correctHour);

        // Sum EnergyTraded amounts per seller
        bytes32 energyTradedTopic = keccak256("EnergyTraded(uint256,address,address,uint256,uint256)");
        uint256 totalTradedAmount;
        uint256 receiver1TradedAmount;
        uint256 receiver2TradedAmount;

        for (uint256 i; i < entries.length; i++) {
            if (entries[i].topics[0] == energyTradedTopic) {
                address seller = address(uint160(uint256(entries[i].topics[3])));
                (uint256 amount, uint256 price) = abi.decode(entries[i].data, (uint256, uint256));

                // Verify clearing price in event
                assertEq(price, clearingPrice, "Event clearing price should match");

                totalTradedAmount += amount;
                if (seller == RECEIVER1) receiver1TradedAmount += amount;
                if (seller == RECEIVER2) receiver2TradedAmount += amount;
            }
        }

        // Total traded should equal total available energy (100) since bid demand (80+50=130) > supply (100)
        assertEq(totalTradedAmount, 100, "Total traded should match total supply");

        // Verify seller payments match event amounts
        uint256 receiver1Payment = market.claimableBalance(RECEIVER1) - receiver1BalanceBefore;
        uint256 receiver2Payment = market.claimableBalance(RECEIVER2) - receiver2BalanceBefore;

        assertEq(receiver1Payment, receiver1TradedAmount * clearingPrice, "Receiver1 payment should match traded amount * clearing price");
        assertEq(receiver2Payment, receiver2TradedAmount * clearingPrice, "Receiver2 payment should match traded amount * clearing price");
    }
}
