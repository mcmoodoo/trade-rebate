// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {SequenceBase} from "./SequenceBase.sol";
import {GatedTradeRebateHook} from "../../src/GatedTradeRebateHook.sol";
import {RebateAccessNFT} from "../../src/RebateAccessNFT.sol";
import {IRebateAccessNFT} from "../../src/IRebateAccessNFT.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

/// @notice Mines and deploys the Gated Trade Rebate hook with RebateAccessNFT; saves address to deployments.json
contract DeployHook is SequenceBase {
    function run() external {
        Deployments memory d = _readDeployments();
        require(d.poolManager != address(0), "PoolManager not deployed");

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);

        vm.startBroadcast();
        
        // Deploy RebateAccessNFT first
        RebateAccessNFT rebateAccessNFT = new RebateAccessNFT();
        
        // Mine the hook address for constructor args (poolManager and rebateAccessNFT)
        bytes memory args = abi.encode(IPoolManager(d.poolManager), IRebateAccessNFT(address(rebateAccessNFT)));
        (address expected, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(GatedTradeRebateHook).creationCode, args);
        GatedTradeRebateHook counter = new GatedTradeRebateHook{salt: salt}(IPoolManager(d.poolManager), IRebateAccessNFT(address(rebateAccessNFT)));
        vm.stopBroadcast();

        require(address(counter) == expected, "Deployed hook address mismatch");

        d.hook = address(counter);
        _writeDeployments(d);
    }
}

