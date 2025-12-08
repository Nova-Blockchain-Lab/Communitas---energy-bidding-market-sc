-include .env

.PHONY: install build test deploy-arbitrum-sepolia clean fmt snapshot

install:
	forge install foundry-rs/forge-std --no-git
	forge install openzeppelin/openzeppelin-contracts --no-git
	forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-git
	forge install OpenZeppelin/openzeppelin-foundry-upgrades --no-git

build:
	forge build

test:
	forge test -vvv

test-gas:
	forge test --gas-report

clean:
	forge clean

fmt:
	forge fmt

snapshot:
	forge snapshot

# Deployment commands - use environment variables for security
# Required env vars: PRIVATE_KEY, ALCHEMY_KEY, ETHERSCAN_API_KEY
deploy-arbitrum-sepolia:
	@if [ -z "$(PRIVATE_KEY)" ]; then echo "Error: PRIVATE_KEY not set"; exit 1; fi
	@if [ -z "$(ALCHEMY_KEY)" ]; then echo "Error: ALCHEMY_KEY not set"; exit 1; fi
	forge script ./script/EnergyBiddingMarket.s.sol \
		--rpc-url https://arb-sepolia.g.alchemy.com/v2/$(ALCHEMY_KEY) \
		--broadcast \
		--private-key $(PRIVATE_KEY) \
		--verify

deploy-multi-region:
	@if [ -z "$(PRIVATE_KEY)" ]; then echo "Error: PRIVATE_KEY not set"; exit 1; fi
	@if [ -z "$(ALCHEMY_KEY)" ]; then echo "Error: ALCHEMY_KEY not set"; exit 1; fi
	forge script ./script/DeployAndUpdateFE.s.sol \
		--rpc-url https://arb-sepolia.g.alchemy.com/v2/$(ALCHEMY_KEY) \
		--broadcast \
		--private-key $(PRIVATE_KEY) \
		--verify
