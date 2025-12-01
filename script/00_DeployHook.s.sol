// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {BaseScript} from "./base/BaseScript.sol";

import {TradeRebate, IAavePool} from "../src/TradeRebate.sol";
import {DeepAmmMock} from "../src/DeepAmmMock.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @notice Mines the address and deploys the Counter.sol Hook contract
contract DeployHookScript is BaseScript {
    function run() public {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

        // Deploy mock deep AMM and use canonical Aave/asset addresses
        DeepAmmMock deep = new DeepAmmMock();
        address aavePool = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
        address weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        address usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

        // Mine a salt that will produce a hook address with the correct flags and constructor
        bytes memory constructorArgs = abi.encode(poolManager, aavePool, address(deep), weth, usdc, uint256(1_000_000e6));
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(TradeRebate).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        vm.startBroadcast();
        TradeRebate counter =
            new TradeRebate{salt: salt}(poolManager, IAavePool(aavePool), deep, IERC20(weth), IERC20(usdc), 1_000_000e6);
        vm.stopBroadcast();

        require(address(counter) == hookAddress, "DeployHookScript: Hook Address Mismatch");
    }
}
