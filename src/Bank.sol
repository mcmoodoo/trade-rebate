// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @notice Minimal trust-based bank that lends ERC20s and expects repayment + small fee.
contract Bank {
    address public immutable owner;
    uint256 public immutable feeBps; // e.g., 5 = 0.05%

    event Borrow(address indexed borrower, address indexed token, uint256 amount);
    event Repay(address indexed payer, address indexed token, uint256 amount);

    constructor(uint256 _feeBps) {
        require(_feeBps <= 10_000, "fee too high");
        owner = msg.sender;
        feeBps = _feeBps;
    }

    /// @dev Pre-fund the bank by transferring tokens into this contract.
    function borrow(address token, uint256 amount) external {
        require(amount > 0, "amount=0");
        IERC20(token).transfer(msg.sender, amount);
        emit Borrow(msg.sender, token, amount);
    }

    /// @dev Hooks repay by transferring tokens back; we emit for observability.
    function repay(address token, uint256 amount) external {
        require(amount > 0, "amount=0");
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        emit Repay(msg.sender, token, amount);
    }
}

