// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SequenceBase} from "./SequenceBase.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

interface IWETH {
    function deposit() external payable;
}

/// @notice Prefunds the deployed DeepAmmMock with WETH and/or USDC using addresses from deployments.json.
/// Env (optional overrides):
/// - DEEP_AMM: address of the DeepAmmMock (defaults to deployments.json .deepAmm)
/// - FUND_WETH_WEI: amount of WETH to fund (in wei, wraps ETH then transfers; default 1e18)
/// - FUND_USDC: amount of USDC to fund (6 decimals; default 100e6)
contract PrefundDeepAmm is SequenceBase {
    event Prefunded(address deep, uint256 wethWei, uint256 usdc);

    function run() external {
        Deployments memory d = _readDeployments();
        require(d.deepAmm != address(0), "deepAmm not set");
        require(d.weth != address(0), "weth not set");
        require(d.token1 != address(0), "token1 (USDC) not set");

        address deep = vm.envOr("DEEP_AMM", d.deepAmm);
        uint256 fundWethWei = vm.envOr("FUND_WETH_WEI", uint256(1 ether));
        uint256 fundUsdc = vm.envOr("FUND_USDC", uint256(100_000_000)); // 100 USDC

        IERC20 WETH = IERC20(d.weth);
        IERC20 USDC = IERC20(d.token1);

        vm.startBroadcast();
        if (fundWethWei > 0) {
            IWETH(address(WETH)).deposit{value: fundWethWei}();
            WETH.transfer(deep, fundWethWei);
        }
        if (fundUsdc > 0) {
            USDC.transfer(deep, fundUsdc);
        }
        vm.stopBroadcast();

        emit Prefunded(deep, fundWethWei, fundUsdc);
    }
}

