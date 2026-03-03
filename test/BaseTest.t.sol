// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EnergyBiddingMarket} from "../src/EnergyBiddingMarket.sol";
import {BidSorterLib} from "../src/libraries/BidSorterLib.sol";
import {Bid, AskInput} from "../src/types/MarketTypes.sol";
import {DeployerEnergyBiddingMarket} from "../script/Deploy.s.sol";

/// @title BaseTest
/// @notice Base test contract with shared setup and helper functions
abstract contract BaseTest is Test {
    address internal BIDDER = makeAddr("bidder");
    address internal ASKER = makeAddr("asker");
    address internal SELLER = makeAddr("seller");
    address internal RECEIVER1 = makeAddr("receiver1");
    address internal RECEIVER2 = makeAddr("receiver2");
    address internal OWNER;

    EnergyBiddingMarket internal market;
    uint256 internal correctHour;
    uint256 internal askHour;
    uint256 internal clearHour;
    /// @notice Default test price per Watt for bid tests (1e12 wei/Watt).
    uint256 internal testPrice;
    uint256 internal defaultTestPrice = 1e12;
    uint256 internal bidAmount;

    function setUp() public virtual {
        DeployerEnergyBiddingMarket deployer = new DeployerEnergyBiddingMarket();
        market = deployer.run();

        OWNER = address(this);

        correctHour = (block.timestamp / 3600) * 3600 + 3600;
        askHour = correctHour + 1;
        clearHour = askHour + 3600;
        testPrice = defaultTestPrice;
        bidAmount = 100;

        vm.deal(address(0xBEEF), 1000 ether);
        vm.deal(BIDDER, 100 ether);
        vm.deal(ASKER, 100 ether);
        vm.deal(SELLER, 100 ether);

        // Whitelist the seller for tests
        market.whitelistSeller(SELLER, true);
    }

    /// @notice Helper to get sorted bid indices for off-chain sorting tests
    function getSortedBidIndices(uint256 hour) internal view returns (uint256[] memory) {
        Bid[] memory bids = market.getBidsByHour(hour);
        return BidSorterLib.sortedBidIndicesDescending(bids);
    }

    /// @notice Helper to create AskInput array
    function createAskInputs(
        address[] memory receivers,
        uint88[] memory amounts
    ) internal pure returns (AskInput[] memory) {
        require(receivers.length == amounts.length, "Length mismatch");
        AskInput[] memory asks = new AskInput[](receivers.length);
        for (uint256 i; i < receivers.length; i++) {
            asks[i] = AskInput({receiver: receivers[i], amount: amounts[i]});
        }
        return asks;
    }
}
