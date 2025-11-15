// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract IFraxiversarryErrors {
    error AttemptigToSetExistingMintPrice();
    error CannotTransferSoulboundToken();
    error CanOnlyFuseBaseTokens();
    error CanOnlyUnfuseFusedTokens();
    error InsufficientAllowance();
    error InsufficientBalance();
    error InvalidRange();
    error MintingLimitReached();
    error OnlyTokenOwnerCanBurnTheToken();
    error OnlyTokenOwnerCanFuseTokens();
    error OnlyTokenOwnerCanUnfuseTokens();
    error OutOfBounds();
    error SameTokenUnderlyingAssets();
    error TokenDoesNotExist();
    error TokensCanOnlyBeDepositedByNftMint();
    error TokensCanOnlyBeRetrievedByNftBurn();
    error TransferFailed();
    error UnfuseTokenBeforeBurning();
    error UnsupportedToken();
}