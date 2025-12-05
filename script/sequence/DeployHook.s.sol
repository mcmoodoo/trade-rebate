// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {SequenceBase} from "./SequenceBase.sol";
import {TradeRebate} from "../../src/TradeRebate.sol";

/// @notice Mines and deploys the Counter hook; saves address to deployments.json
contract DeployHook is SequenceBase {
    function run() external {
        Deployments memory d = _readDeployments();
        require(d.poolManager != address(0), "PoolManager not deployed");

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

        vm.startBroadcast();
        // Mine the hook address for constructor args
        bytes memory args = abi.encode(IPoolManager(d.poolManager));
        (address expected, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(TradeRebate).creationCode, args);
        TradeRebate counter = new TradeRebate{salt: salt}(IPoolManager(d.poolManager));
        vm.stopBroadcast();

        require(address(counter) == expected, "Deployed hook address mismatch");

        d.hook = address(counter);
        _writeDeployments(d);
    }
}

