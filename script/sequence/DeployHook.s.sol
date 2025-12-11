// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {SequenceBase} from "./SequenceBase.sol";
import {GatedTradeRebateHook} from "../../src/GatedTradeRebateHook.sol";
import {BarterNFT} from "../../src/BarterNFT.sol";
import {IBarterNFT} from "../../src/IBarterNFT.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

/// @notice Mines and deploys the Gated Trade Rebate hook with BarterNFT; saves address to deployments.json
contract DeployHook is SequenceBase {
    function run() external {
        Deployments memory d = _readDeployments();
        require(d.poolManager != address(0), "PoolManager not deployed");

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);

        vm.startBroadcast();
        
        // Deploy BarterNFT first
        BarterNFT barterNFT = new BarterNFT();
        
        // Mine the hook address for constructor args (poolManager and barterNFT)
        bytes memory args = abi.encode(IPoolManager(d.poolManager), IBarterNFT(address(barterNFT)));
        (address expected, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(GatedTradeRebateHook).creationCode, args);
        GatedTradeRebateHook counter = new GatedTradeRebateHook{salt: salt}(IPoolManager(d.poolManager), IBarterNFT(address(barterNFT)));
        vm.stopBroadcast();

        require(address(counter) == expected, "Deployed hook address mismatch");

        d.hook = address(counter);
        _writeDeployments(d);
    }
}

