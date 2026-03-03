# Energy Bidding Market

A Solidity smart contract for decentralized energy trading using a double-auction market mechanism. Buyers place bids, whitelisted sellers place asks, and the market clears at a uniform clearing price.

## Features

- **Double-Auction Market**: Buyers bid for energy, sellers offer asks, market clears at uniform price
- **Hourly Markets**: Separate markets for each hour, enabling time-based energy trading
- **Whitelisted Sellers**: Only approved energy producers can place asks
- **Gas-Optimized**: Off-chain sorting with on-chain verification saves up to 81% gas
- **Batch Operations**: Place multiple bids/asks and clear market in single transaction
- **Upgradeable**: UUPS proxy pattern for contract upgrades

## How It Works

1. **Bidding Phase**: Buyers place bids specifying amount (Watts) and maximum price
2. **Ask Phase**: Whitelisted sellers place asks specifying energy available
3. **Market Clearing**: Bids sorted by price (highest first), matched with asks until supply exhausted
4. **Settlement**: All matched trades execute at the clearing price (lowest matched bid price)
5. **Refunds**: Bidders who bid above clearing price get automatic refunds

## Installation

```bash
# Clone the repository
git clone <repository-url>
cd Communitas---energy-bidding-market-sc

# Install dependencies
forge install

# Copy environment file
cp .env.example .env
# Edit .env with your API keys
```

## Build & Test

```bash
# Build
forge build

# Run all tests (128 tests)
forge test

# Run with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/unit/PlaceBid.t.sol

# Gas report
forge test --gas-report
```

## Deployment

```bash
# Deploy to local anvil
anvil &
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy to testnet (e.g., Sepolia)
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
```

## Usage

### For Buyers

```solidity
// Place a single bid for 1000 Watts
market.placeBid{value: pricePerWatt * 1000}(hour, 1000);

// Place bids for multiple hours (range)
market.placeMultipleBids{value: totalValue}(startHour, endHour, amount);

// Place bids for specific hours (array)
uint256[] memory hours = new uint256[](3);
hours[0] = hour1;
hours[1] = hour2;
hours[2] = hour3;
market.placeMultipleBids{value: totalValue}(hours, amount);

// Cancel a bid (before market clears)
market.cancelBid(hour, bidIndex);

// Claim refunds/balance
market.claimBalance();
```

### For Sellers (Whitelisted)

```solidity
// Place an ask for 5000 Watts
market.placeAsk(5000, receiverAddress);

// Batch: place asks and clear market with off-chain sorted indices
AskInput[] memory asks = new AskInput[](2);
asks[0] = AskInput(receiver1, 3000);
asks[1] = AskInput(receiver2, 2000);
market.placeAsksAndClearMarket(hour, asks, sortedBidIndices);
```

### For Anyone

```solidity
// Clear market (on-chain sorting)
market.clearMarket(hour);

// Clear market (off-chain sorting - recommended)
market.clearMarketWithSortedBids(hour, sortedBidIndices);

// Clear past hour
market.clearMarketPastHour();
```

### Off-Chain Sorting (JavaScript)

```javascript
// Get bids and sort by price descending
const bids = await market.getBidsByHour(hour);
const sortedIndices = bids
    .map((bid, index) => ({ index, price: bid.price, canceled: bid.canceled }))
    .filter(b => !b.canceled)
    .sort((a, b) => Number(b.price) - Number(a.price))
    .map(b => b.index);

// Submit pre-sorted indices
await market.clearMarketWithSortedBids(hour, sortedIndices);
```

## Project Structure

```
src/
├── EnergyBiddingMarket.sol          # Main contract
├── interfaces/
│   └── IEnergyBiddingMarket.sol     # Complete interface
├── libraries/
│   └── BidSorterLib.sol             # Sorting library
└── types/
    └── MarketTypes.sol              # Structs & errors

script/
├── Deploy.s.sol                     # Deployment script
├── DeployMultiRegion.s.sol          # Multi-region deployment
└── helpers/
    └── StressTest.s.sol             # Stress testing

test/
├── BaseTest.t.sol                   # Shared test setup
├── EnergyBiddingMarketTest.t.sol    # Main tests (50 tests)
├── unit/                            # Unit tests
│   ├── PlaceBid.t.sol
│   ├── PlaceAsk.t.sol
│   ├── ClearMarket.t.sol
│   ├── CancelBid.t.sol
│   ├── WhitelistSeller.t.sol
│   └── BatchOperations.t.sol
├── integration/
│   └── FullMarketCycle.t.sol        # End-to-end tests
├── fuzz/
│   └── PriceCalculation.t.sol       # Fuzz tests
└── invariants/
    └── MarketInvariants.t.sol       # Invariant tests
```

## Gas Optimizations

### Off-Chain Sorting

| Scenario | On-Chain Sort | Off-Chain + Verify | Savings |
|----------|---------------|-------------------|---------|
| 10 bids | ~50,000 | ~30,000 | 40% |
| 100 bids | ~500,000 | ~150,000 | 70% |
| 1000 bids | ~8,000,000 | ~1,500,000 | 81% |

### Struct Packing

```solidity
// Optimized: 2 storage slots (was 3)
struct Bid {
    address bidder;   // 20 bytes
    uint88 amount;    // 11 bytes
    bool settled;     // 1 byte
    uint88 price;     // 11 bytes
    bool canceled;    // 1 byte
}
```

Saves ~20,000 gas per bid/ask.

## Key Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `uint88 max` | ~3.09e26 | Max amount/price value |

## Security

- **Reentrancy Protection**: Checks-effects-interactions pattern
- **Access Control**: Owner-only admin functions, whitelisted sellers
- **Input Validation**: Hour validation, minimum price checks
- **Off-Chain Verification**: O(n) verification of sorted indices

## Test Coverage

- **128 tests** passing
- Unit, integration, fuzz, and invariant tests
- Key invariants verified:
  - Contract solvency (balance >= claimable)
  - Cleared markets stay cleared
  - Canceled bids never settled
  - Settled bids never canceled

## License

MIT
