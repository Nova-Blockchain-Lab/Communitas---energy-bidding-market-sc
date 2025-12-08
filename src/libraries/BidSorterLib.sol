// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Bid} from "../types/MarketTypes.sol";

/// @title BidSorterLib
/// @notice Library for sorting bids by price in descending order
/// @dev Uses quicksort algorithm optimized for on-chain execution
library BidSorterLib {
    /// @notice Returns indices of non-canceled bids sorted by descending price
    /// @param bids List of Bid structs in memory
    /// @return indices Sorted indices of valid bids (non-canceled, high to low price)
    function sortedBidIndicesDescending(
        Bid[] memory bids
    ) internal pure returns (uint256[] memory indices) {
        uint256 bidsLength = bids.length;
        uint256 validCount;

        // Count valid (non-canceled) bids
        for (uint256 i; i < bidsLength;) {
            if (!bids[i].canceled) {
                unchecked { ++validCount; }
            }
            unchecked { ++i; }
        }

        // Create array of valid indices
        indices = new uint256[](validCount);
        uint256 j;
        for (uint256 i; i < bidsLength;) {
            if (!bids[i].canceled) {
                indices[j] = i;
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }

        // Sort if more than one valid bid
        if (validCount > 1) {
            // Safe cast: validCount is bounded by array length which fits in int256
            // forge-lint: disable-next-line(unsafe-typecast)
            _quickSort(bids, indices, 0, int256(validCount - 1));
        }

        return indices;
    }

    /// @notice QuickSort implementation for sorting bid indices by price (descending)
    /// @param bids The array of bids to reference for prices
    /// @param indices The array of indices to sort
    /// @param left Left boundary of the partition
    /// @param right Right boundary of the partition
    function _quickSort(
        Bid[] memory bids,
        uint256[] memory indices,
        int256 left,
        int256 right
    ) private pure {
        if (left >= right) return;

        int256 i = left;
        int256 j = right;

        // Use middle element as pivot for better average case
        // Safe cast: left >= 0 and right >= left at this point, so result is non-negative
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 pivotIndex = indices[uint256(left + (right - left) / 2)];
        uint256 pivotPrice = bids[pivotIndex].price;

        while (i <= j) {
            // Find element on left that should be on right (smaller than pivot for descending)
            // Safe cast: i starts at left (>= 0) and only increments
            // forge-lint: disable-next-line(unsafe-typecast)
            while (bids[indices[uint256(i)]].price > pivotPrice) {
                unchecked { ++i; }
            }
            // Find element on right that should be on left (larger than pivot for descending)
            // Safe cast: j starts at right (>= 0) and stays >= 0 while in loop (i <= j)
            // forge-lint: disable-next-line(unsafe-typecast)
            while (bids[indices[uint256(j)]].price < pivotPrice) {
                unchecked { --j; }
            }

            if (i <= j) {
                // Swap elements (safe casts: i and j are non-negative when i <= j)
                // forge-lint: disable-next-line(unsafe-typecast)
                (indices[uint256(i)], indices[uint256(j)]) = (
                    indices[uint256(j)],
                    indices[uint256(i)]
                );
                unchecked {
                    ++i;
                    --j;
                }
            }
        }

        // Recursively sort partitions
        if (left < j) _quickSort(bids, indices, left, j);
        if (i < right) _quickSort(bids, indices, i, right);
    }
}
