// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Bid, Ask, AskInput} from "../types/MarketTypes.sol";

/// @title IEnergyBiddingMarket
/// @notice Interface for the Energy Bidding Market contract
/// @dev Defines all external functions for the energy trading market
interface IEnergyBiddingMarket {
    // ============ Events ============

    /// @notice Emitted when a bid is placed
    event BidPlaced(
        address indexed bidder,
        uint256 indexed hour,
        uint256 amount,
        uint256 price
    );

    /// @notice Emitted when an ask is placed
    event AskPlaced(
        address indexed seller,
        uint256 indexed hour,
        uint256 amount
    );

    /// @notice Emitted when the market is cleared for an hour
    event MarketCleared(uint256 indexed hour, uint256 clearingPrice);

    /// @notice Emitted when a bid is matched with an ask during market clearing
    event EnergyTraded(
        uint256 indexed hour,
        address indexed buyer,
        address indexed seller,
        uint256 amount,
        uint256 clearingPrice
    );

    /// @notice Emitted when a bid is canceled
    event BidCanceled(
        uint256 indexed hour,
        uint256 indexed index,
        address indexed bidder,
        uint256 refundAmount
    );

    /// @notice Emitted when a seller whitelist status changes
    event SellerWhitelistUpdated(address indexed seller, bool enabled);

    /// @notice Emitted when a user claims their balance
    event BalanceClaimed(address indexed user, address indexed to, uint256 amount);

    /// @notice Emitted when a bid is refunded during market clearing (no energy available)
    event BidRefunded(
        uint256 indexed hour,
        uint256 indexed index,
        address indexed bidder,
        uint256 refundAmount
    );

    // ============ Bidder Functions ============

    /// @notice Places a bid for energy in a specific market hour
    /// @param hour The market hour for which the bid is being placed
    /// @param amount The amount of energy in Watts being bid for
    function placeBid(uint256 hour, uint256 amount) external payable;

    /// @notice Places multiple bids for energy over a range of market hours
    /// @param beginHour The starting hour of the range
    /// @param endHour The ending hour of the range
    /// @param amount The amount of energy in Watts being bid for each hour
    function placeMultipleBids(
        uint256 beginHour,
        uint256 endHour,
        uint256 amount
    ) external payable;

    /// @notice Places multiple bids for energy in specified market hours
    /// @param biddingHours An array of market hours for which bids are being placed
    /// @param amount The amount of energy in Watts being bid for each hour
    function placeMultipleBids(
        uint256[] calldata biddingHours,
        uint256 amount
    ) external payable;

    /// @notice Cancels a bid for a specific hour
    /// @param hour The hour of the bid to cancel
    /// @param index The index of the bid in the storage array
    function cancelBid(uint256 hour, uint256 index) external;

    // ============ Seller Functions (Whitelisted Only) ============

    /// @notice Places an ask for selling energy in the current market hour
    /// @param amount The amount of energy in Watts being offered
    /// @param receiver The address that will receive payment for the energy
    function placeAsk(uint256 amount, address receiver) external;

    /// @notice Places multiple asks for different receivers and clears a past market hour
    /// @dev Only callable by whitelisted sellers. Uses off-chain sorting for gas optimization.
    /// @param hour The past hour to place asks for and clear
    /// @param asks Array of AskInput structs containing receiver and amount
    /// @param sortedBidIndices Pre-sorted bid indices (descending by price) for gas-efficient clearing
    function placeAsksAndClearMarket(
        uint256 hour,
        AskInput[] calldata asks,
        uint256[] calldata sortedBidIndices
    ) external;

    // ============ Market Functions ============

    /// @notice Clears the market for a specific hour (uses on-chain sorting)
    /// @param hour The market hour to clear
    function clearMarket(uint256 hour) external;

    /// @notice Clears the market with pre-sorted bid indices (gas optimized)
    /// @dev Off-chain sorting with on-chain verification - O(n) vs O(n log n)
    /// @param hour The market hour to clear
    /// @param sortedBidIndices Bid indices sorted by price descending (highest first)
    function clearMarketWithSortedBids(
        uint256 hour,
        uint256[] calldata sortedBidIndices
    ) external;

    /// @notice Clears the market for the past hour
    function clearMarketPastHour() external;

    /// @notice Allows users to claim any balance available to them
    function claimBalance() external;

    /// @notice Allows users to claim balance to a different address (useful if msg.sender is a contract that can't receive ETH)
    /// @param to The address to send the balance to
    function claimBalanceTo(address payable to) external;

    // ============ Admin Functions ============

    /// @notice Whitelists or removes a seller from the whitelist
    /// @param seller The address of the seller
    /// @param enable True to whitelist, false to remove
    function whitelistSeller(address seller, bool enable) external;

    // ============ View Functions ============

    /// @notice Returns the claimable balance of a user
    /// @param user The address of the user
    /// @return The claimable balance in wei
    function balanceOf(address user) external view returns (uint256);

    /// @notice Retrieves all bids for a specific hour
    /// @param hour The hour to query
    /// @return An array of Bid structs
    function getBidsByHour(uint256 hour) external view returns (Bid[] memory);

    /// @notice Retrieves all asks for a specific hour
    /// @param hour The hour to query
    /// @return An array of Ask structs
    function getAsksByHour(uint256 hour) external view returns (Ask[] memory);

    /// @notice Retrieves all bids by a specific user for a specific hour
    /// @param hour The hour to query
    /// @param user The user address
    /// @return An array of Bid structs
    function getBidsByAddress(
        uint256 hour,
        address user
    ) external view returns (Bid[] memory);

    /// @notice Retrieves all asks by a specific user for a specific hour
    /// @param hour The hour to query
    /// @param user The user address
    /// @return An array of Ask structs
    function getAsksByAddress(
        uint256 hour,
        address user
    ) external view returns (Ask[] memory);

    /// @notice Gets the clearing price for a specific hour
    /// @param hour The hour to query
    /// @return The clearing price in wei per Watt
    function getClearingPrice(uint256 hour) external view returns (uint256);

    /// @notice Gets the current hour timestamp
    /// @return The Unix timestamp of the start of the current hour
    function getCurrentHourTimestamp() external view returns (uint256);

    /// @notice Checks if a seller is whitelisted
    /// @param seller The address to check
    /// @return True if whitelisted
    function isSellerWhitelisted(address seller) external view returns (bool);

    /// @notice Returns the total available energy for a specific hour
    /// @param hour The hour to query
    /// @return The total available energy in Watts
    function getTotalAvailableEnergy(uint256 hour) external view returns (uint256);
}
