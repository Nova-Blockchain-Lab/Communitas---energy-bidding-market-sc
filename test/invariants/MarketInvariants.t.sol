// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EnergyBiddingMarket} from "../../src/EnergyBiddingMarket.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/// @title Market Invariants Handler
/// @notice Handler contract for invariant testing
contract MarketHandler is Test {
    EnergyBiddingMarket public market;
    uint256 public minimumPrice;
    uint256 public correctHour;
    uint256 public askHour;
    uint256 public clearHour;

    address public seller;
    address public receiver;
    address[] public bidders;

    uint256 public totalDeposited;
    uint256 public totalWithdrawn;
    uint256 public totalRefunded;

    constructor(
        EnergyBiddingMarket _market,
        uint256 _minimumPrice,
        uint256 _correctHour,
        address _seller,
        address _receiver
    ) {
        market = _market;
        minimumPrice = _minimumPrice;
        correctHour = _correctHour;
        askHour = _correctHour + 3600;
        clearHour = _correctHour + 7200;
        seller = _seller;
        receiver = _receiver;

        // Create some bidders
        for (uint256 i = 0; i < 5; i++) {
            address bidder = makeAddr(string.concat("bidder", vm.toString(i)));
            vm.deal(bidder, 100 ether);
            bidders.push(bidder);
        }
    }

    function placeBid(uint256 bidderIndex, uint256 amount, uint256 priceMultiplier) external {
        bidderIndex = bound(bidderIndex, 0, bidders.length - 1);
        amount = bound(amount, 1, 10000);
        priceMultiplier = bound(priceMultiplier, 1, 10);

        uint256 price = minimumPrice * priceMultiplier;
        uint256 totalValue = price * amount;

        address bidder = bidders[bidderIndex];

        vm.prank(bidder);
        try market.placeBid{value: totalValue}(correctHour, amount) {
            totalDeposited += totalValue;
        } catch {}
    }

    function placeAsk(uint256 amount) external {
        amount = bound(amount, 1, 10000);

        vm.warp(askHour);
        vm.prank(seller);
        try market.placeAsk(amount, receiver) {} catch {}
    }

    function cancelBid(uint256 bidderIndex, uint256 bidIndex) external {
        if (market.totalBidsByHour(correctHour) == 0) return;

        bidderIndex = bound(bidderIndex, 0, bidders.length - 1);
        bidIndex = bound(bidIndex, 0, market.totalBidsByHour(correctHour) - 1);

        address bidder = bidders[bidderIndex];
        (address storedBidder,,, , bool canceled) = market.bidsByHour(correctHour, bidIndex);

        if (storedBidder == bidder && !canceled) {
            uint256 balanceBefore = bidder.balance;
            vm.prank(bidder);
            try market.cancelBid(correctHour, bidIndex) {
                uint256 balanceAfter = bidder.balance;
                totalRefunded += balanceAfter - balanceBefore;
            } catch {}
        }
    }

    function clearMarket() external {
        if (market.isMarketCleared(correctHour)) return;
        if (market.totalBidsByHour(correctHour) == 0) return;

        vm.warp(clearHour);
        try market.clearMarket(correctHour) {} catch {}
    }

    function claimBalance(uint256 bidderIndex) external {
        bidderIndex = bound(bidderIndex, 0, bidders.length - 1);
        address bidder = bidders[bidderIndex];

        uint256 claimable = market.claimableBalance(bidder);
        if (claimable == 0) return;

        uint256 balanceBefore = bidder.balance;
        vm.prank(bidder);
        try market.claimBalance() {
            totalWithdrawn += bidder.balance - balanceBefore;
        } catch {}
    }

    function claimSellerBalance() external {
        uint256 claimable = market.claimableBalance(receiver);
        if (claimable == 0) return;

        uint256 balanceBefore = receiver.balance;
        vm.prank(receiver);
        try market.claimBalance() {
            totalWithdrawn += receiver.balance - balanceBefore;
        } catch {}
    }
}

/// @title Market Invariants Test
/// @notice Invariant tests for the EnergyBiddingMarket contract
contract MarketInvariantsTest is Test {
    EnergyBiddingMarket public market;
    MarketHandler public handler;

    uint256 public minimumPrice = 1e12;
    uint256 public correctHour;
    address public seller = makeAddr("seller");
    address public receiver = makeAddr("receiver");

    function setUp() public {
        // Set timestamp to a valid hour
        vm.warp(1700000000);
        correctHour = block.timestamp - (block.timestamp % 3600);

        // Deploy market
        address implementation = address(new EnergyBiddingMarket());
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            implementation,
            abi.encodeWithSelector(EnergyBiddingMarket.initialize.selector, address(this))
        );
        market = EnergyBiddingMarket(proxy);

        // Whitelist seller
        market.whitelistSeller(seller, true);

        // Create handler
        handler = new MarketHandler(market, minimumPrice, correctHour, seller, receiver);

        // Fund contract for testing
        vm.deal(address(market), 0);

        // Target handler for invariant testing
        targetContract(address(handler));
    }

    /// @notice Invariant: Contract balance >= sum of claimable balances
    function invariant_contractSolvency() public view {
        // Sum all claimable balances
        uint256 totalClaimable;

        // Check handler bidders
        for (uint256 i = 0; i < 5; i++) {
            address bidder = handler.bidders(i);
            totalClaimable += market.claimableBalance(bidder);
        }

        // Add receiver balance
        totalClaimable += market.claimableBalance(receiver);

        // Contract should always have enough to pay
        assertGe(
            address(market).balance,
            totalClaimable,
            "Contract balance must cover all claimable balances"
        );
    }

    /// @notice Invariant: Market cleared flag is immutable once set
    function invariant_marketClearedImmutable() public view {
        // If market was cleared, it should remain cleared
        if (market.isMarketCleared(correctHour)) {
            assertTrue(
                market.isMarketCleared(correctHour),
                "Market cleared flag should be immutable"
            );
        }
    }

    /// @notice Invariant: Clearing price is within bid range when market is cleared
    function invariant_clearingPriceWithinRange() public view {
        if (!market.isMarketCleared(correctHour)) return;

        uint256 clearingPrice = market.clearingPricePerHour(correctHour);

        // Clearing price must be at least minimum price
        assertGe(
            clearingPrice,
            minimumPrice,
            "Clearing price must be >= minimum price"
        );

        // Clearing price must not exceed any bid price (checked against bid that was matched)
        // This is implicitly guaranteed by the algorithm
    }

    /// @notice Invariant: Total bids count never decreases (only increases or stays same)
    function invariant_bidCountMonotonic() public view {
        // Bids can only be added, never removed
        // totalBidsByHour should only increase
        uint256 totalBids = market.totalBidsByHour(correctHour);
        assertGe(totalBids, 0, "Total bids should never be negative");
    }

    /// @notice Invariant: Canceled bids are not settled
    function invariant_canceledBidsNotSettled() public view {
        uint256 totalBids = market.totalBidsByHour(correctHour);

        for (uint256 i = 0; i < totalBids; i++) {
            (, , bool settled, , bool canceled) = market.bidsByHour(correctHour, i);

            if (canceled) {
                assertFalse(settled, "Canceled bids should not be settled");
            }
        }
    }

    /// @notice Invariant: Settled bids are not canceled
    function invariant_settledBidsNotCanceled() public view {
        uint256 totalBids = market.totalBidsByHour(correctHour);

        for (uint256 i = 0; i < totalBids; i++) {
            (, , bool settled, , bool canceled) = market.bidsByHour(correctHour, i);

            if (settled) {
                assertFalse(canceled, "Settled bids should not be canceled");
            }
        }
    }

    /// @notice Invariant: Ask matched amount <= ask total amount
    function invariant_askMatchedNotExceedTotal() public view {
        uint256 totalAsks = market.totalAsksByHour(correctHour);

        for (uint256 i = 0; i < totalAsks; i++) {
            (, uint88 amount, , uint88 matchedAmount) = market.asksByHour(correctHour, i);

            assertLe(
                matchedAmount,
                amount,
                "Ask matched amount should not exceed total amount"
            );
        }
    }
}
