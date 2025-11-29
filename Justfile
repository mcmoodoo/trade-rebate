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
    forge script script/sequence/DeployV4InfraToJson.s.sol:DeployV4InfraToJson --broadcast --rpc-url "{{rpc_url}}" --private-key "{{private_key}}"

deploy-tokens: check-env
    forge script script/sequence/DeployTokensToJson.s.sol:DeployTokensToJson --broadcast --rpc-url "{{rpc_url}}" --private-key "{{private_key}}"

deploy-hook: check-env
    forge script script/sequence/DeployHookToJson.s.sol:DeployHookToJson --broadcast --rpc-url "{{rpc_url}}" --private-key "{{private_key}}"

create-pool: check-env
    forge script script/sequence/CreatePoolFromJson.s.sol:CreatePoolFromJson --broadcast --rpc-url "{{rpc_url}}" --private-key "{{private_key}}"

add-liquidity: check-env
    forge script script/sequence/AddLiquidityFromJson.s.sol:AddLiquidityFromJson --broadcast --rpc-url "{{rpc_url}}" --private-key "{{private_key}}"

# Run the full sequence in order
seq-all: check-env
    just deploy-infra
    just deploy-tokens
    just deploy-hook
    just create-pool
    just add-liquidity
