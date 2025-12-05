// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract IFraxiversarryErrors {
    error AttemptigToSetExistingMintPrice();
    error CannotTransferSoulboundToken();
    error CanOnlyFuseBaseTokens();
    error CanOnlyUnfuseFusedTokens();
    error GiftMintingLimitReached();
    error InsufficientAllowance();
    error InsufficientBalance();
    error InvalidGiftMintPrice();
    error InvalidRange();
    error MintingLimitReached();
    error MintingPeriodOver();
    error MissingComposedMessage();
    error OnlyTokenOwnerCanBurnTheToken();
    error OnlyTokenOwnerCanFuseTokens();
    error OnlyTokenOwnerCanUnfuseTokens();
    error OutOfBounds();
    error SameTokenUnderlyingAssets();
    error TokenAlreadyExists(uint256 tokenId);
    error TokenDoesNotExist();
    error TokensCanOnlyBeDepositedByNftMint();
    error TokensCanOnlyBeRetrievedByNftBurn();
    error TransferFailed();
    error UnfuseTokenBeforeBurning();
    error UnsupportedToken();
}
