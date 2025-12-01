// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

interface IWETH {
    function deposit() external payable;
}

/// @notice Prefunds the deployed DeepAmmMock with WETH and/or USDC on an Arbitrum fork.
/// Env:
/// - DEEP_AMM: address of the DeepAmmMock
/// - FUND_WETH_WEI: amount of WETH to fund (in wei, wraps ETH then transfers)
/// - FUND_USDC: amount of USDC to fund (6 decimals)
contract PrefundDeepAmm is Script {
    // Arbitrum canonical WETH and USDC
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    event Prefunded(address deep, uint256 wethWei, uint256 usdc);

    function run() external {
        address deep = vm.envAddress("DEEP_AMM");
        uint256 fundWethWei = vm.envUint("FUND_WETH_WEI");
        uint256 fundUsdc = vm.envUint("FUND_USDC");

        vm.startBroadcast();
        if (fundWethWei > 0) {
            IWETH(WETH).deposit{value: fundWethWei}();
            IERC20(WETH).transfer(deep, fundWethWei);
        }
        if (fundUsdc > 0) {
            IERC20(USDC).transfer(deep, fundUsdc);
        }
        vm.stopBroadcast();

        emit Prefunded(deep, fundWethWei, fundUsdc);
    }
}

