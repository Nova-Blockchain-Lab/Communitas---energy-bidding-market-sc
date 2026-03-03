// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {
    EnergyBiddingMarket__ValueExceedsUint88,
    EnergyBiddingMarket__DuplicateBidIndex,
    EnergyBiddingMarket__ETHTransferFailed
} from "../../src/types/MarketTypes.sol";

/// @title Error Paths Unit Tests
/// @notice Tests for error paths that are hard to trigger in normal usage
contract ErrorPathsTest is BaseTest {
    // ============ ValueExceedsUint88 Tests ============

    function test_placeBid_AmountExceedsUint88() public {
        uint256 overflowAmount = uint256(type(uint88).max) + 1;

        // Use a small msg.value to avoid overflow
        // price = msg.value / amount will be 0 or very small, but the amount check triggers first
        vm.deal(address(this), 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__ValueExceedsUint88.selector,
                overflowAmount
            )
        );
        market.placeBid{value: 1 ether}(correctHour, overflowAmount);
    }

    function test_placeBid_PriceExceedsUint88() public {
        // Send enough ETH that price = msg.value / amount overflows uint88
        // amount = 1, price = msg.value
        uint256 amount = 1;
        uint256 overflowPrice = uint256(type(uint88).max) + 1;

        vm.deal(address(this), overflowPrice);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__ValueExceedsUint88.selector,
                overflowPrice
            )
        );
        market.placeBid{value: overflowPrice}(correctHour, amount);
    }

    function test_placeMultipleBids_Range_AmountExceedsUint88() public {
        uint256 overflowAmount = uint256(type(uint88).max) + 1;
        uint256 endHour = correctHour + 7200;
        uint256 testPrice = 1e12;

        vm.deal(address(this), testPrice * overflowAmount * 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__ValueExceedsUint88.selector,
                overflowAmount
            )
        );
        market.placeMultipleBids{value: testPrice * overflowAmount * 2}(correctHour, endHour, overflowAmount);
    }

    function test_placeMultipleBids_Array_AmountExceedsUint88() public {
        uint256 overflowAmount = uint256(type(uint88).max) + 1;
        uint256[] memory biddingHours = new uint256[](1);
        biddingHours[0] = correctHour;
        uint256 testPrice = 1e12;

        vm.deal(address(this), testPrice * overflowAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__ValueExceedsUint88.selector,
                overflowAmount
            )
        );
        market.placeMultipleBids{value: testPrice * overflowAmount}(biddingHours, overflowAmount);
    }

    // ============ DuplicateBidIndex Tests ============

    function test_clearMarketWithSortedBids_DuplicateIndex() public {
        // Place 2 bids
        uint256 testPrice = 1e12;
        market.placeBid{value: testPrice * 100}(correctHour, 100);
        market.placeBid{value: testPrice * 2 * 50}(correctHour, 50);

        vm.warp(askHour);
        vm.prank(SELLER);
        market.placeAsk(100, RECEIVER1);

        vm.warp(clearHour);

        // Provide duplicate index
        uint256[] memory sortedIndices = new uint256[](2);
        sortedIndices[0] = 1; // higher price
        sortedIndices[1] = 1; // DUPLICATE

        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__DuplicateBidIndex.selector,
                correctHour,
                1
            )
        );
        market.clearMarketWithSortedBids(correctHour, sortedIndices);
    }

    // ============ ETHTransferFailed Tests ============

    function test_claimBalance_ETHTransferFailed() public {
        // Deploy a contract that rejects ETH transfers
        ETHRejecter rejecter = new ETHRejecter();
        vm.deal(address(rejecter), 100 ether);
        uint256 testPrice = 1e12;

        // Place bid from the rejecter contract
        vm.prank(address(rejecter));
        market.placeBid{value: testPrice * 100}(correctHour, 100);

        // Cancel the bid to generate claimable balance
        vm.prank(address(rejecter));
        market.cancelBid(correctHour, 0);

        assertEq(market.claimableBalance(address(rejecter)), testPrice * 100);

        // Attempting to claim should fail because rejecter rejects ETH
        vm.prank(address(rejecter));
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyBiddingMarket__ETHTransferFailed.selector
            )
        );
        market.claimBalance();
    }

    function test_claimBalanceTo_SucceedsWhenSenderRejectsETH() public {
        // Deploy a contract that rejects ETH transfers
        ETHRejecter rejecter = new ETHRejecter();
        vm.deal(address(rejecter), 100 ether);
        uint256 testPrice = 1e12;

        // Place bid from the rejecter contract
        vm.prank(address(rejecter));
        market.placeBid{value: testPrice * 100}(correctHour, 100);

        // Cancel the bid to generate claimable balance
        vm.prank(address(rejecter));
        market.cancelBid(correctHour, 0);

        // claimBalanceTo a different address that CAN receive ETH
        address payable recipient = payable(makeAddr("recipient"));
        uint256 recipientBalanceBefore = recipient.balance;

        vm.prank(address(rejecter));
        market.claimBalanceTo(recipient);

        assertEq(market.claimableBalance(address(rejecter)), 0);
        assertEq(recipient.balance, recipientBalanceBefore + testPrice * 100);
    }
}

/// @notice Helper contract that rejects ETH transfers (no receive/fallback)
contract ETHRejecter {
    // No receive() or fallback() — will revert on ETH transfer
}
