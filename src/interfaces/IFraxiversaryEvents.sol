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
 * ===================== IFraxiversaryEvents =========================
 * ====================================================================
 * Events of the Fraxiversary NFT contract for the 5th anniversary of Frax Finance
 * Frax Finance: https://github.com/FraxFinance
 */

/**
 * @title IFraxiversaryEvents
 * @author Frax Finance
 * @notice A collection of events used by the Fraxiversary NFT collection.
 */
contract IFraxiversaryEvents {
    /**
     * @notice Emitted when a minting fee is collected for a given ERC20
     * @dev This is emitted during BASE and GIFT mint flows when a fee is added on top of the net amount
     * @param erc20Contract ERC20 token used for the mint payment
     * @param from Address that paid the fee
     * @param feeAmount Fee amount recorded for the ERC20
     */
    event FeeCollected(address indexed erc20Contract, address indexed from, uint256 feeAmount);

    /**
     * @notice Emitted when the contract owner retrieves accumulated minting fees
     * @dev The fee balance for the ERC20 is reset to zero before transferring out
     * @param erc20Contract ERC20 token whose fees were retrieved
     * @param to Address that received the fees
     * @param feeAmount Fee amount transferred to the recipient
     */
    event FeesRetrieved(address indexed erc20Contract, address indexed to, uint256 feeAmount);

    /**
     * @notice Emitted when a GIFT token is minted for a recipient
     * @dev The minter pays the giftMintingPrice plus fee while the recipient receives the NFT
     * @param minter Address that paid for the gift mint
     * @param recipient Address that received the newly minted GIFT token
     * @param tokenId Newly minted GIFT token ID
     * @param mintPrice Net mint price excluding fee
     */
    event GiftMinted(address indexed minter, address indexed recipient, uint256 tokenId, uint256 mintPrice);

    /**
     * @notice Emitted when the base GIFT mint price is updated
     * @dev This event tracks changes to giftMintingPrice
     * @param previousMintPrice Previous GIFT mint price
     * @param newMintPrice New GIFT mint price
     */
    event GiftMintPriceUpdated(uint256 previousMintPrice, uint256 newMintPrice);

    /**
     * @notice Emitted when the minting cutoff block is updated
     * @dev The cutoff governs when BASE and GIFT minting is disabled
     * @param previousCutoffBlock Previous cutoff block number
     * @param newCutoffBlock New cutoff block number
     */
    event MintingCutoffBlockUpdated(uint256 previousCutoffBlock, uint256 newCutoffBlock);

    /**
     * @notice Emitted when the minting fee basis points value is updated
     * @dev The fee applies to both BASE and GIFT mint prices
     * @param previousFeeBasisPoints Previous fee value in basis points
     * @param newFeeBasisPoints New fee value in basis points
     */
    event MintingFeeUpdated(uint256 previousFeeBasisPoints, uint256 newFeeBasisPoints);

    /**
     * @notice Emitted when a BASE mint price is added, updated, or removed for an ERC20
     * @dev Setting newMintPrice to zero indicates removal from the supported list
     * @param erc20Contract ERC20 token whose mint price was updated
     * @param previousMintPrice Previous BASE mint price for the ERC20
     * @param newMintPrice New BASE mint price for the ERC20
     */
    event MintPriceUpdated(address indexed erc20Contract, uint256 previousMintPrice, uint256 newMintPrice);

    /**
     * @notice Emitted when a new SOULBOUND token is minted
     * @dev SOULBOUND tokens are marked non-transferable
     * @param tokenOwner Address that received the soulbound token
     * @param tokenId Newly minted SOULBOUND token ID
     */
    event NewSoulboundToken(address indexed tokenOwner, uint256 tokenId);

    /**
     * @notice Emitted when four BASE tokens are fused into a FUSED premium token
     * @dev The underlying BASE tokens are transferred into contract custody
     * @param owner Address that performed the fuse and received the premium token
     * @param underlyingToken1 First underlying BASE token ID
     * @param underlyingToken2 Second underlying BASE token ID
     * @param underlyingToken3 Third underlying BASE token ID
     * @param underlyingToken4 Fourth underlying BASE token ID
     * @param premiumTokenId Newly minted FUSED token ID
     */
    event TokenFused(
        address indexed owner,
        uint256 underlyingToken1,
        uint256 underlyingToken2,
        uint256 underlyingToken3,
        uint256 underlyingToken4,
        uint256 premiumTokenId
    );

    /**
     * @notice Emitted when a FUSED premium token is burned and its BASE tokens are returned
     * @dev The underlying token references on the premium token are cleared after unfusing
     * @param owner Address that unfused the premium token and received the BASE tokens back
     * @param underlyingToken1 First underlying BASE token ID returned
     * @param underlyingToken2 Second underlying BASE token ID returned
     * @param underlyingToken3 Third underlying BASE token ID returned
     * @param underlyingToken4 Fourth underlying BASE token ID returned
     * @param premiumTokenId FUSED token ID that was unfused and burned
     */
    event TokenUnfused(
        address indexed owner,
        uint256 underlyingToken1,
        uint256 underlyingToken2,
        uint256 underlyingToken3,
        uint256 underlyingToken4,
        uint256 premiumTokenId
    );
}
