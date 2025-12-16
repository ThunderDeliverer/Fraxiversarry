// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * ====================================================================
 * |     ______                   _______                             |
 * |    / _____________ __  __   / ____(_____  ____ _____  ________   |
 * |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
 * |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
 * | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
 * |                                                                  |
 * ====================================================================
 * ===================== IFraxiversaryErrors =========================
 * ====================================================================
 * Errors of the Fraxiversary NFT contract for the 5th anniversary of Frax Finance
 * Frax Finance: https://github.com/FraxFinance
 */

/**
 * @title IFraxiversaryErrors
 * @author Frax Finance
 * @notice A collection of errors used by the Fraxiversary NFT collection.
 */
contract IFraxiversaryErrors {
    /// @notice Attempted to set a mint price to the same value already stored
    error AttemptingToSetExistingMintPrice();

    /// @notice Attempted to transfer a token marked as non-transferable
    error CannotTransferSoulboundToken();

    /// @notice Attempted to fuse tokens that are not all BASE type
    error CanOnlyFuseBaseTokens();

    /// @notice Attempted to unfuse a token that is not FUSED type
    error CanOnlyUnfuseFusedTokens();

    /// @notice Gift minting supply limit has been reached
    error GiftMintingLimitReached();

    /// @notice ERC20 allowance is insufficient for the required transfer
    error InsufficientAllowance();

    /// @notice Balance is insufficient for the requested operation
    error InsufficientBalance();

    /// @notice Gift mint price is outside allowed constraints
    error InvalidGiftMintPrice();

    /// @notice Provided tokenId range is invalid
    error InvalidRange();

    /// @notice Base minting supply limit has been reached
    error MintingLimitReached();

    /// @notice Minting period has ended based on the cutoff block
    error MintingPeriodOver();

    /// @notice Expected a composed ONFT message but none was provided
    error MissingComposedMessage();

    /// @notice Only the current token owner can burn the token
    error OnlyTokenOwnerCanBurnTheToken();

    /// @notice Only the owner of all provided tokens can fuse them
    error OnlyTokenOwnerCanFuseTokens();

    /// @notice Only the owner of the premium token can unfuse it
    error OnlyTokenOwnerCanUnfuseTokens();

    /// @notice Provided value or tokenId is outside allowed bounds
    error OutOfBounds();

    /// @notice Underlying ERC20 assets for BASE tokens must all be distinct
    error SameTokenUnderlyingAssets();

    /// @notice Attempted to mint or credit a tokenId that already exists
    /// @dev tokenId Token ID that already exists on the current chain
    error TokenAlreadyExists(uint256 tokenId);

    /// @notice Token does not exist or has been burned
    error TokenDoesNotExist();

    /// @notice ERC20 deposits to tokenIds are only allowed during minting
    error TokensCanOnlyBeDepositedByNftMint();

    /// @notice ERC20 withdrawals from tokenIds are only allowed via burn
    error TokensCanOnlyBeRetrievedByNftBurn();

    /// @notice ERC20 transfer or transferFrom returned false
    error TransferFailed();

    /// @notice FUSED tokens must be unfused before burning
    error UnfuseTokenBeforeBurning();

    /// @notice ERC20 token is not supported for BASE minting
    error UnsupportedToken();
}
