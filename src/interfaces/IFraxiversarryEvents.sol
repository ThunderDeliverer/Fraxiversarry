// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract IFraxiversarryEvents {
    event MintPriceUpdated(address indexed erc20Contract, uint256 previousMintPrice, uint256 newMintPrice);

    event NewSoulboundToken(address indexed tokenOwner, uint256 tokenId);

    event TokenFused(
        address indexed owner,
        uint256 underlyingToken1,
        uint256 underlyingToken2,
        uint256 underlyingToken3,
        uint256 premiumTokenId
    );

    event TokenUnfused(
        address indexed owner,
        uint256 underlyingToken1,
        uint256 underlyingToken2,
        uint256 underlyingToken3,
        uint256 premiumTokenId
    );
}