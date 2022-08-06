-include .env
export

SCRIPT_DIR = ./script

build:
	forge build
rebuild: clean build
clean:
	forge clean
install: init
init:
	git submodule update --init --recursive
	forge install
test:
	forge test -v
trace:
	forge test -vvvv 
remappings:
	forge remappings > remappings.txt
deploy-simulation:
	$(foreach file, $(wildcard $(SCRIPT_DIR)/*.s.sol), \
		echo "Simulating $(file)..."; \
		forge script $(file) --rpc-url $(rpc) -vvvv; \
	)
deploy:
	$(foreach file, $(wildcard $(SCRIPT_DIR)/*.s.sol), \
		echo "Running $(file)..."; \
		forge script $(file) --rpc-url $(rpc) --private-key $(pk) --broadcast --verify --etherscan-api-key $(etherscan_key) -vvvv; \
	)
deploy-resume:
	$(foreach file, $(wildcard $(SCRIPT_DIR)/*.s.sol), \
		echo "Resuming $(file)..."; \
		forge script $(file) --rpc-url $(rpc) --private-key $(pk) --resume --verify --etherscan-api-key $(etherscan_key) -vvvv; \
	)

playground: FOUNDRY_TEST:=playground
playground:
	forge test --match-path playground/Playground.t.sol -vvvv --gas-report

## Mainnet
mainnet-deploy-simulation: rpc:=${MAINNET_RPC_URL}
mainnet-deploy-simulation: deploy-simulation
mainnet-deploy: rpc:=${MAINNET_RPC_URL}
mainnet-deploy: pk:=${PRIVATE_KEY}
mainnet-deploy: etherscan_key:=${MAINNET_ETHERSCAN_KEY}
mainnet-deploy: deploy
mainnet-deploy-resume: rpc:=${MAINNET_RPC_URL}
mainnet-deploy-resume: pk:=${PRIVATE_KEY}
mainnet-deploy-resume: etherscan_key:=${MAINNET_ETHERSCAN_KEY}
mainnet-deploy-resume: deploy-resume

## Avalanche
avalanche-deploy-simulation: rpc:=${AVALANCHE_RPC_URL}
avalanche-deploy-simulation: deploy-simulation
avalanche-deploy: rpc:=${AVALANCHE_RPC_URL}
avalanche-deploy: pk:=${PRIVATE_KEY}
avalanche-deploy: etherscan_key:=${SNOWTRACE_ETHERSCAN_KEY}
avalanche-deploy: deploy
avalanche-deploy-resume: rpc:=${AVALANCHE_RPC_URL}
avalanche-deploy-resume: pk:=${PRIVATE_KEY}
avalanche-deploy-resume: etherscan_key:=${SNOWTRACE_ETHERSCAN_KEY}
avalanche-deploy-resume: deploy-resume

## Optimism
optimism-deploy-simulation: rpc:=${OPTIMISM_RPC_URL}
optimism-deploy-simulation: deploy-simulation
optimism-deploy: rpc:=${OPTIMISM_RPC_URL}
optimism-deploy: pk:=${PRIVATE_KEY}
optimism-deploy: etherscan_key:=${OPTIMISM_ETHERSCAN_KEY}
optimism-deploy: deploy
optimism-deploy-resume: rpc:=${OPTIMISM_RPC_URL}
optimism-deploy-resume: pk:=${PRIVATE_KEY}
optimism-deploy-resume: etherscan_key:=${OPTIMISM_ETHERSCAN_KEY}
optimism-deploy-resume: deploy-resume

.PHONY: test playground
.SILENT: deploy-simulation deploy deploy-resume