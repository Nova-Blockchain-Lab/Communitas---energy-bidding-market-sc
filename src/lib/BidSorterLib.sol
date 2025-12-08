// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EnergyBiddingMarket} from "../EnergyBiddingMarket.sol";

library BidSorterLib {
    using BidSorterLib for EnergyBiddingMarket.Bid[];

    /// @notice Returns indices of non-canceled bids sorted by descending price
    /// @param bids List of Bid structs in memory
    /// @return indices Sorted indices of valid bids (non-canceled, high to low)
    function sortedBidIndicesDescending(
        EnergyBiddingMarket.Bid[] memory bids
    ) internal pure returns (uint[] memory indices) {
        uint256 validCount = 0;
        for (uint256 i = 0; i < bids.length; i++) {
            if (!bids[i].canceled) validCount++;
        }

        indices = new uint[](validCount);
        uint256 j = 0;
        for (uint256 i = 0; i < bids.length; i++) {
            if (!bids[i].canceled) {
                indices[j] = i;
                j++;
            }
        }

        if (validCount > 1) {
            _quickSort(bids, indices, 0, int256(validCount - 1));
        }

        return indices;
    }

    function _quickSort(
        EnergyBiddingMarket.Bid[] memory bids,
        uint[] memory indices,
        int256 left,
        int256 right
    ) private pure {
        int256 i = left;
        int256 j = right;
        if (i >= j) return;

        uint256 pivotIndex = indices[uint256(left + (right - left) / 2)];
        uint256 pivotPrice = bids[pivotIndex].price;

        while (i <= j) {
            while (bids[indices[uint256(i)]].price > pivotPrice) i++;
            while (bids[indices[uint256(j)]].price < pivotPrice) j--;

            if (i <= j) {
                (indices[uint256(i)], indices[uint256(j)]) = (
                    indices[uint256(j)],
                    indices[uint256(i)]
                );
                i++;
                j--;
            }
        }

        if (left < j) _quickSort(bids, indices, left, j);
        if (i < right) _quickSort(bids, indices, i, right);
    }
}
