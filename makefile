# Makefile

.PHONY: run

# run these commands while cd'd into root 

# runs echidna in fork testing mode using an rpc url and block specified in the .env file 
echidna-fork:
	@set -a; . ./.env; set +a; \
	ECHIDNA_RPC_URL=$$MAINNET_RPC_URL ECHIDNA_RPC_BLOCK=$$FORK_FROM_BLOCK echidna . --contract CryticForkTester --config echidna.yaml

# runs echidna in local testing mode where setup uses local deployment of system contracts
echidna-local: 
	echidna . --contract CryticTester --config echidna.yaml

# runs medusa in local testing mode where setup uses local deployment of system contracts
medusa-local:
	medusa fuzz

# runs reproducers for local deployment fuzz tests
foundry-reproducers-local:
	forge test --mc CryticToFoundry

# runs reproducers for forked deployment fuzz tests
foundry-reproducers-fork:
	forge test --mc CryticToForkFoundry