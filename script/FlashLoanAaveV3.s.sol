// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// Minimal Pool interface (subset) for Aave v3
interface IPool {
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
}

/// Flash loan receiver that borrows 1 ETH (WETH) and immediately repays it.
contract FlashBorrower {
    IPool public immutable POOL;

    event FlashLoanExecuted(address asset, uint256 amount, uint256 premium, address initiator);

    constructor(IPool pool) {
        POOL = pool;
    }

    /// Called by Aave Pool during simple flash loan
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata /* params */
    ) external returns (bool) {
        require(msg.sender == address(POOL), "Caller is not Aave Pool");

        // Emit event for observability
        emit FlashLoanExecuted(asset, amount, premium, initiator);

        // Approve the Pool to pull principal + premium for repayment
        IERC20(asset).approve(address(POOL), amount + premium);
        return true;
    }
}

/// Foundry script: triggers a 1 ETH flash loan on Aave v3 Arbitrum and repays it in the same tx.
contract FlashLoanAaveV3 is Script {
    // Canonical addresses on Arbitrum (from Aave address book)
    address constant POOL_ARBITRUM = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant WETH_ARBITRUM = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    function run() external {
        IPool pool = IPool(POOL_ARBITRUM);

        // Deploy receiver
        vm.startBroadcast();
        FlashBorrower receiver = new FlashBorrower(pool);

        // Pre-fund receiver with a small WETH amount to cover the flash-loan premium (~0.05%)
        // 0.001 WETH is ample for a 1 WETH loan on typical params.
        IWETH(WETH_ARBITRUM).transfer(address(receiver), 0.001 ether);

        // Borrow 1 ETH as WETH on Arbitrum, no referral code, no extra params
        pool.flashLoanSimple(
            address(receiver),
            WETH_ARBITRUM,
            1 ether,
            bytes(""),
            0
        );
        vm.stopBroadcast();
    }
}

