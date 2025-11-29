// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SequenceBase} from "./SequenceBase.sol";
import {console2} from "forge-std/Script.sol";

import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

/// @notice Read-only summary of PositionManager-related state using deployments.json.
contract DescribePositionManager is SequenceBase {
    using PoolIdLibrary for PoolKey;

    function run() external {
        Deployments memory d = _readDeployments();

        // Resolve the owner address (who approved & funded)
        address owner;
        try vm.envAddress("OWNER") returns (address a) {
            owner = a;
        } catch {}
        if (owner == address(0)) {
            try vm.envBytes32("OWNER_PK") returns (bytes32 pk) {
                owner = vm.addr(uint256(pk));
            } catch {}
        }
        if (owner == address(0)) {
            address[] memory wallets = vm.getWallets();
            if (wallets.length > 0) owner = wallets[0];
        }

        // Compose the pool key to recompute PoolId for reference
        Currency c0 = Currency.wrap(d.token0);
        Currency c1 = Currency.wrap(d.token1);
        if (c1 < c0) (c0, c1) = (c1, c0);
        PoolKey memory poolKey = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: uint24(d.lpFee),
            tickSpacing: int24(d.tickSpacing),
            hooks: IHooks(d.hook)
        });
        bytes32 computedPoolId = PoolId.unwrap(poolKey.toId());

        console2.log("--- PositionManager State ---");
        console2.log("PositionManager:", d.positionManager);
        console2.log("PoolManager    :", d.poolManager);
        console2.log("Permit2        :", d.permit2);
        console2.log("Router         :", d.router);
        console2.log("Hook           :", d.hook);
        console2.log("Token0         :", d.token0);
        console2.log("Token1         :", d.token1);
        console2.log("lpFee          :", d.lpFee);
        console2.log("tickSpacing    :", int24(d.tickSpacing));
        console2.log("poolId (json)  :");
        console2.logBytes32(d.poolId);
        console2.log("poolId (calc)  :");
        console2.logBytes32(computedPoolId);
        console2.log("Owner          :", owner);

        // Permit2 allowances for PositionManager
        if (owner != address(0) && d.permit2 != address(0)) {
            (uint160 a0, uint48 e0, uint48 n0) = IPermit2(d.permit2).allowance(owner, d.token0, d.positionManager);
            (uint160 a1, uint48 e1, uint48 n1) = IPermit2(d.permit2).allowance(owner, d.token1, d.positionManager);
            console2.log("--- Permit2 allowances for PositionManager ---");
            console2.log("token0 amount :", uint256(a0));
            console2.log("token0 expiry :", uint256(e0));
            console2.log("token0 nonce  :", uint256(n0));
            console2.log("token1 amount :", uint256(a1));
            console2.log("token1 expiry :", uint256(e1));
            console2.log("token1 nonce  :", uint256(n1));
        }
    }
}

