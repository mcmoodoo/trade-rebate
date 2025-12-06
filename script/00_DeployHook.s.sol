// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {BaseScript} from "./base/BaseScript.sol";

import {KYCHook} from "../src/KYCHook.sol";
import {BarterNFT} from "../src/BarterNFT.sol";
import {IBarterNFT} from "../src/IBarterNFT.sol";

/// @notice Mines the address and deploys the KYC hook with BarterNFT
contract DeployHookScript is BaseScript {
    function run() public {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);

        // Deploy the hook using CREATE2
        vm.startBroadcast();
        
        // Deploy BarterNFT first
        BarterNFT barterNFT = new BarterNFT();
        
        // Mine salt with constructor args (poolManager and barterNFT)
        bytes memory constructorArgs = abi.encode(poolManager, IBarterNFT(address(barterNFT)));
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(KYCHook).creationCode, constructorArgs);
        KYCHook counter = new KYCHook{salt: salt}(poolManager, IBarterNFT(address(barterNFT)));
        vm.stopBroadcast();

        require(address(counter) == hookAddress, "DeployHookScript: Hook Address Mismatch");
    }
}
