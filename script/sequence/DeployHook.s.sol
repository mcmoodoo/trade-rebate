// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {SequenceBase} from "./SequenceBase.sol";
import {TradeRebate, IBank} from "../../src/TradeRebate.sol";
import {DeepAmmMock} from "../../src/DeepAmmMock.sol";
import {Bank} from "../../src/Bank.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @notice Mines and deploys the Counter hook; saves address to deployments.json
contract DeployHook is SequenceBase {
    function run() external {
        Deployments memory d = _readDeployments();
        require(d.poolManager != address(0), "PoolManager not deployed");

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

        // Canonical assets (USDC, WETH)
        address weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        address usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

        vm.startBroadcast();
        // Deploy bank and a mock deep AMM to trade against; fund them separately if needed
        Bank bank = new Bank(5);
        DeepAmmMock deep = new DeepAmmMock();
        // Mine the hook address for the full constructor args (now that deep is deployed)
        bytes memory args =
            abi.encode(IPoolManager(d.poolManager), address(bank), address(deep), weth, usdc, uint256(1_000_000e6));
        (address expected, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(TradeRebate).creationCode, args);
        TradeRebate counter =
            new TradeRebate{salt: salt}(IPoolManager(d.poolManager), IBank(address(bank)), deep, IERC20(weth), IERC20(usdc), 1_000_000e6);
        vm.stopBroadcast();

        require(address(counter) == expected, "Deployed hook address mismatch");

        d.hook = address(counter);
        d.deepAmm = address(deep);
        d.weth = weth;
        _writeDeployments(d);
    }
}

