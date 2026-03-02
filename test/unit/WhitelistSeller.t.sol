// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IEnergyBiddingMarket} from "../../src/interfaces/IEnergyBiddingMarket.sol";

/// @title WhitelistSeller Unit Tests
/// @notice Tests for seller whitelist management
contract WhitelistSellerTest is BaseTest {
    function test_whitelistSeller_Success() public {
        address newSeller = makeAddr("newSeller");

        assertFalse(market.whitelistedSellers(newSeller));

        market.whitelistSeller(newSeller, true);

        assertTrue(market.whitelistedSellers(newSeller));
    }

    function test_whitelistSeller_OnlyOwner() public {
        address newSeller = makeAddr("newSeller");

        vm.prank(BIDDER);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                BIDDER
            )
        );
        market.whitelistSeller(newSeller, true);
    }

    function test_whitelistSeller_Disable() public {
        assertTrue(market.whitelistedSellers(SELLER));

        market.whitelistSeller(SELLER, false);

        assertFalse(market.whitelistedSellers(SELLER));
    }

    function test_whitelistSeller_MultipleAddresses() public {
        address seller1 = makeAddr("seller1");
        address seller2 = makeAddr("seller2");
        address seller3 = makeAddr("seller3");

        market.whitelistSeller(seller1, true);
        market.whitelistSeller(seller2, true);
        market.whitelistSeller(seller3, true);

        assertTrue(market.whitelistedSellers(seller1));
        assertTrue(market.whitelistedSellers(seller2));
        assertTrue(market.whitelistedSellers(seller3));

        // Disable one
        market.whitelistSeller(seller2, false);

        assertTrue(market.whitelistedSellers(seller1));
        assertFalse(market.whitelistedSellers(seller2));
        assertTrue(market.whitelistedSellers(seller3));
    }

    function test_whitelistSeller_EmitsEvent() public {
        address newSeller = makeAddr("newSeller");

        vm.expectEmit(true, false, false, true);
        emit IEnergyBiddingMarket.SellerWhitelistUpdated(newSeller, true);

        market.whitelistSeller(newSeller, true);
    }
}
