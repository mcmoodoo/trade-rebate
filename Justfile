set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# Defaults (override via environment if desired)
rpc_url := env("RPC_URL", "http://127.0.0.1:8545")
private_key := env("ANVIL_PRIVATE_KEY", "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80")

default:
    @just --list

check-env:
    echo "RPC_URL={{rpc_url}}"
    echo "PRIVATE_KEY={{private_key}}"

deploy-infra: check-env
    forge script script/sequence/DeployV4Infra.s.sol:DeployV4Infra --broadcast --rpc-url "{{rpc_url}}" --private-key "{{private_key}}"

deploy-tokens: check-env
    forge script script/sequence/DeployTokens.s.sol:DeployTokens --broadcast --rpc-url "{{rpc_url}}" --private-key "{{private_key}}"

deploy-hook: check-env
    forge script script/sequence/DeployHook.s.sol:DeployHook --broadcast --rpc-url "{{rpc_url}}" --private-key "{{private_key}}"

create-pool: check-env
    forge script script/sequence/CreatePool.s.sol:CreatePoolFromJson --broadcast --rpc-url "{{rpc_url}}" --private-key "{{private_key}}"

add-liquidity: check-env
    forge script script/sequence/AddLiquidity.s.sol:AddLiquidityFromJson --broadcast --rpc-url "{{rpc_url}}" --private-key "{{private_key}}"

# Run the full sequence in order
seq-all: check-env
    just deploy-infra
    just deploy-tokens
    just deploy-hook
    just create-pool
    just add-liquidity

# Inspect PositionManager-related state. Optionally set OWNER or rely on OWNER_PK from private_key.
describe-pm: check-env
    OWNER_PK="{{private_key}}" forge script script/sequence/DescribePositionManager.s.sol:DescribePositionManager --rpc-url "{{rpc_url}}"
