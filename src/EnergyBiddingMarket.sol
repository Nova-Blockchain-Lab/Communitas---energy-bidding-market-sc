// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {BidSorterLib} from "./libraries/BidSorterLib.sol";
import {IEnergyBiddingMarket} from "./interfaces/IEnergyBiddingMarket.sol";
import {
    Bid,
    Ask,
    AskInput,
    EnergyBiddingMarket__WrongHourProvided,
    EnergyBiddingMarket__WrongHoursProvided,
    EnergyBiddingMarket__NoBidsOrAsksForThisHour,
    EnergyBiddingMarket__MarketAlreadyClearedForThisHour,
    EnergyBiddingMarket__NoClaimableBalance,
    EnergyBiddingMarket__OnlyBidOwnerCanCancel,
    EnergyBiddingMarket__BidMinimumPriceNotMet,
    EnergyBiddingMarket__AmountCannotBeZero,
    EnergyBiddingMarket__BidIsAlreadyCanceled,
    EnergyBiddingMarket__SellerIsNotWhitelisted,
    EnergyBiddingMarket__BidDoesNotExist,
    EnergyBiddingMarket__InvalidSellerAddress,
    EnergyBiddingMarket__HourNotInPast,
    EnergyBiddingMarket__ETHTransferFailed,
    EnergyBiddingMarket__InvalidSortOrder
} from "./types/MarketTypes.sol";

/// @title EnergyBiddingMarket
/// @author 0xchefmike
/// @notice A uniform price auction market for energy trading
/// @dev Implements UUPS upgradeable pattern. Uses checks-effects-interactions pattern for safety.
contract EnergyBiddingMarket is
    UUPSUpgradeable,
    OwnableUpgradeable,
    IEnergyBiddingMarket
{
    // ============ Constants ============

    /// @notice Minimum price per Watt in wei (0.000001 ETH per Watt)
    /// @dev Approximately $0.003 USD at current prices
    uint256 public constant MIN_PRICE = 1e12;

    // ============ Storage ============

    /// @notice Bids indexed by hour and bid index
    mapping(uint256 => mapping(uint256 => Bid)) public bidsByHour;

    /// @notice Asks indexed by hour and ask index
    mapping(uint256 => mapping(uint256 => Ask)) public asksByHour;

    /// @notice Total number of bids per hour
    mapping(uint256 => uint256) public totalBidsByHour;

    /// @notice Total number of asks per hour
    mapping(uint256 => uint256) public totalAsksByHour;

    /// @notice Clearing price for each hour after market is cleared
    mapping(uint256 => uint256) public clearingPricePerHour;

    /// @notice Total available energy (in Watts) for each hour
    mapping(uint256 => uint256) internal totalAvailableEnergyByHour;

    /// @notice Whether the market has been cleared for a specific hour
    mapping(uint256 => bool) public isMarketCleared;

    /// @notice Claimable balance for each user
    mapping(address => uint256) public claimableBalance;

    /// @notice Whitelist of authorized sellers
    mapping(address => bool) public s_whitelistedSellers;

    // ============ Modifiers ============

    /// @notice Ensures the provided hour is an exact hour timestamp
    modifier assertExactHour(uint256 hour) {
        if (hour % 3600 != 0) {
            revert EnergyBiddingMarket__WrongHourProvided(hour);
        }
        _;
    }

    /// @notice Ensures the caller is a whitelisted seller
    modifier onlyWhitelistedSeller() {
        if (!s_whitelistedSellers[msg.sender]) {
            revert EnergyBiddingMarket__SellerIsNotWhitelisted(msg.sender);
        }
        _;
    }

    /// @notice Ensures the market has not been cleared for the given hour
    modifier isMarketNotCleared(uint256 hour) {
        if (isMarketCleared[hour]) {
            revert EnergyBiddingMarket__MarketAlreadyClearedForThisHour(hour);
        }
        _;
    }

    // ============ Constructor & Initializer ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with the owner address
    /// @param owner The address that will own the contract
    function initialize(address owner) public initializer {
        __Ownable_init(owner);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyOwner {}

    // ============ Bidder Functions ============

    /// @inheritdoc IEnergyBiddingMarket
    function placeBid(
        uint256 hour,
        uint256 amount
    ) external payable {
        if (amount == 0) revert EnergyBiddingMarket__AmountCannotBeZero();

        uint256 price = msg.value / amount;
        uint256 totalCost = price * amount;
        uint256 excess = msg.value - totalCost;

        // Safe cast: practical energy amounts (Watts) and prices fit within uint88 (max ~309 quadrillion)
        // forge-lint: disable-next-line(unsafe-typecast)
        _placeBid(hour, uint88(amount), uint88(price));

        if (excess > 0) {
            _transferETH(msg.sender, excess);
        }
    }

    /// @inheritdoc IEnergyBiddingMarket
    function placeMultipleBids(
        uint256 beginHour,
        uint256 endHour,
        uint256 amount
    ) external payable {
        if (amount == 0) revert EnergyBiddingMarket__AmountCannotBeZero();
        if (beginHour + 3600 > endHour) {
            revert EnergyBiddingMarket__WrongHoursProvided(beginHour, endHour);
        }

        uint256 totalEnergy = ((amount * (endHour - beginHour)) / 3600);
        uint256 price = msg.value / totalEnergy;
        uint256 totalCost = price * totalEnergy;
        uint256 excess = msg.value - totalCost;

        for (uint256 i = beginHour; i < endHour;) {
            // Safe cast: amount and price bounded by practical energy market limits
            // forge-lint: disable-next-line(unsafe-typecast)
            _placeBid(i, uint88(amount), uint88(price));
            unchecked { i += 3600; }
        }

        if (excess > 0) {
            _transferETH(msg.sender, excess);
        }
    }

    /// @inheritdoc IEnergyBiddingMarket
    function placeMultipleBids(
        uint256[] calldata biddingHours,
        uint256 amount
    ) external payable {
        if (amount == 0) revert EnergyBiddingMarket__AmountCannotBeZero();

        uint256 bidsAmount = biddingHours.length;
        uint256 totalEnergy = amount * bidsAmount;
        uint256 price = msg.value / totalEnergy;
        uint256 totalCost = price * totalEnergy;
        uint256 excess = msg.value - totalCost;

        for (uint256 i; i < bidsAmount;) {
            // Safe cast: amount and price bounded by practical energy market limits
            // forge-lint: disable-next-line(unsafe-typecast)
            _placeBid(biddingHours[i], uint88(amount), uint88(price));
            unchecked { ++i; }
        }

        if (excess > 0) {
            _transferETH(msg.sender, excess);
        }
    }

    /// @inheritdoc IEnergyBiddingMarket
    function cancelBid(
        uint256 hour,
        uint256 index
    ) external isMarketNotCleared(hour) {
        uint256 _totalBids = totalBidsByHour[hour];
        if (index >= _totalBids) {
            revert EnergyBiddingMarket__BidDoesNotExist(hour, index);
        }

        Bid storage bid = bidsByHour[hour][index];
        if (msg.sender != bid.bidder) {
            revert EnergyBiddingMarket__OnlyBidOwnerCanCancel(hour, msg.sender);
        }
        if (bid.canceled) {
            revert EnergyBiddingMarket__BidIsAlreadyCanceled(hour, index);
        }

        bid.canceled = true;
        uint256 refundAmount = uint256(bid.amount) * uint256(bid.price);
        claimableBalance[msg.sender] += refundAmount;

        emit BidCanceled(hour, index, msg.sender, refundAmount);
    }

    // ============ Seller Functions ============

    /// @inheritdoc IEnergyBiddingMarket
    function placeAsk(
        uint256 amount,
        address receiver
    ) external onlyWhitelistedSeller {
        if (amount == 0) revert EnergyBiddingMarket__AmountCannotBeZero();
        if (receiver == address(0)) revert EnergyBiddingMarket__InvalidSellerAddress();

        uint256 hour = getCurrentHourTimestamp();
        uint256 totalAsks = totalAsksByHour[hour];

        // Safe cast: practical energy amounts fit within uint88
        // forge-lint: disable-next-line(unsafe-typecast)
        asksByHour[hour][totalAsks] = Ask({
            seller: receiver,
            amount: uint88(amount),
            settled: false,
            matchedAmount: 0
        });

        unchecked {
            totalAsksByHour[hour] = totalAsks + 1;
            totalAvailableEnergyByHour[hour] += amount;
        }

        emit AskPlaced(receiver, hour, amount);
    }

    /// @inheritdoc IEnergyBiddingMarket
    /// @dev Gas-optimized batch ask placement with immediate market clearing using off-chain sorting
    function placeAsksAndClearMarket(
        uint256 hour,
        AskInput[] calldata asks,
        uint256[] calldata sortedBidIndices
    ) external onlyWhitelistedSeller assertExactHour(hour) isMarketNotCleared(hour) {
        // Verify hour is in the past
        if (hour + 3600 > block.timestamp) {
            revert EnergyBiddingMarket__HourNotInPast(hour);
        }

        uint256 asksLength = asks.length;
        if (asksLength == 0) revert EnergyBiddingMarket__AmountCannotBeZero();

        // Cache storage reads
        uint256 currentAskIndex = totalAsksByHour[hour];
        uint256 totalNewEnergy;

        // Batch place all asks - optimized loop
        for (uint256 i; i < asksLength;) {
            AskInput calldata askInput = asks[i];

            if (askInput.receiver == address(0)) {
                revert EnergyBiddingMarket__InvalidSellerAddress();
            }
            if (askInput.amount == 0) {
                revert EnergyBiddingMarket__AmountCannotBeZero();
            }

            asksByHour[hour][currentAskIndex] = Ask({
                seller: askInput.receiver,
                amount: askInput.amount,
                settled: false,
                matchedAmount: 0
            });

            emit AskPlaced(askInput.receiver, hour, askInput.amount);

            unchecked {
                totalNewEnergy += askInput.amount;
                ++currentAskIndex;
                ++i;
            }
        }

        // Update storage once
        totalAsksByHour[hour] = currentAskIndex;
        totalAvailableEnergyByHour[hour] += totalNewEnergy;

        // Clear the market using off-chain sorting verification (gas optimized)
        _clearMarketWithVerification(hour, sortedBidIndices);
    }

    // ============ Market Functions ============

    /// @inheritdoc IEnergyBiddingMarket
    /// @dev Uses on-chain sorting (more gas expensive). Consider using clearMarketWithSortedBids for gas savings.
    function clearMarket(
        uint256 hour
    ) external assertExactHour(hour) {
        if (hour + 3600 > block.timestamp) {
            revert EnergyBiddingMarket__WrongHourProvided(hour);
        }
        _clearMarketOnChainSort(hour);
    }

    /// @notice Clears the market with pre-sorted bid indices (gas optimized)
    /// @dev Caller provides sorted indices - O(n) verification vs O(n log n) sorting
    /// @param hour The market hour to clear
    /// @param sortedBidIndices Bid indices sorted by price descending (highest first)
    function clearMarketWithSortedBids(
        uint256 hour,
        uint256[] calldata sortedBidIndices
    ) external assertExactHour(hour) {
        if (hour + 3600 > block.timestamp) {
            revert EnergyBiddingMarket__WrongHourProvided(hour);
        }
        _clearMarketWithVerification(hour, sortedBidIndices);
    }

    /// @inheritdoc IEnergyBiddingMarket
    function clearMarketPastHour() external {
        uint256 hour = getCurrentHourTimestamp() - 3600;
        _clearMarketOnChainSort(hour);
    }

    /// @inheritdoc IEnergyBiddingMarket
    /// @dev Uses checks-effects-interactions pattern: state is updated before external call
    function claimBalance() external {
        uint256 balance = claimableBalance[msg.sender];
        if (balance == 0) {
            revert EnergyBiddingMarket__NoClaimableBalance(msg.sender);
        }

        // Effect: Update state before external call (CEI pattern)
        claimableBalance[msg.sender] = 0;

        // Interaction: External call after state update
        _transferETH(msg.sender, balance);
    }

    // ============ Admin Functions ============

    /// @inheritdoc IEnergyBiddingMarket
    function whitelistSeller(address seller, bool enable) external onlyOwner {
        if (seller == address(0)) revert EnergyBiddingMarket__InvalidSellerAddress();
        s_whitelistedSellers[seller] = enable;
        emit SellerWhitelistUpdated(seller, enable);
    }

    // ============ Internal Functions ============

    /// @notice Internal function to place a bid
    /// @param hour The market hour for the bid
    /// @param amount The amount of energy in Watts
    /// @param price The price per Watt in wei
    function _placeBid(
        uint256 hour,
        uint88 amount,
        uint88 price
    ) internal assertExactHour(hour) isMarketNotCleared(hour) {
        if (hour <= block.timestamp) {
            revert EnergyBiddingMarket__WrongHourProvided(hour);
        }
        if (price < MIN_PRICE) {
            revert EnergyBiddingMarket__BidMinimumPriceNotMet(price, MIN_PRICE);
        }

        uint256 totalBids = totalBidsByHour[hour];

        bidsByHour[hour][totalBids] = Bid({
            bidder: msg.sender,
            amount: amount,
            settled: false,
            price: price,
            canceled: false
        });

        unchecked {
            totalBidsByHour[hour] = totalBids + 1;
        }

        emit BidPlaced(msg.sender, hour, amount, price);
    }

    /// @notice Internal function to clear the market using on-chain sorting
    /// @param hour The hour to clear
    function _clearMarketOnChainSort(uint256 hour) internal isMarketNotCleared(hour) {
        // Get bids and sort indices on-chain (expensive)
        Bid[] memory bids = getBidsByHour(hour);
        uint256[] memory sortedIndices = BidSorterLib.sortedBidIndicesDescending(bids);

        uint256 sortedLength = sortedIndices.length;
        if (sortedLength == 0) {
            revert EnergyBiddingMarket__NoBidsOrAsksForThisHour(hour);
        }

        _executeClearMarket(hour, sortedIndices, bids);
    }

    /// @notice Internal function to clear the market with off-chain sorting verification
    /// @param hour The hour to clear
    /// @param sortedIndices Pre-sorted bid indices (must be verified)
    function _clearMarketWithVerification(
        uint256 hour,
        uint256[] calldata sortedIndices
    ) internal isMarketNotCleared(hour) {
        uint256 _totalBids = totalBidsByHour[hour];
        uint256 sortedLength = sortedIndices.length;

        if (sortedLength == 0) {
            revert EnergyBiddingMarket__NoBidsOrAsksForThisHour(hour);
        }

        // Verify sorting: O(n) instead of O(n log n) sorting
        // 1. Check all indices are valid and count non-canceled bids
        // 2. Verify descending price order
        uint256 nonCanceledCount;
        uint256 lastPrice = type(uint256).max;

        for (uint256 i; i < sortedLength;) {
            uint256 idx = sortedIndices[i];

            // Check index is valid
            if (idx >= _totalBids) {
                revert EnergyBiddingMarket__BidDoesNotExist(hour, idx);
            }

            Bid storage bid = bidsByHour[hour][idx];

            // Skip canceled bids in verification
            if (bid.canceled) {
                revert EnergyBiddingMarket__BidIsAlreadyCanceled(hour, idx);
            }

            // Verify descending order (price must be <= lastPrice)
            uint256 currentPrice = bid.price;
            if (currentPrice > lastPrice) {
                revert EnergyBiddingMarket__InvalidSortOrder();
            }
            lastPrice = currentPrice;

            unchecked {
                ++nonCanceledCount;
                ++i;
            }
        }

        // Verify all non-canceled bids are included
        uint256 actualNonCanceled;
        for (uint256 i; i < _totalBids;) {
            if (!bidsByHour[hour][i].canceled) {
                unchecked { ++actualNonCanceled; }
            }
            unchecked { ++i; }
        }

        if (nonCanceledCount != actualNonCanceled) {
            revert EnergyBiddingMarket__InvalidSortOrder();
        }

        // Convert calldata to memory for internal functions
        uint256[] memory sortedIndicesMem = sortedIndices;

        // Load bids into memory for clearing price calculation
        Bid[] memory bids = getBidsByHour(hour);

        _executeClearMarket(hour, sortedIndicesMem, bids);
    }

    /// @notice Executes the market clearing logic
    /// @param hour The hour to clear
    /// @param sortedIndices Verified sorted bid indices
    /// @param bids Bids array in memory
    function _executeClearMarket(
        uint256 hour,
        uint256[] memory sortedIndices,
        Bid[] memory bids
    ) private {
        // Cache storage values
        uint256 totalEnergyAvailable = totalAvailableEnergyByHour[hour];

        // Determine clearing price
        uint256 clearingPrice = _determineClearingPrice(bids, sortedIndices, totalEnergyAvailable);
        clearingPricePerHour[hour] = clearingPrice;

        // Match bids with asks
        _matchBidsWithAsks(hour, sortedIndices, totalEnergyAvailable, clearingPrice);

        isMarketCleared[hour] = true;
        emit MarketCleared(hour, clearingPrice);
    }

    /// @notice Alias for backwards compatibility
    function _clearMarket(uint256 hour) internal {
        _clearMarketOnChainSort(hour);
    }

    /// @notice Matches bids with asks and handles settlements
    /// @param hour The market hour
    /// @param sortedIndices Sorted bid indices (descending by price)
    /// @param totalEnergyAvailable Total available energy
    /// @param clearingPrice The determined clearing price
    function _matchBidsWithAsks(
        uint256 hour,
        uint256[] memory sortedIndices,
        uint256 totalEnergyAvailable,
        uint256 clearingPrice
    ) private {
        uint256 sortedLength = sortedIndices.length;
        uint256 _totalAsks = totalAsksByHour[hour];
        uint256 totalMatchedEnergy;
        uint256 fulfilledAsks;

        for (uint256 i; i < sortedLength;) {
            Bid storage bid = bidsByHour[hour][sortedIndices[i]];
            uint256 bidAmount = bid.amount;
            uint256 bidPrice = bid.price;
            uint256 remainingEnergy = totalEnergyAvailable - totalMatchedEnergy;

            // No more energy available or clearing price is 0 - refund remaining bids
            if (remainingEnergy == 0 || clearingPrice == 0) {
                _refundRemainingBids(hour, sortedIndices, i, sortedLength);
                break;
            }

            // Determine how much of this bid can be fulfilled
            uint256 fillAmount = bidAmount <= remainingEnergy ? bidAmount : remainingEnergy;

            // Match with asks
            fulfilledAsks = _matchBidWithAsks(hour, fillAmount, clearingPrice, fulfilledAsks, _totalAsks);

            // Settle bid
            bid.settled = true;

            // Calculate refunds: (unfilled portion * original price) + (filled portion * price difference)
            uint256 unfilledAmount = bidAmount - fillAmount;
            uint256 refund = (unfilledAmount * bidPrice) + (fillAmount * (bidPrice - clearingPrice));
            claimableBalance[bid.bidder] += refund;

            totalMatchedEnergy += fillAmount;

            unchecked { ++i; }
        }
    }

    /// @notice Refunds remaining bids that couldn't be fulfilled
    function _refundRemainingBids(
        uint256 hour,
        uint256[] memory sortedIndices,
        uint256 startIndex,
        uint256 endIndex
    ) private {
        for (uint256 k = startIndex; k < endIndex;) {
            Bid storage refundBid = bidsByHour[hour][sortedIndices[k]];
            claimableBalance[refundBid.bidder] += uint256(refundBid.amount) * uint256(refundBid.price);
            unchecked { ++k; }
        }
    }

    /// @notice Matches a single bid with asks
    /// @return fulfilledAsks Updated count of fulfilled asks
    function _matchBidWithAsks(
        uint256 hour,
        uint256 bidAmount,
        uint256 clearingPrice,
        uint256 fulfilledAsks,
        uint256 _totalAsks
    ) private returns (uint256) {
        uint256 totalMatchedEnergyForBid;

        for (uint256 j = fulfilledAsks; j < _totalAsks;) {
            Ask storage ask = asksByHour[hour][j];
            uint256 amountLeftInAsk = uint256(ask.amount) - uint256(ask.matchedAmount);

            if (totalMatchedEnergyForBid + amountLeftInAsk <= bidAmount) {
                // Ask fully matched
                ask.settled = true;
                ask.matchedAmount = ask.amount;
                totalMatchedEnergyForBid += amountLeftInAsk;
                claimableBalance[ask.seller] += amountLeftInAsk * clearingPrice;

                unchecked { ++fulfilledAsks; }

                if (totalMatchedEnergyForBid == bidAmount) break;
            } else {
                // Ask partially matched
                uint256 partialMatch = bidAmount - totalMatchedEnergyForBid;
                // Safe cast: matchedAmount + partialMatch <= ask.amount which is uint88
                // forge-lint: disable-next-line(unsafe-typecast)
                ask.matchedAmount = uint88(uint256(ask.matchedAmount) + partialMatch);
                claimableBalance[ask.seller] += partialMatch * clearingPrice;
                break;
            }

            unchecked { ++j; }
        }

        return fulfilledAsks;
    }

    /// @notice Determines the clearing price for a specific hour
    /// @param bids Array of bids in memory
    /// @param sortedIndices Sorted indices of valid bids (descending by price)
    /// @param totalAvailableEnergy Total available energy for the hour
    /// @return The clearing price in wei per Watt
    function _determineClearingPrice(
        Bid[] memory bids,
        uint256[] memory sortedIndices,
        uint256 totalAvailableEnergy
    ) internal pure returns (uint256) {
        // No energy available means no clearing price
        if (totalAvailableEnergy == 0) return 0;

        uint256 totalBids = sortedIndices.length;
        uint256 totalMatchedEnergy;

        for (uint256 i; i < totalBids;) {
            totalMatchedEnergy += bids[sortedIndices[i]].amount;

            if (totalMatchedEnergy > totalAvailableEnergy) {
                // This bid would exceed available energy
                // The clearing price is this bid's price (marginal bid)
                return bids[sortedIndices[i]].price;
            }

            unchecked { ++i; }
        }

        // All bids can be matched - clearing price is lowest accepted bid
        return bids[sortedIndices[totalBids - 1]].price;
    }

    /// @notice Safely transfers ETH to an address
    /// @param to The recipient address
    /// @param amount The amount to transfer
    function _transferETH(address to, uint256 amount) internal {
        (bool success,) = to.call{value: amount}("");
        if (!success) revert EnergyBiddingMarket__ETHTransferFailed();
    }

    // ============ View Functions ============

    /// @inheritdoc IEnergyBiddingMarket
    function balanceOf(address user) external view returns (uint256) {
        return claimableBalance[user];
    }

    /// @inheritdoc IEnergyBiddingMarket
    function getCurrentHourTimestamp() public view returns (uint256) {
        return (block.timestamp / 3600) * 3600;
    }

    /// @inheritdoc IEnergyBiddingMarket
    function getBidsByHour(uint256 hour) public view returns (Bid[] memory) {
        uint256 totalBids = totalBidsByHour[hour];
        Bid[] memory bids = new Bid[](totalBids);

        for (uint256 i; i < totalBids;) {
            bids[i] = bidsByHour[hour][i];
            unchecked { ++i; }
        }

        return bids;
    }

    /// @inheritdoc IEnergyBiddingMarket
    function getAsksByHour(uint256 hour) external view returns (Ask[] memory) {
        uint256 totalAsks = totalAsksByHour[hour];
        Ask[] memory asks = new Ask[](totalAsks);

        for (uint256 i; i < totalAsks;) {
            asks[i] = asksByHour[hour][i];
            unchecked { ++i; }
        }

        return asks;
    }

    /// @inheritdoc IEnergyBiddingMarket
    function getBidsByAddress(
        uint256 hour,
        address user
    ) external view returns (Bid[] memory) {
        uint256 totalBids = totalBidsByHour[hour];
        uint256 count;

        for (uint256 i; i < totalBids;) {
            if (bidsByHour[hour][i].bidder == user) {
                unchecked { ++count; }
            }
            unchecked { ++i; }
        }

        Bid[] memory userBids = new Bid[](count);
        count = 0;

        for (uint256 i; i < totalBids;) {
            if (bidsByHour[hour][i].bidder == user) {
                userBids[count] = bidsByHour[hour][i];
                unchecked { ++count; }
            }
            unchecked { ++i; }
        }

        return userBids;
    }

    /// @inheritdoc IEnergyBiddingMarket
    function getAsksByAddress(
        uint256 hour,
        address user
    ) external view returns (Ask[] memory) {
        uint256 totalAsks = totalAsksByHour[hour];
        uint256 count;

        for (uint256 i; i < totalAsks;) {
            if (asksByHour[hour][i].seller == user) {
                unchecked { ++count; }
            }
            unchecked { ++i; }
        }

        Ask[] memory userAsks = new Ask[](count);
        count = 0;

        for (uint256 i; i < totalAsks;) {
            if (asksByHour[hour][i].seller == user) {
                userAsks[count] = asksByHour[hour][i];
                unchecked { ++count; }
            }
            unchecked { ++i; }
        }

        return userAsks;
    }

    /// @inheritdoc IEnergyBiddingMarket
    function getClearingPrice(uint256 hour) external view returns (uint256) {
        return clearingPricePerHour[hour];
    }

    /// @inheritdoc IEnergyBiddingMarket
    function isSellerWhitelisted(address seller) external view returns (bool) {
        return s_whitelistedSellers[seller];
    }
}
