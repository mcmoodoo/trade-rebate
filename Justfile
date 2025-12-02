set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# Defaults (override via environment if desired)
rpc_url := env("RPC_URL", "http://127.0.0.1:8545")
private_key := env("ANVIL_PRIVATE_KEY", "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80")

default:
    @just --list

check-env:
    echo "RPC_URL={{rpc_url}}"
    echo "PRIVATE_KEY={{private_key}}"

# Start local Anvil node for Blockscout (bind to all interfaces)
anvil-local:
    anvil --host 0.0.0.0 --port 8545 --fork-url $INFURA_ARBITRUM_MAINNET_RPC

# Bring up Blockscout (API + Frontend) stack
blockscout-up:
    # Ensure latest images and apply env changes (ANVIL_IP_ADDR) by recreating
    docker compose -f blockscout/docker-compose.yml up -d --force-recreate anvil blockscout blockscout-frontend

# Tear down Blockscout stack and remove volumes
blockscout-down:
    docker compose -f blockscout/docker-compose.yml down -v

# Quick connectivity check to Anvil JSON-RPC
blockscout-probe:
    curl -sS -X POST -H 'Content-Type: application/json' \
      --data '{"jsonrpc":"2.0","id":1,"method":"web3_clientVersion","params":[]}' \
      http://127.0.0.1:8545 || true

# Open the Blockscout UI
blockscout-open:
    xdg-open http://localhost:3000 >/dev/null 2>&1 || true
deploy-infra: check-env
    forge script script/sequence/DeployV4Infra.s.sol:DeployV4Infra --broadcast --rpc-url "{{rpc_url}}" --private-key "{{private_key}}"

deploy-tokens: check-env
    forge script script/sequence/DeployTokens.s.sol:DeployTokens --broadcast --rpc-url "{{rpc_url}}" --private-key "{{private_key}}"

deploy-hook: check-env
    forge script script/sequence/DeployHook.s.sol:DeployHook --broadcast --rpc-url "{{rpc_url}}" --private-key "{{private_key}}"

create-pool: check-env
    forge script script/sequence/CreatePool.s.sol:CreatePool --broadcast --rpc-url "{{rpc_url}}" --private-key "{{private_key}}" -vvvv

add-liquidity: check-env
    forge script script/sequence/AddLiquidity.s.sol:AddLiquidity --broadcast --rpc-url "{{rpc_url}}" --private-key "{{private_key}}"

# Run the full sequence in order
seq-all: check-env
    just deploy-infra
    # just deploy-tokens
    just deploy-hook
    just create-pool
    just swap-eth-usdc
    just add-liquidity
    just wrap-eth
    just prefund-deep-amm

# Inspect PositionManager-related state. Optionally set OWNER or rely on OWNER_PK from private_key.
describe-pm: check-env
    OWNER_PK="{{private_key}}" forge script script/sequence/DescribePositionManager.s.sol:DescribePositionManager --rpc-url "{{rpc_url}}"

# Swap 5 ETH -> USDC on Unichain via v4 router (router read from deployments.json)
# Optional env overrides: AMOUNT_OUT_MIN, RECEIVER, FEE, TICK_SPACING
swap-eth-usdc: check-env
    forge script script/SwapETHToUSDC_Unichain.s.sol:SwapETHToUSDC_Unichain --broadcast --rpc-url "{{rpc_url}}" --private-key "{{private_key}}" -vvvv

my-usdc-balance: check-env
    cast call 0x078D782b760474a361dDA0AF3839290b0EF57AD6 "balanceOf(address)(uint256)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

# Swap ETH -> USDC using sequence script reading deployments.json
# Optional env overrides: AMOUNT_IN_WEI, AMOUNT_OUT_MIN, RECEIVER
swap-eth-usdc-my-pool: check-env
    forge script script/sequence/SwapETHToUSDC.s.sol:SwapETHToUSDC --broadcast --rpc-url "{{rpc_url}}" --private-key "{{private_key}}" -vvvv

# Describe current pool state and positions from deployments.json
describe-pool: check-env
    forge script script/sequence/DescribePool.s.sol:DescribePool --rpc-url "{{rpc_url}}" -vvvv

# Run a 1 WETH flash loan on Aave v3 Arbitrum and repay in-tx
flashloan-aave: check-env
    forge script script/FlashLoanAaveV3.s.sol:FlashLoanAaveV3 --broadcast --rpc-url "{{rpc_url}}" --private-key "{{private_key}}" -vvvv

# Wrap ETH into WETH (defaults to 10 ETH)
wrap-eth amount_wei="10000000000000000000": check-env
    WRAP_AMOUNT_WEI="{{amount_wei}}" forge script script/WrapETH.s.sol:WrapETH --broadcast --rpc-url "{{rpc_url}}" --private-key "{{private_key}}" -vvvv

# Query WETH balance (defaults to anvil's first default address)
weth-balance owner="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266": check-env
    cast call 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1 "balanceOf(address)(uint256)" "{{owner}}" --rpc-url "{{rpc_url}}"

# Prefund DeepAmmMock so it can pay out during arb
# Params:
# - deep: address of DeepAmmMock
# - weth_wei: WETH amount to fund (wraps ETH), default 1 WETH
# - usdc: USDC amount (6 decimals), default 100_000_000 (100 USDC)
prefund-deep-amm deep="" weth_wei="1000000000000000000" usdc="100000000": check-env
    DEEP_AMM="{{deep}}" FUND_WETH_WEI="{{weth_wei}}" FUND_USDC="{{usdc}}" forge script script/sequence/PrefundDeepAmm.s.sol:PrefundDeepAmm --broadcast --rpc-url "{{rpc_url}}" --private-key "{{private_key}}" -vvvv
