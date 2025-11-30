// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";

interface IWETH {
    function deposit() external payable;
}

/// @notice Wraps native ETH into WETH on Arbitrum.
/// Amount (in wei) is read from env WRAP_AMOUNT_WEI.
contract WrapETH is Script {
    // Arbitrum canonical WETH
    address constant WETH_ARBITRUM = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    event Wrapped(address indexed from, uint256 amount);

    function run() external {
        uint256 amountWei = vm.envUint("WRAP_AMOUNT_WEI");
        vm.startBroadcast();
        IWETH(WETH_ARBITRUM).deposit{value: amountWei}();
        emit Wrapped(msg.sender, amountWei);
        vm.stopBroadcast();
    }
}

