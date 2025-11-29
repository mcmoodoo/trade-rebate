// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SequenceBase} from "./SequenceBase.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

/// @notice Deploys two mock tokens (mUSDC, mWBTC) and stores their addresses.
contract DeployTokens is SequenceBase {
    function run() external {
        vm.startBroadcast();
        // USDC-like: 6 decimals
        MockERC20 mUSDC = new MockERC20("Mock USDC", "mUSDC", 6);
        mUSDC.mint(msg.sender, 1_000_000_000_000); // 1e12 = 1,000,000 mUSDC with 6 decimals

        // WBTC-like: 8 decimals
        MockERC20 mWBTC = new MockERC20("Mock WBTC", "mWBTC", 8);
        mWBTC.mint(msg.sender, 21_000_000_00000000); // 21,000,000 mWBTC with 8 decimals
        vm.stopBroadcast();

        Deployments memory d = _readDeployments();
        d.token0 = address(mUSDC);
        d.token1 = address(mWBTC);
        _writeDeployments(d);
    }
}

