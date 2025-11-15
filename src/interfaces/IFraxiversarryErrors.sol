// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract IFraxiversarryErrors {
    error AttemptigToSetExistingMintPrice();
    error CannotTransferSoulboundToken();
    error InsufficientAllowance();
    error InsufficientBalance();
    error InvalidRange();
    error MintingLimitReached();
    error OnlyTokenOwnerCanBurnTheToken();
    error OnlyTokenOwnerCanFuseTokens();
    error OnlyTokenOwnerCanUnfuseTokens();
    error OutOfBounds();
    error TokensCanOnlyBeDepositedByNftMint();
    error TokensCanOnlyBeRetrievedByNftBurn();
    error TransferFailed();
    error UnsupportedToken();
}