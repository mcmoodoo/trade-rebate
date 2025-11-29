// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SequenceBase} from "./SequenceBase.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

/// @notice Deploys two mock tokens (fUSDC, fWBTC) and stores their addresses.
contract DeployTokens is SequenceBase {
    function run() external {
        vm.startBroadcast();
        // USDC-like: 6 decimals
        MockERC20 fUSDC = new MockERC20("Fake USDC", "fUSDC", 6);
        fUSDC.mint(msg.sender, 1_000_000_000_000); // 1e12 = 1,000,000 fUSDC with 6 decimals

        // WBTC-like: 8 decimals
        MockERC20 fWBTC = new MockERC20("Fake WBTC", "fWBTC", 8);
        fWBTC.mint(msg.sender, 21_000_000_00000000); // 21,000,000 WBTC with 8 decimals
        vm.stopBroadcast();

        Deployments memory d = _readDeployments();
        d.token0 = address(fUSDC);
        d.token1 = address(fWBTC);
        _writeDeployments(d);
    }
}

