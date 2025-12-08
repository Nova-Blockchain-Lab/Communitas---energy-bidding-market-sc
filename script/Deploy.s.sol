// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {EnergyBiddingMarket} from "../src/EnergyBiddingMarket.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/// @title DeployerEnergyBiddingMarket
/// @notice Deployment script for the EnergyBiddingMarket contract with UUPS proxy
/// @dev Deploy with: forge script ./script/EnergyBiddingMarket.s.sol --rpc-url <RPC_URL> --broadcast --private-key <PRIVATE_KEY>
contract DeployerEnergyBiddingMarket is Script {
    function run() public returns (EnergyBiddingMarket) {
        vm.startBroadcast();

        // Deploy the UUPS proxy with the implementation
        address proxy = Upgrades.deployUUPSProxy(
            "EnergyBiddingMarket.sol:EnergyBiddingMarket",
            abi.encodeWithSignature("initialize(address)", msg.sender)
        );

        console.log("EnergyBiddingMarket deployed at:", proxy);

        vm.stopBroadcast();

        return EnergyBiddingMarket(proxy);
    }
}
