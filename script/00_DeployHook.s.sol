// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {BaseScript} from "./base/BaseScript.sol";

import {GatedTradeRebateHook} from "../src/GatedTradeRebateHook.sol";
import {RebateAccessNFT} from "../src/RebateAccessNFT.sol";
import {IRebateAccessNFT} from "../src/IRebateAccessNFT.sol";

/// @notice Mines the address and deploys the Gated Trade Rebate hook with RebateAccessNFT
contract DeployHookScript is BaseScript {
    function run() public {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);

        // Deploy the hook using CREATE2
        vm.startBroadcast();
        
        // Deploy RebateAccessNFT first
        RebateAccessNFT rebateAccessNFT = new RebateAccessNFT();
        
        // Mine salt with constructor args (poolManager and rebateAccessNFT)
        bytes memory constructorArgs = abi.encode(poolManager, IRebateAccessNFT(address(rebateAccessNFT)));
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(GatedTradeRebateHook).creationCode, constructorArgs);
        GatedTradeRebateHook counter = new GatedTradeRebateHook{salt: salt}(poolManager, IRebateAccessNFT(address(rebateAccessNFT)));
        vm.stopBroadcast();

        require(address(counter) == hookAddress, "DeployHookScript: Hook Address Mismatch");
    }
}
