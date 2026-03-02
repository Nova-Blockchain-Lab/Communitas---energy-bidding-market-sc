// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// MarketTypes
// Contains all custom types, structs, and errors for the Energy Bidding Market

// ============ Errors ============

error EnergyBiddingMarket__WrongHourProvided(uint256 hour);
error EnergyBiddingMarket__WrongHoursProvided(uint256 beginHour, uint256 endHour);
error EnergyBiddingMarket__NoBidsOrAsksForThisHour(uint256 hour);
error EnergyBiddingMarket__MarketAlreadyClearedForThisHour(uint256 hour);
error EnergyBiddingMarket__NoClaimableBalance(address user);
error EnergyBiddingMarket__OnlyBidOwnerCanCancel(uint256 hour, address bidder);
error EnergyBiddingMarket__BidMinimumPriceNotMet(uint256 price, uint256 minimumPrice);
error EnergyBiddingMarket__AmountCannotBeZero();
error EnergyBiddingMarket__BidIsAlreadyCanceled(uint256 hour, uint256 index);
error EnergyBiddingMarket__SellerIsNotWhitelisted(address seller);
error EnergyBiddingMarket__BidDoesNotExist(uint256 hour, uint256 index);
error EnergyBiddingMarket__InvalidSellerAddress();
error EnergyBiddingMarket__HourNotInPast(uint256 hour);
error EnergyBiddingMarket__ETHTransferFailed();
error EnergyBiddingMarket__InvalidSortOrder();
error EnergyBiddingMarket__ValueExceedsUint88(uint256 value);
error EnergyBiddingMarket__DuplicateBidIndex(uint256 hour, uint256 index);
error EnergyBiddingMarket__EmptyAsksArray();
error EnergyBiddingMarket__InvalidAddress();

// ============ Structs ============

/// @notice Represents a bid in the energy market
/// @dev Packed to optimize storage (2 slots instead of 3)
struct Bid {
    address bidder;      // 20 bytes - Address of the bidder
    uint88 amount;       // 11 bytes - Amount of energy in Watts (max ~309 TWh)
    bool settled;        // 1 byte - Flag indicating if bid has been settled
    uint88 price;        // 11 bytes - Price per Watt in wei (max ~309 ETH per Watt)
    bool canceled;       // 1 byte - Flag indicating if bid has been canceled
    // Total: 44 bytes = 2 storage slots
}

/// @notice Represents an ask (sell order) in the energy market
/// @dev Packed to optimize storage. Asks cannot be canceled (energy already injected)
struct Ask {
    address seller;          // 20 bytes - Address of the energy seller (receiver of payment)
    uint88 amount;           // 11 bytes - Amount of energy in Watts
    bool settled;            // 1 byte - Flag indicating if ask has been settled
    uint88 matchedAmount;    // 11 bytes - Amount of energy matched with bids
    // Total: 43 bytes = 2 storage slots
}

/// @notice Input struct for batch ask submissions
struct AskInput {
    address receiver;    // Address to receive payment for this energy sale
    uint88 amount;       // Amount of energy in Watts
}
