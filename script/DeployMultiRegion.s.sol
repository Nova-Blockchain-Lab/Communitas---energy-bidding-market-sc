// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {EnergyBiddingMarket} from "../src/EnergyBiddingMarket.sol";
import {DeployerEnergyBiddingMarket} from "./Deploy.s.sol";
import {stdJson} from "forge-std/StdJson.sol";

/// @title DeployMultiRegion
/// @notice Deploys EnergyBiddingMarket contracts for multiple regions and updates frontend config
/// @dev Deploys to multiple regions and outputs addresses to JSON config files
contract DeployMultiRegion is Script {
    uint256 constant PROD_CHAIN_ID = 421614; // Arbitrum Sepolia

    // Configuration paths - consider moving to environment variables
    string constant CONFIG_FILE = "../uniform_market_fe/uniform-market-web3modal/constants/addresses.json";
    string constant CLEAR_MARKET_BOT = "../ClearMarketBot/addresses.json";
    string constant TEST_FILE = "./test/addresses.json";

    string[5] regions = [
        "Portugal",
        "Spain",
        "Germany",
        "Greece",
        "Italy"
    ];

    using stdJson for string;

    /// @notice Deploys markets for all configured regions
    /// @return markets Array of deployed EnergyBiddingMarket contracts
    function run() public returns (EnergyBiddingMarket[] memory) {
        uint256 numberOfRegions = regions.length;
        EnergyBiddingMarket[] memory markets = new EnergyBiddingMarket[](numberOfRegions);

        string memory json;
        string memory tempjson;

        for (uint256 i; i < numberOfRegions;) {
            DeployerEnergyBiddingMarket deployer = new DeployerEnergyBiddingMarket();
            EnergyBiddingMarket market = deployer.run();
            markets[i] = market;

            console.log("Deployed EnergyBiddingMarket for", regions[i], "at:", address(market));

            tempjson = json.serialize(regions[i], address(market));

            unchecked { ++i; }
        }

        // Write config based on chain
        if (block.chainid == PROD_CHAIN_ID) {
            tempjson = tempjson.serialize(vm.toString(block.chainid), tempjson);
            tempjson.write(CONFIG_FILE);
            tempjson.write(CLEAR_MARKET_BOT);
        } else {
            tempjson.write(TEST_FILE);
        }

        return markets;
    }
}
