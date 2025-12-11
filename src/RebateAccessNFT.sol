// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "solmate/src/tokens/ERC721.sol";

/// @notice NFT for gated access verification to Trade Rebate Hook
contract RebateAccessNFT is ERC721 {
    uint256 private _nextTokenId = 1;
    address public immutable owner;

    constructor() ERC721("Rebate Access NFT", "REBATE") {
        owner = msg.sender;
    }

    /// @notice Mint an NFT to an address (for testing/onboarding)
    function mint(address to) external returns (uint256 tokenId) {
        require(msg.sender == owner, "Only owner can mint");
        tokenId = _nextTokenId++;
        _mint(to, tokenId);
        return tokenId;
    }

    /// @notice Batch mint multiple NFTs
    function batchMint(address[] calldata recipients) external returns (uint256[] memory tokenIds) {
        require(msg.sender == owner, "Only owner can mint");
        tokenIds = new uint256[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            tokenIds[i] = _nextTokenId++;
            _mint(recipients[i], tokenIds[i]);
        }
        return tokenIds;
    }

    /// @notice Check if an address owns at least one Rebate Access NFT
    function hasRebateAccessNFT(address account) external view returns (bool) {
        return balanceOf(account) > 0;
    }

    /// @notice Returns the token URI (required by ERC721)
    function tokenURI(uint256) public pure override returns (string memory) {
        return "https://rebate.xyz/nft/";
    }
}
