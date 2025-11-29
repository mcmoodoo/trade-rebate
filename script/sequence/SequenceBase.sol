// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {Deployers} from "test/utils/Deployers.sol";

/// @notice Shared base for sequence scripts. Does NOT auto-deploy infra.
abstract contract SequenceBase is Script, Deployers {
    using stdJson for string;

    struct Deployments {
        address hook;
        address token0;
        address token1;
        address permit2;
        address poolManager;
        address positionManager;
        address router;
        uint256 lpFee;      // store as uint for json convenience (e.g. 3000)
        int256 tickSpacing; // positive; stored as signed for clarity
        bytes32 poolId;     // optional, set by pool creation script
    }

    function _etch(address target, bytes memory bytecode) internal override {
        if (block.chainid == 31337) {
            vm.rpc(
                "anvil_setCode",
                string.concat('["', vm.toString(target), '",', '"', vm.toString(bytecode), '"]')
            );
        } else {
            revert("Unsupported etch on this network");
        }
    }

    function _deploymentsPath() internal view returns (string memory) {
        // Use project root deployments.json
        return string.concat(vm.projectRoot(), "/deployments.json");
    }

    function _readDeployments() internal view returns (Deployments memory d) {
        string memory path = _deploymentsPath();
        string memory json;
        // best-effort read; if missing, return zero-initialized struct
        try vm.readFile(path) returns (string memory contents) {
            json = contents;
        } catch {
            return d;
        }

        // read fields individually; ignore if missing
        try vm.parseJsonAddress(json, ".hook") returns (address v) { d.hook = v; } catch {}
        try vm.parseJsonAddress(json, ".token0") returns (address v) { d.token0 = v; } catch {}
        try vm.parseJsonAddress(json, ".token1") returns (address v) { d.token1 = v; } catch {}
        try vm.parseJsonAddress(json, ".permit2") returns (address v) { d.permit2 = v; } catch {}
        try vm.parseJsonAddress(json, ".poolManager") returns (address v) { d.poolManager = v; } catch {}
        try vm.parseJsonAddress(json, ".positionManager") returns (address v) { d.positionManager = v; } catch {}
        try vm.parseJsonAddress(json, ".router") returns (address v) { d.router = v; } catch {}
        try vm.parseJsonUint(json, ".lpFee") returns (uint256 v) { d.lpFee = v; } catch {}
        try vm.parseJsonInt(json, ".tickSpacing") returns (int256 v) { d.tickSpacing = v; } catch {}
        try vm.parseJsonBytes32(json, ".poolId") returns (bytes32 v) { d.poolId = v; } catch {}
    }

    function _writeDeployments(Deployments memory d) internal {
        string memory obj = "deployments";
        string memory json;

        json = vm.serializeAddress(obj, "hook", d.hook);
        json = vm.serializeAddress(obj, "token0", d.token0);
        json = vm.serializeAddress(obj, "token1", d.token1);
        json = vm.serializeAddress(obj, "permit2", d.permit2);
        json = vm.serializeAddress(obj, "poolManager", d.poolManager);
        json = vm.serializeAddress(obj, "positionManager", d.positionManager);
        json = vm.serializeAddress(obj, "router", d.router);
        json = vm.serializeUint(obj, "lpFee", d.lpFee);
        json = vm.serializeInt(obj, "tickSpacing", d.tickSpacing);
        json = vm.serializeBytes32(obj, "poolId", d.poolId);

        vm.writeJson(json, _deploymentsPath());
    }
}

