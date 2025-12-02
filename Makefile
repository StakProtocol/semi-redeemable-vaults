-include .env

.PHONY: all build test testv clean fmt snapshot install update coverage

all: build

build:
	forge build

test:
	forge test

testv:
	forge test -vvvv

clean:
	forge clean

fmt:
	forge fmt

snapshot:
	forge snapshot

install:
	forge soldeer install

update:
	forge soldeer update

coverage:
	forge coverage



# snapshot :; forge snapshot
# format :; forge fmt

# deploy:
# 	@forge script script/DeployOurToken.s.sol:DeployOurToken --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

# deploy-sepolia:
# 	@forge script script/DeployOurToken.s.sol:DeployOurToken --rpc-url $(SEPOLIA_RPC_URL) --account $(ACCOUNT) --sender $(SENDER) --etherscan-api-key $(ETHERSCAN_API_KEY) --broadcast --verify

# verify:
# 	@forge verify-contract --chain-id 11155111 --num-of-optimizations 200 --watch --constructor-args 0x00000000000000000000000000000000000000000000d3c21bcecceda1000000 --etherscan-api-key $(ETHERSCAN_API_KEY) --compiler-version v0.8.19+commit.7dd6d404 0x089dc24123e0a27d44282a1ccc2fd815989e3300 src/OurToken.sol:OurToken
