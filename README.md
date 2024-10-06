# staked-ebtc

Fork Foundry
forge test --match-contract CryticToForkFoundry --rpc-url https://mainnet.infura.io/v3/5df425b97c6c4e1aad561cb15814303c

Fork Echidna
nohup anvil --hardfork cancun -f https://eth-mainnet.g.alchemy.com/v2/ST0ZewmedZBEsMSxL96YZAhkpCcXOLCC > /dev/null 2>&1 & ANVIL_PID=$!; echidna . --contract CryticForkTester --test-mode assertion --rpc-url http://127.0.0.1:8545 --config echidna.yaml --test-limit 100000 --workers 15; kill $ANVIL_PID


