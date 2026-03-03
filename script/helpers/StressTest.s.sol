// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
import {EnergyBiddingMarket} from "../../src/EnergyBiddingMarket.sol";
import {DeployerEnergyBiddingMarket} from "../Deploy.s.sol";

/// @title StressTest
/// @notice Script for stress testing the EnergyBiddingMarket with many bids and asks
/// @dev Used for gas benchmarking and load testing. Run with increased gas limit.
contract StressTest is Script {
    /// @notice Runs a stress test with configurable number of bids/asks
    /// @dev Creates worst-case scenario (price ascending) for sorting
    function run() public {
        DeployerEnergyBiddingMarket deployer = new DeployerEnergyBiddingMarket();
        EnergyBiddingMarket market = deployer.run();

        uint256 correctHour = (block.timestamp / 3600) * 3600 + 3600;
        uint256 testPrice = 1e12;

        vm.startBroadcast();

        // Whitelist this contract as a seller
        market.whitelistSeller(address(this), true);

        uint256 loops = 5000;
        uint256 bidPrice = testPrice + 1e9;
        uint256 smallAskAmount = 1;
        uint256 smallBidAmount = 2;

        // Place bids in worst case scenario (price ascending)
        for (uint256 i; i < loops;) {
            uint256 randomBidAmount = smallBidAmount + (i * 2);
            market.placeBid{value: (bidPrice + i) * randomBidAmount}(correctHour, randomBidAmount);
            unchecked { ++i; }
        }

        vm.warp(correctHour + 1);

        // Place asks
        for (uint256 i; i < loops;) {
            uint256 randomAskAmount = smallAskAmount + i;
            market.placeAsk(randomAskAmount, address(this));
            unchecked { ++i; }
        }

        vm.warp(correctHour + 3600);

        // Clear the market
        market.clearMarket(correctHour);

        vm.stopBroadcast();

        console.log("Stress test completed with", loops, "bids and asks");
    }
}
