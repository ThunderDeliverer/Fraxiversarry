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
 * ========================= Fraxiversarry ============================
 * ====================================================================
 * Fraxiversarry NFT contract for the 5th anniversary of Frax Finance
 * Frax Finance: https://github.com/FraxFinance
 */

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {ERC721Burnable} from "openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {ERC721Enumerable} from "openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721Pausable} from "openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import {ERC721URIStorage} from "openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

import {IFraxiversarryErrors} from "./interfaces/IFraxiversarryErrors.sol";
import {IFraxiversarryEvents} from "./interfaces/IFraxiversarryEvents.sol";
import {IERC6454} from "./interfaces/IERC6454.sol";
import {IERC7590} from "./interfaces/IERC7590.sol";
import {IERC4906} from "openzeppelin-contracts/contracts/interfaces/IERC4906.sol";

import {ONFT721Core} from "@layerzerolabs/onft-evm/contracts/onft721/ONFT721Core.sol";
import {IONFT721, SendParam} from "@layerzerolabs/onft-evm/contracts/onft721/interfaces/IONFT721.sol";
import {ONFT721MsgCodec} from "@layerzerolabs/onft-evm/contracts/onft721/libs/ONFT721MsgCodec.sol";
import {ONFTComposeMsgCodec} from "@layerzerolabs/onft-evm/contracts/libs/ONFTComposeMsgCodec.sol";
import {IOAppMsgInspector} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppMsgInspector.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

/**
 * @title Fraxiversarry
 * @author Frax Finance
 * @notice Fraxiversarry is a composable ERC721 that tokenizes ERC20 deposits and supports cross-chain movement
 * @dev The contract supports BASE mints funded by approved Frax ERC20s, GIFT mints funded by WFRAX,
 *  SOULBOUND mints for curated distribution, and FUSED tokens created from four BASE tokens
 * @dev Minting for BASE and GIFT is time-boxed by mintingCutoffBlock which is calculated assuming Fraxtal 2s blocks
 * @dev ERC20 deposits are accounted per tokenId and can only be withdrawn by burning the NFT
 * @dev Soulbound restrictions are enforced via _update with a bridge-aware bypass used during ONFT operations
 * @dev Frax Reviewer(s) / Contributor(s)
 *  Jan Turk: https://github.com/ThunderDeliverer
 *  Sam Kazemian: https://github.com/samkazemian
 *  Bjirke (honorary mention for the original idea)
 */
contract Fraxiversarry is
    ERC721,
    ERC721Enumerable,
    ERC721URIStorage,
    ERC721Pausable,
    ERC721Burnable,
    IERC6454,
    IERC7590,
    IFraxiversarryErrors,
    IFraxiversarryEvents,
    ONFT721Core
{
    using ONFT721MsgCodec for bytes;
    using ONFT721MsgCodec for bytes32;

    /// @notice Canonical WFRAX address on Fraxtal used for gift mints and internal accounting
    address public constant WFRAX_ADDRESS = 0xFc00000000000000000000000000000000000002;

    /// @notice Maximum basis points value used for fee calculations
    uint256 public constant MAX_BASIS_POINTS = 1e4;

    /// @notice Stores base mint price for each supported ERC20
    /// @dev erc20 ERC20 token address used for BASE mint payments
    /// @dev price Price in ERC20 units excluding minting fee
    mapping(address erc20 => uint256 price) public mintPrices;

    /// @notice Stores the token URI assigned to BASE NFTs minted with a given ERC20
    /// @dev erc20 ERC20 token address used for BASE mint payments
    /// @dev uri Metadata URI applied to newly minted BASE tokens
    mapping(address erc20 => string uri) public baseAssetTokenUris;

    /// @notice Tracks fees collected per ERC20 from BASE and GIFT minting
    /// @dev erc20 ERC20 token address used for mint payment
    /// @dev fee Accumulated fee amount held by the contract
    mapping(address erc20 => uint256 fee) public collectedFees;

    /// @notice Stores supported ERC20 token addresses by index for enumeration
    /// @dev index Position in the supported ERC20 list
    /// @dev erc20 ERC20 token address at the stored index
    mapping(uint256 index => address erc20) public supportedErc20s;

    /// @notice Stores the underlying ERC20 asset addresses attached to each tokenId
    /// @dev tokenId Fraxiversarry token ID that holds underlying assets
    /// @dev index Position of the underlying asset for the tokenId
    /// @dev underlyingAsset ERC20 token address stored at a given index for the tokenId
    mapping(uint256 tokenId => mapping(uint256 index => address underlyingAsset)) public underlyingAssets;

    /// @notice Stores the number of underlying ERC20 assets recorded for each tokenId
    /// @dev tokenId Fraxiversarry token ID that holds underlying assets
    /// @dev numberOfAssets Count of underlyingAssets entries for the tokenId
    mapping(uint256 tokenId => uint256 numberOfAssets) public numberOfTokenUnderlyingAssets;

    /// @notice Stores the outbound ERC20 transfer nonce for each tokenId
    /// @dev tokenId Fraxiversarry token ID that holds underlying assets
    /// @dev transferOutNonce Number of successful ERC20 withdrawals triggered by burn
    mapping(uint256 tokenId => uint256 transferOutNonce) public transferOutNonces;

    /// @notice Stores the internal ERC20 balance credited to each tokenId per ERC20
    /// @dev tokenId Fraxiversarry token ID that holds underlying assets
    /// @dev erc20 ERC20 token address for which the internal balance is tracked
    /// @dev balance Internal accounting balance for the ERC20 held by the tokenId
    mapping(uint256 tokenId => mapping(address erc20 => uint256 balance)) public erc20Balances;

    /// @notice Stores the four underlying BASE token IDs that make up a FUSED token
    /// @dev tokenId FUSED token ID that references underlying BASE tokens
    /// @dev index Position of the underlying BASE token ID for the FUSED token 0-3
    /// @dev underlyingTokenId Underlying BASE token ID stored at the index for the tokenId
    mapping(uint256 tokenId => mapping(uint256 index => uint256 underlyingTokenId)) public underlyingTokenIds;

    /// @notice Marks whether a tokenId is non-transferable under IERC6454 rules
    /// @dev tokenId Fraxiversarry token ID to check
    /// @dev nonTransferable True if the token is soulbound
    mapping(uint256 tokenId => bool nonTransferable) public isNonTransferrable;

    /// @notice Stores the TokenType classification for each tokenId
    /// @dev tokenId Fraxiversarry token ID to classify
    /// @dev tokenType Current type for the tokenId
    mapping(uint256 tokenId => TokenType tokenType) public tokenTypes;

    /// @notice Next BASE tokenId to be minted
    uint256 public nextTokenId;

    /// @notice Next GIFT tokenId to be minted
    uint256 public nextGiftTokenId;

    /// @notice Next premium tokenId to be minted for FUSED or SOULBOUND tokens
    uint256 public nextPremiumTokenId;

    /// @notice Number of ERC20 tokens currently supported for BASE minting
    uint256 public totalNumberOfSupportedErc20s;

    /// @notice Maximum number of BASE tokens that can be minted
    uint256 public mintingLimit;

    /// @notice Maximum number of GIFT tokens that can be minted
    uint256 public giftMintingLimit;

    /// @notice Base price for a single GIFT mint denominated in WFRAX
    uint256 public giftMintingPrice;

    /// @notice Minting fee in basis points applied to BASE and GIFT mint prices
    uint256 public mintingFeeBasisPoints;

    /// @notice Block number after which BASE and GIFT minting is disabled
    uint256 public mintingCutoffBlock;

    /// @dev Flag that disables soulbound checks during bridge operations
    bool private _isBridgeOperation;

    /**
     * @notice TokenType describes the classification and rules for each minted token
     * @dev NONEXISTENT is used after burn and for unminted token IDs
     * @dev BASE tokens are backed by a single ERC20 deposit
     * @dev FUSED tokens are backed by four distinct BASE tokens
     * @dev SOULBOUND tokens are non-transferable and may represent curated rewards
     * @dev GIFT tokens are backed by WFRAX and have a separate supply and price
     */
    enum TokenType {
        NONEXISTENT, // 0 - Token does not exist
        BASE, // 1 - NFTs that are minted using ERC20 tokens
        FUSED, // 2 - NFTs that are created by combining multiple base NFTs
        SOULBOUND, // 3 - NFTs that are non-transferable and tied to a specific user
        GIFT // 4 - NFTs that are gifted and have a separate minting limit and separate mint prices
    }

    /// @dev Default metadata URI for GIFT tokens
    string private giftTokenUri;

    /// @dev Default metadata URI for FUSED tokens
    string private premiumTokenUri;

    /**
     * @notice Initializes Fraxiversarry with supply caps, fee settings, and ONFT configuration
     * @dev The mintingCutoffBlock is calculated assuming a fixed 2 second Fraxtal block time
     * @dev nextGiftTokenId starts immediately after the BASE tokenId range
     * @dev nextPremiumTokenId starts immediately after the GIFT tokenId range
     * @param _initialOwner Address that will own the contract and control admin functions
     * @param _lzEndpoint LayerZero endpoint used by ONFT721Core
     */
    constructor(address _initialOwner, address _lzEndpoint)
        ERC721("Fraxiversarry", "FRAX5Y")
        ONFT721Core(_lzEndpoint, _initialOwner)
    {
        mintingLimit = 12_000;
        giftMintingLimit = 50_000;
        giftMintingPrice = 50 * 1e18; // 50 WFRAX
        nextGiftTokenId = mintingLimit;
        nextPremiumTokenId = mintingLimit + giftMintingLimit;
        mintingFeeBasisPoints = 25; // 0.25%
        mintingCutoffBlock = block.number + (35 days / 2 seconds); // Approximately 5 weeks with 2s blocktime

        //TODO: Set correct URIs
        giftTokenUri = "https://gift.tba.frax/";
        premiumTokenUri = "https://premium.tba.frax/";
    }

    /**
     * @notice Returns the base URI for token metadata resolution
     * @dev The contract relies on per-token URIs for all token types
     * @return Empty base URI string
     */
    function _baseURI() internal pure override returns (string memory) {
        return "";
    }

    /**
     * @notice Pauses all transfers and minting that rely on ERC721Pausable checks
     * @dev Only the contract owner can pause the contract
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract so transfers and minting can resume
     * @dev Only the contract owner can unpause the contract
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @notice Mints a BASE token by transferring the configured ERC20 price plus fee into the contract
     * @dev Reverts if the minting period is over or the BASE minting limit is reached
     * @dev The ERC20 must be supported via updateBaseAssetMintPrice with a non-zero price
     * @dev The deposited amount excluding fee is credited to the new tokenId internal balance
     * @param _erc20Contract ERC20 token address used to pay for the mint
     * @return Newly minted BASE token ID
     */
    function paidMint(address _erc20Contract) public returns (uint256) {
        if (block.number > mintingCutoffBlock) revert MintingPeriodOver();
        if (nextTokenId >= mintingLimit) revert MintingLimitReached();
        if (mintPrices[_erc20Contract] == 0) revert UnsupportedToken();

        uint256 tokenId = nextTokenId++;
        _transferERC20ToToken(_erc20Contract, tokenId, msg.sender);

        // Update underlying assets with the asset being used when minting
        underlyingAssets[tokenId][numberOfTokenUnderlyingAssets[tokenId]] = _erc20Contract;
        numberOfTokenUnderlyingAssets[tokenId] += 1;

        // Set the token type to BASE
        tokenTypes[tokenId] = TokenType.BASE;

        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, baseAssetTokenUris[_erc20Contract]);

        return tokenId;
    }

    /**
     * @notice Mints a GIFT token to a recipient by paying the configured WFRAX price plus fee
     * @dev Reverts if the minting period is over or the GIFT minting limit is reached
     * @dev The caller pays the giftMintingPrice while the recipient receives the NFT
     * @param _recipient Address that will receive the newly minted GIFT NFT
     * @return Newly minted GIFT token ID
     */
    function giftMint(address _recipient) public returns (uint256) {
        if (block.number > mintingCutoffBlock) revert MintingPeriodOver();
        if (nextGiftTokenId >= mintingLimit + giftMintingLimit) revert GiftMintingLimitReached();

        uint256 tokenId = nextGiftTokenId;
        nextGiftTokenId += 1;
        _transferERC20ToToken(WFRAX_ADDRESS, tokenId, msg.sender, giftMintingPrice);

        // Update underlying assets with the asset being used when minting
        underlyingAssets[tokenId][numberOfTokenUnderlyingAssets[tokenId]] = WFRAX_ADDRESS;
        numberOfTokenUnderlyingAssets[tokenId] += 1;

        // Set the token type to GIFT
        tokenTypes[tokenId] = TokenType.GIFT;

        _safeMint(_recipient, tokenId);
        _setTokenURI(tokenId, giftTokenUri);

        emit GiftMinted(msg.sender, _recipient, tokenId, giftMintingPrice);

        return tokenId;
    }

    /**
     * @notice Mints a SOULBOUND token to a recipient with a custom token URI
     * @dev Only the contract owner can mint SOULBOUND tokens
     * @dev Soulbound tokens are marked non-transferable and are excluded from underlying balance views
     * @param _recipient Address that will receive the soulbound NFT
     * @param _tokenUri Metadata URI assigned to the soulbound NFT
     * @return Newly minted SOULBOUND token ID
     */
    function soulboundMint(address _recipient, string memory _tokenUri) public onlyOwner returns (uint256) {
        uint256 tokenId = nextPremiumTokenId;

        _safeMint(_recipient, tokenId);
        _setTokenURI(tokenId, _tokenUri);

        isNonTransferrable[tokenId] = true;
        tokenTypes[tokenId] = TokenType.SOULBOUND;

        nextPremiumTokenId += 1;

        emit NewSoulboundToken(_recipient, tokenId);

        return tokenId;
    }

    /**
     * @notice Burns a token and returns all held ERC20 balances to the token owner
     * @dev Only the current token owner can burn
     * @dev FUSED tokens must be unfused before they can be burned
     * @dev ERC20 transfers are performed per underlying asset recorded for the tokenId
     * @param _tokenId Token ID to burn and redeem underlying ERC20 balances from
     */
    function burn(uint256 _tokenId) public override(ERC721Burnable) {
        if (msg.sender != ownerOf(_tokenId)) revert OnlyTokenOwnerCanBurnTheToken();
        if (tokenTypes[_tokenId] == TokenType.FUSED) revert UnfuseTokenBeforeBurning();
        // Transfer out the held ERC20 and then burn the NFT
        for (uint256 i; i < numberOfTokenUnderlyingAssets[_tokenId];) {
            _transferHeldERC20FromToken(
                underlyingAssets[_tokenId][i],
                _tokenId,
                msg.sender,
                erc20Balances[_tokenId][underlyingAssets[_tokenId][i]]
            );

            unchecked {
                ++i;
            }
        }
        numberOfTokenUnderlyingAssets[_tokenId] = 0;
        super.burn(_tokenId);
        tokenTypes[_tokenId] = TokenType.NONEXISTENT;
    }

    /**
     * @notice Sets the metadata URI used for BASE tokens minted with a specified ERC20
     * @dev Only the contract owner can set base asset URIs
     * @param _erc20Contract ERC20 token address whose BASE mint URI will be updated
     * @param _uri New metadata URI for BASE tokens minted with the ERC20
     */
    function setBaseAssetTokenUri(address _erc20Contract, string memory _uri) public onlyOwner {
        baseAssetTokenUris[_erc20Contract] = _uri;
    }

    /**
     * @notice Sets the default metadata URI used for all GIFT tokens
     * @dev Only the contract owner can set the GIFT token URI
     * @param _uri New default metadata URI for GIFT tokens
     */
    function setGiftTokenUri(string memory _uri) public onlyOwner {
        giftTokenUri = _uri;
    }

    /**
     * @notice Sets the default metadata URI used for all FUSED tokens
     * @dev Only the contract owner can set the premium token URI
     * @param _uri New default metadata URI for FUSED tokens
     */
    function setPremiumTokenUri(string memory _uri) public onlyOwner {
        premiumTokenUri = _uri;
    }

    /**
     * @notice Refreshes BASE token URIs for an inclusive tokenId range
     * @dev Only the contract owner can refresh BASE token URIs
     * @dev The function reads the underlying asset at index 0 and updates the token URI if balance is non-zero
     * @param _firstTokenId First tokenId in the range to update
     * @param _lastTokenId Last tokenId in the range to update
     */
    function refreshBaseTokenUris(uint256 _firstTokenId, uint256 _lastTokenId) public onlyOwner {
        if (_lastTokenId < _firstTokenId) revert InvalidRange();
        if (_lastTokenId >= nextTokenId) revert OutOfBounds();

        for (uint256 tokenId = _firstTokenId; tokenId <= _lastTokenId;) {
            address underlyingAsset = underlyingAssets[tokenId][0];

            // Only update if there is an underlying asset (if the token exists)
            if (underlyingAsset != address(0) && erc20Balances[tokenId][underlyingAsset] > 0) {
                _setTokenURI(tokenId, baseAssetTokenUris[underlyingAsset]);
            }

            unchecked {
                ++tokenId;
            }
        }

        emit BatchMetadataUpdate(_firstTokenId, _lastTokenId);
    }

    /**
     * @notice Refreshes GIFT token URIs for an inclusive tokenId range
     * @dev Only the contract owner can refresh GIFT token URIs
     * @dev The range must start within the GIFT tokenId space and end below nextGiftTokenId
     * @param _firstTokenId First tokenId in the GIFT range to update
     * @param _lastTokenId Last tokenId in the GIFT range to update
     */
    function refreshGiftTokenUris(uint256 _firstTokenId, uint256 _lastTokenId) public onlyOwner {
        if (_firstTokenId < mintingLimit) revert OutOfBounds();
        if (_lastTokenId < _firstTokenId) revert InvalidRange();
        if (_lastTokenId >= nextGiftTokenId) revert OutOfBounds();

        for (uint256 tokenId = _firstTokenId; tokenId <= _lastTokenId;) {
            // Only update if there is an underlying asset (if the token exists)
            if (erc20Balances[tokenId][WFRAX_ADDRESS] > 0) {
                _setTokenURI(tokenId, giftTokenUri);
            }

            unchecked {
                ++tokenId;
            }
        }

        emit BatchMetadataUpdate(_firstTokenId, _lastTokenId);
    }

    /**
     * @notice Refreshes premium token URIs for an inclusive tokenId range
     * @dev Only the contract owner can refresh premium token URIs
     * @dev Only FUSED tokens are updated as they hold underlyingTokenIds references
     * @param _firstTokenId First tokenId in the premium range to update
     * @param _lastTokenId Last tokenId in the premium range to update
     */
    function refreshPremiumTokenUris(uint256 _firstTokenId, uint256 _lastTokenId) public onlyOwner {
        if (_lastTokenId < _firstTokenId) revert InvalidRange();
        if (_firstTokenId < mintingLimit + giftMintingLimit) revert OutOfBounds();
        if (_lastTokenId >= nextPremiumTokenId) revert OutOfBounds();

        for (uint256 tokenId = _firstTokenId; tokenId <= _lastTokenId;) {
            // Only update if the token has underlying tokens (this ensures that the token exists and that it isn't soulbound)
            if (underlyingTokenIds[tokenId][0] != 0 || underlyingTokenIds[tokenId][1] != 0) {
                // This is in case the first underlying token ID is 0

                _setTokenURI(tokenId, premiumTokenUri);
            }

            unchecked {
                ++tokenId;
            }
        }

        emit BatchMetadataUpdate(_firstTokenId, _lastTokenId);
    }

    /**
     * @notice Updates the metadata URI for a specific existing token
     * @dev Only the contract owner can update token URIs
     * @dev Reverts if the token has been burned or never existed
     * @param _tokenId Token ID whose metadata URI will be updated
     * @param _uri New metadata URI for the _tokenId
     */
    function updateSpecificTokenUri(uint256 _tokenId, string memory _uri) public onlyOwner {
        if (tokenTypes[_tokenId] == TokenType.NONEXISTENT) revert TokenDoesNotExist();

        _setTokenURI(_tokenId, _uri);
    }

    /**
     * @notice Adds, updates, or removes an ERC20 from the BASE mint allowlist by setting its mint price
     * @dev Setting a non-zero price adds the token to supportedErc20s if it was not previously supported
     * @dev Setting the price to zero removes the token from supportedErc20s
     * @dev The function emits MintPriceUpdated for all price changes
     * @param _erc20Contract ERC20 token address to update
     * @param _mintPrice New BASE mint price for the ERC20
     */
    function updateBaseAssetMintPrice(address _erc20Contract, uint256 _mintPrice) public onlyOwner {
        uint256 previousMintPrice = mintPrices[_erc20Contract];
        if (previousMintPrice == _mintPrice) revert AttemptingToSetExistingMintPrice();

        mintPrices[_erc20Contract] = _mintPrice;

        if (previousMintPrice == 0) {
            supportedErc20s[totalNumberOfSupportedErc20s] = _erc20Contract;
            totalNumberOfSupportedErc20s += 1;
        }

        if (_mintPrice == 0) {
            uint256 erc20Index = type(uint256).max;

            for (uint256 i; i < totalNumberOfSupportedErc20s;) {
                if (supportedErc20s[i] == _erc20Contract) {
                    erc20Index = i;
                    break;
                }

                unchecked {
                    ++i;
                }
            }

            // This shouldn't even be reachable, but it is defensive guard in case the guard at the beginning of the
            //  function doesn't catch an unsupported token
            if (erc20Index == type(uint256).max) revert UnsupportedToken();

            supportedErc20s[erc20Index] = supportedErc20s[totalNumberOfSupportedErc20s - 1];
            totalNumberOfSupportedErc20s -= 1;
            supportedErc20s[totalNumberOfSupportedErc20s] = address(0);
        }

        emit MintPriceUpdated(_erc20Contract, previousMintPrice, _mintPrice);
    }

    /**
     * @notice Updates the base WFRAX price used for GIFT minting
     * @dev Only the contract owner can update the GIFT mint price
     * @dev The price must be greater than 1 WFRAX
     * @param _newPrice New GIFT mint price denominated in WFRAX
     */
    function updateGiftMintingPrice(uint256 _newPrice) public onlyOwner {
        if (_newPrice <= 1e18) revert InvalidGiftMintPrice(); // Minimum 1 WFRAX
        uint256 previousPrice = giftMintingPrice;
        if (previousPrice == _newPrice) revert AttemptingToSetExistingMintPrice();

        giftMintingPrice = _newPrice;

        emit GiftMintPriceUpdated(previousPrice, _newPrice);
    }

    /**
     * @notice Updates the minting fee charged on top of BASE and GIFT prices
     * @dev Only the contract owner can update fee basis points
     * @dev The new value must not exceed MAX_BASIS_POINTS
     * @param _newFeeBasisPoints New fee value expressed in basis points
     */
    function updateMintingFeeBasisPoints(uint256 _newFeeBasisPoints) public onlyOwner {
        if (_newFeeBasisPoints > MAX_BASIS_POINTS) revert OutOfBounds();

        uint256 previousFeeBasisPoints = mintingFeeBasisPoints;
        mintingFeeBasisPoints = _newFeeBasisPoints;

        emit MintingFeeUpdated(previousFeeBasisPoints, _newFeeBasisPoints);
    }

    /**
     * @notice Updates the block cutoff after which BASE and GIFT minting is disabled
     * @dev Only the contract owner can update the cutoff block
     * @param _newCutoffBlock New block number used as the minting cutoff
     */
    function updateMintingCutoffBlock(uint256 _newCutoffBlock) public onlyOwner {
        uint256 previousCutoffBlock = mintingCutoffBlock;

        mintingCutoffBlock = _newCutoffBlock;

        emit MintingCutoffBlockUpdated(previousCutoffBlock, _newCutoffBlock);
    }

    /**
     * @notice Transfers accumulated minting fees for a given ERC20 to a recipient
     * @dev Only the contract owner can retrieve collected fees
     * @dev No action is taken if the recorded fee amount is zero
     * @param _erc20Contract ERC20 token address whose fees will be retrieved
     * @param _to Address that will receive the collected fees
     */
    function retrieveCollectedFees(address _erc20Contract, address _to) public onlyOwner {
        uint256 feeAmount = collectedFees[_erc20Contract];
        if (feeAmount == 0) return;

        collectedFees[_erc20Contract] = 0;
        if (!IERC20(_erc20Contract).transfer(_to, feeAmount)) revert TransferFailed();

        emit FeesRetrieved(_erc20Contract, _to, feeAmount);
    }

    /**
     * @notice Returns the BASE mint price, fee, and total price for a given ERC20
     * @dev The returned fee uses mintingFeeBasisPoints and MAX_BASIS_POINTS
     * @param _erc20Contract ERC20 token address to quote
     * @return mintPrice_ Base price excluding fee
     * @return fee_ Fee amount added on top of the base price
     * @return totalPrice_ Sum of mintPrice_ and fee_
     */
    function getMintingPriceWithFee(address _erc20Contract)
        public
        view
        returns (uint256 mintPrice_, uint256 fee_, uint256 totalPrice_)
    {
        mintPrice_ = mintPrices[_erc20Contract];
        fee_ = (mintPrice_ * mintingFeeBasisPoints) / MAX_BASIS_POINTS;
        totalPrice_ = mintPrice_ + fee_;
    }

    /**
     * @notice Returns the GIFT mint price, fee, and total price for WFRAX
     * @dev The returned fee uses mintingFeeBasisPoints and MAX_BASIS_POINTS
     * @return mintPrice_ Base GIFT price excluding fee
     * @return fee_ Fee amount added on top of the base price
     * @return totalPrice_ Sum of mintPrice_ and fee_
     */
    function getGiftMintingPriceWithFee() public view returns (uint256 mintPrice_, uint256 fee_, uint256 totalPrice_) {
        mintPrice_ = giftMintingPrice;
        fee_ = (mintPrice_ * mintingFeeBasisPoints) / MAX_BASIS_POINTS;
        totalPrice_ = mintPrice_ + fee_;
    }

    /**
     * @notice Returns the four underlying BASE token IDs referenced by a premium token
     * @dev The values are meaningful for FUSED tokens and are zeros for other token types
     * @param _premiumTokenId Token ID expected to be a FUSED token
     * @return tokenId1_ Underlying BASE token ID stored at index 0
     * @return tokenId2_ Underlying BASE token ID stored at index 1
     * @return tokenId3_ Underlying BASE token ID stored at index 2
     * @return tokenId4_ Underlying BASE token ID stored at index 3
     */
    function getUnderlyingTokenIds(uint256 _premiumTokenId)
        external
        view
        returns (uint256 tokenId1_, uint256 tokenId2_, uint256 tokenId3_, uint256 tokenId4_)
    {
        return (
            underlyingTokenIds[_premiumTokenId][0],
            underlyingTokenIds[_premiumTokenId][1],
            underlyingTokenIds[_premiumTokenId][2],
            underlyingTokenIds[_premiumTokenId][3]
        );
    }

    /**
     * @notice Returns underlying ERC20 contracts and balances associated with a tokenId
     * @dev Reverts if the tokenId is marked as NONEXISTENT
     * @dev SOULBOUND tokens return empty arrays as they do not represent ERC20 deposits
     * @dev BASE and GIFT tokens return a single ERC20 entry
     * @dev FUSED tokens return four entries derived from their underlying BASE tokens
     * @param _tokenId Token ID to query
     * @return erc20Contracts_ Array of ERC20 token addresses
     * @return balances_ Array of internal balances_ corresponding to erc20Contracts_
     */
    function getUnderlyingBalances(uint256 _tokenId)
        external
        view
        returns (address[] memory erc20Contracts_, uint256[] memory balances_)
    {
        if (tokenTypes[_tokenId] == TokenType.NONEXISTENT) revert TokenDoesNotExist();
        if (tokenTypes[_tokenId] == TokenType.SOULBOUND) return (new address[](0), new uint256[](0));

        if (tokenTypes[_tokenId] == TokenType.BASE || tokenTypes[_tokenId] == TokenType.GIFT) {
            erc20Contracts_ = new address[](1);
            balances_ = new uint256[](1);

            address erc20Contract = underlyingAssets[_tokenId][0];
            erc20Contracts_[0] = erc20Contract;
            balances_[0] = erc20Balances[_tokenId][erc20Contract];

            return (erc20Contracts_, balances_);
        }

        erc20Contracts_ = new address[](4);
        balances_ = new uint256[](4);

        for (uint256 i; i < 4;) {
            uint256 underlyingTokenId = underlyingTokenIds[_tokenId][i];
            address erc20Contract = underlyingAssets[underlyingTokenId][0];
            erc20Contracts_[i] = erc20Contract;
            balances_[i] = erc20Balances[underlyingTokenId][erc20Contract];

            unchecked {
                ++i;
            }
        }

        return (erc20Contracts_, balances_);
    }

    /**
     * @notice Returns the full list of supported ERC20s and their BASE mint prices
     * @dev The order corresponds to supportedErc20s indexes and may change when tokens are removed
     * @return erc20Contracts_ Array of supported ERC20 token addresses
     * @return mintPricesOut_ Array of mint prices aligned with erc20Contracts_
     */
    function getSupportedErc20s()
        external
        view
        returns (address[] memory erc20Contracts_, uint256[] memory mintPricesOut_)
    {
        erc20Contracts_ = new address[](totalNumberOfSupportedErc20s);
        mintPricesOut_ = new uint256[](totalNumberOfSupportedErc20s);

        for (uint256 i; i < totalNumberOfSupportedErc20s;) {
            address erc20Contract = supportedErc20s[i];
            erc20Contracts_[i] = erc20Contract;
            mintPricesOut_[i] = mintPrices[erc20Contract];

            unchecked {
                ++i;
            }
        }

        return (erc20Contracts_, mintPricesOut_);
    }

    /**
     * @notice Returns whether a tokenId is transferable under IERC6454 semantics
     * @dev This is a lightweight view that reflects the isNonTransferrable flag
     * @dev This function preserves the interface of IERC6454 even though _from and _to are unused
     * @param _tokenId Token ID to check
     * @param _from Current owner address provided for interface compliance
     * @param _to Intended recipient address provided for interface compliance
     * @return True if the token is not marked as non-transferable
     */
    function isTransferable(uint256 _tokenId, address _from, address _to) public view override returns (bool) {
        return !isNonTransferrable[_tokenId];
    }

    /**
     * @notice Returns the internal balance of an ERC20 held by a given tokenId
     * @dev This value reflects contract-side accounting rather than direct ERC20 balances
     * @param _erc20Contract ERC20 token address to query
     * @param _tokenId Token ID whose internal balance will be returned
     * @return Internal accounting balance for the ERC20 and _tokenId
     */
    function balanceOfERC20(address _erc20Contract, uint256 _tokenId) external view override returns (uint256) {
        return erc20Balances[_tokenId][_erc20Contract];
    }

    /**
     * @notice Disallows arbitrary ERC20 withdrawals from tokenIds
     * @dev ERC20 retrieval is only supported via burn to preserve accounting invariants
     * @param _erc20Contract ERC20 token address requested for withdrawal
     * @param _tokenId Token ID requested for withdrawal
     * @param _to Recipient address requested for withdrawal
     * @param _amount Amount requested for withdrawal
     * @param _data Unused calldata parameter for interface compliance
     */
    function transferHeldERC20FromToken(
        address _erc20Contract,
        uint256 _tokenId,
        address _to,
        uint256 _amount,
        bytes memory _data
    ) external pure override {
        revert TokensCanOnlyBeRetrievedByNftBurn();
    }

    /**
     * @notice Disallows arbitrary ERC20 deposits into tokenIds after mint
     * @dev ERC20 deposits are only supported during minting flows
     * @param _erc20Contract ERC20 token address requested for deposit
     * @param _tokenId Token ID requested for deposit
     * @param _amount Amount requested for deposit
     * @param _data Unused calldata parameter for interface compliance
     */
    function transferERC20ToToken(address _erc20Contract, uint256 _tokenId, uint256 _amount, bytes memory _data)
        external
        pure
        override
    {
        revert TokensCanOnlyBeDepositedByNftMint();
    }

    /**
     * @notice Returns the number of ERC20 transfers executed out of a tokenId
     * @dev The nonce increments for each underlying asset transferred during burn
     * @param _tokenId Token ID to query
     * @return Current outbound transfer nonce value
     */
    function erc20TransferOutNonce(uint256 _tokenId) external view override returns (uint256) {
        return transferOutNonces[_tokenId];
    }

    /**
     * @notice Fuses four BASE tokens into a single FUSED premium token
     * @dev The caller must own all four tokens and each must be of type BASE
     * @dev All four BASE tokens must have distinct underlying ERC20 assets
     * @dev The BASE tokens are transferred into the contract as custody for the FUSED token
     * @param _tokenId1 First BASE token ID to fuse
     * @param _tokenId2 Second BASE token ID to fuse
     * @param _tokenId3 Third BASE token ID to fuse
     * @param _tokenId4 Fourth BASE token ID to fuse
     * @return premiumTokenId_ Newly minted FUSED token ID
     */
    function fuseTokens(uint256 _tokenId1, uint256 _tokenId2, uint256 _tokenId3, uint256 _tokenId4)
        public
        returns (uint256 premiumTokenId_)
    {
        if (
            ownerOf(_tokenId1) != msg.sender || ownerOf(_tokenId2) != msg.sender || ownerOf(_tokenId3) != msg.sender
                || ownerOf(_tokenId4) != msg.sender
        ) revert OnlyTokenOwnerCanFuseTokens();

        if (
            tokenTypes[_tokenId1] != TokenType.BASE || tokenTypes[_tokenId2] != TokenType.BASE
                || tokenTypes[_tokenId3] != TokenType.BASE || tokenTypes[_tokenId4] != TokenType.BASE
        ) revert CanOnlyFuseBaseTokens();

        if (
            underlyingAssets[_tokenId1][0] == underlyingAssets[_tokenId2][0]
                || underlyingAssets[_tokenId1][0] == underlyingAssets[_tokenId3][0]
                || underlyingAssets[_tokenId1][0] == underlyingAssets[_tokenId4][0]
                || underlyingAssets[_tokenId2][0] == underlyingAssets[_tokenId3][0]
                || underlyingAssets[_tokenId2][0] == underlyingAssets[_tokenId4][0]
                || underlyingAssets[_tokenId3][0] == underlyingAssets[_tokenId4][0]
        ) revert SameTokenUnderlyingAssets();

        premiumTokenId_ = nextPremiumTokenId;

        _update(address(this), _tokenId1, msg.sender);
        _update(address(this), _tokenId2, msg.sender);
        _update(address(this), _tokenId3, msg.sender);
        _update(address(this), _tokenId4, msg.sender);

        _safeMint(msg.sender, premiumTokenId_);
        _setTokenURI(premiumTokenId_, premiumTokenUri);

        // Assign the fused tokens to the premium token, so they can be extracted when unfusing them
        underlyingTokenIds[premiumTokenId_][0] = _tokenId1;
        underlyingTokenIds[premiumTokenId_][1] = _tokenId2;
        underlyingTokenIds[premiumTokenId_][2] = _tokenId3;
        underlyingTokenIds[premiumTokenId_][3] = _tokenId4;
        tokenTypes[premiumTokenId_] = TokenType.FUSED;

        nextPremiumTokenId += 1;

        emit TokenFused(msg.sender, _tokenId1, _tokenId2, _tokenId3, _tokenId4, premiumTokenId_);
    }

    /**
     * @notice Burns a FUSED token and returns its four underlying BASE tokens to the owner
     * @dev The caller must own the premium token and it must be of type FUSED
     * @dev Underlying token references are cleared after successful unfuse
     * @param _premiumTokenId FUSED token ID to unfuse
     * @return tokenId1_ First underlying BASE token ID returned
     * @return tokenId2_ Second underlying BASE token ID returned
     * @return tokenId3_ Third underlying BASE token ID returned
     * @return tokenId4_ Fourth underlying BASE token ID returned
     */
    function unfuseTokens(uint256 _premiumTokenId)
        public
        returns (uint256 tokenId1_, uint256 tokenId2_, uint256 tokenId3_, uint256 tokenId4_)
    {
        if (ownerOf(_premiumTokenId) != msg.sender) {
            revert OnlyTokenOwnerCanUnfuseTokens();
        }
        if (tokenTypes[_premiumTokenId] != TokenType.FUSED) revert CanOnlyUnfuseFusedTokens();

        tokenId1_ = underlyingTokenIds[_premiumTokenId][0];
        tokenId2_ = underlyingTokenIds[_premiumTokenId][1];
        tokenId3_ = underlyingTokenIds[_premiumTokenId][2];
        tokenId4_ = underlyingTokenIds[_premiumTokenId][3];

        _burn(_premiumTokenId);
        tokenTypes[_premiumTokenId] = TokenType.NONEXISTENT;

        underlyingTokenIds[_premiumTokenId][0] = 0;
        underlyingTokenIds[_premiumTokenId][1] = 0;
        underlyingTokenIds[_premiumTokenId][2] = 0;
        underlyingTokenIds[_premiumTokenId][3] = 0;

        _update(msg.sender, tokenId1_, address(this));
        _update(msg.sender, tokenId2_, address(this));
        _update(msg.sender, tokenId3_, address(this));
        _update(msg.sender, tokenId4_, address(this));
        emit TokenUnfused(msg.sender, tokenId1_, tokenId2_, tokenId3_, tokenId4_, _premiumTokenId);
    }

    // ********** ONFT functional overrides **********

    /**
     * @notice Returns the token address used by the ONFT interface
     * @dev For ONFT721 this must be the address of the NFT contract itself
     * @return Address of this contract
     */
    function token() external view override returns (address) {
        return address(this);
    }

    /**
     * @notice Indicates whether explicit approvals are required for bridging operations
     * @dev The contract opts into a no-approval bridging model in ONFT721Core
     * @return False indicating approvals are not required
     */
    function approvalRequired() public view override returns (bool) {
        return false;
    }

    // ********** Internal functions to facilitate the ERC6454 functionality **********

    /**
     * @notice Enforces soulbound restrictions during standard transfers and burns
     * @dev The check is bypassed during bridge operations to allow _debit and _credit flows
     * @param _tokenId Token ID to validate for transferability
     */
    function _soulboundCheck(uint256 _tokenId) internal view {
        if (!_isBridgeOperation && isNonTransferrable[_tokenId]) revert CannotTransferSoulboundToken();
    }

    // ********** Internal functions to facilitate the ERC7590 functionality **********

    /**
     * @notice Transfers a recorded ERC20 balance from a tokenId to a recipient
     * @dev Used during burn to return underlying ERC20 assets to the token owner
     * @dev Reverts if the internal balance is insufficient or the ERC20 transfer fails
     * @param _erc20Contract ERC20 token address to transfer
     * @param _tokenId Token ID whose internal balance will be debited
     * @param _to Recipient address that will receive the ERC20
     * @param _amount Amount of ERC20 to transfer based on internal accounting
     */
    function _transferHeldERC20FromToken(address _erc20Contract, uint256 _tokenId, address _to, uint256 _amount)
        internal
    {
        IERC20 erc20Token = IERC20(_erc20Contract);

        if (erc20Balances[_tokenId][_erc20Contract] < _amount) revert InsufficientBalance();

        erc20Balances[_tokenId][_erc20Contract] -= _amount;
        transferOutNonces[_tokenId]++;

        if (!erc20Token.transfer(_to, _amount)) revert TransferFailed();

        emit TransferredERC20(_erc20Contract, _tokenId, _to, _amount);
    }

    /**
     * @notice Transfers the configured BASE mint price plus fee into the contract for a new tokenId
     * @dev The price is read from mintPrices for the provided ERC20
     * @param _erc20Contract ERC20 token address used for payment
     * @param _tokenId Token ID being minted and credited with the deposit
     * @param _from Address paying the mint price and fee
     */
    function _transferERC20ToToken(address _erc20Contract, uint256 _tokenId, address _from) internal {
        uint256 price = mintPrices[_erc20Contract];

        _transferERC20ToToken(_erc20Contract, _tokenId, _from, price);
    }

    /**
     * @notice Transfers a specified ERC20 amount plus fee into the contract and credits internal balances
     * @dev Used for both BASE minting and GIFT minting with explicit amount inputs
     * @dev The fee is recorded in collectedFees and the net amount is recorded in erc20Balances
     * @param _erc20Contract ERC20 token address used for payment
     * @param _tokenId Token ID being minted and credited with the deposit
     * @param _from Address paying the amount and fee
     * @param _amount Net _amount to credit to the _tokenId excluding fee
     */
    function _transferERC20ToToken(address _erc20Contract, uint256 _tokenId, address _from, uint256 _amount) internal {
        IERC20 erc20Token = IERC20(_erc20Contract);
        uint256 fee = (_amount * mintingFeeBasisPoints) / MAX_BASIS_POINTS;
        uint256 amountWithFee = _amount + fee;

        if (erc20Token.allowance(_from, address(this)) < amountWithFee) revert InsufficientAllowance();
        if (erc20Token.balanceOf(_from) < amountWithFee) revert InsufficientBalance();

        if (!erc20Token.transferFrom(_from, address(this), amountWithFee)) revert TransferFailed();

        erc20Balances[_tokenId][_erc20Contract] += _amount;
        collectedFees[_erc20Contract] += fee;

        emit ReceivedERC20(_erc20Contract, _tokenId, _from, _amount);
        emit FeeCollected(_erc20Contract, _from, fee);
    }

    // ********** Internal functions to facilitate the ONFT operations **********

    /**
     * @notice Performs a bridge-aware burn that preserves token-linked ERC20 state
     * @dev This is not a full burn of storage and is used by _debit to represent
     *  a token leaving the source chain
     * @param _owner Current owner of the token being bridged out
     * @param _tokenId Token ID to bridge-burn
     */
    function _bridgeBurn(address _owner, uint256 _tokenId) internal {
        _isBridgeOperation = true;
        // Token should only be burned, but the state including ERC20 balances should be preserved
        _update(address(0), _tokenId, _owner);
        _isBridgeOperation = false;
    }

    /**
     * @notice Debits a token from the source chain during an ONFT send
     * @dev Validates approval when the caller is not the owner
     * @dev Uses _bridgeBurn to preserve ERC20 state for later credit on the destination chain
     * @param _from Address initiating the debit which must be owner or approved
     * @param _tokenId Token ID to debit from the source chain
     * @param _dstEid Destination endpoint ID provided by ONFT721Core (unused)
     */
    function _debit(address _from, uint256 _tokenId, uint32 _dstEid) internal override {
        address owner = ownerOf(_tokenId);

        if (_from != owner && !isApprovedForAll(owner, _from) && getApproved(_tokenId) != _from) {
            revert ERC721InsufficientApproval(_from, _tokenId);
        }

        _bridgeBurn(owner, _tokenId);
    }

    /**
     * @notice Credits a token on the destination chain during an ONFT receive
     * @dev Reverts if the token already exists on the destination chain
     * @dev Uses a bridge-aware update that bypasses soulbound checks
     * @param _to Address that will receive ownership on the destination chain
     * @param _tokenId Token ID to credit on the destination chain
     * @param _srcEid Source endpoint ID provided by ONFT721Core
     */
    function _credit(address _to, uint256 _tokenId, uint32 _srcEid) internal override {
        if (_ownerOf(_tokenId) != address(0)) revert TokenAlreadyExists(_tokenId);

        _isBridgeOperation = true;
        _update(_to, _tokenId, address(0));
        _isBridgeOperation = false;
    }

    /**
     * @notice Builds the ONFT message and options payload for cross-chain sends
     * @dev Encodes tokenURI and soulbound flag into the composed message
     * @dev Reverts if the receiver is zero or if a soulbound token is sent to a non-owner address
     * @param _sendParam SendParam struct containing destination and token data
     * @return _message Encoded ONFT message to be dispatched
     * @return _options Encoded LayerZero options for the send
     */
    function _buildMsgAndOptions(SendParam calldata _sendParam)
        internal
        view
        override
        returns (bytes memory _message, bytes memory _options)
    {
        if (_sendParam.to == bytes32(0)) revert InvalidReceiver();

        string memory tokenUri = tokenURI(_sendParam.tokenId);
        bool isSoulbound = isNonTransferrable[_sendParam.tokenId];
        bytes memory composedMessage = abi.encode(tokenUri, isSoulbound);

        if (isSoulbound && _sendParam.to.bytes32ToAddress() != ownerOf(_sendParam.tokenId)) {
            revert CannotTransferSoulboundToken();
        }

        bool hasCompose;
        (_message, hasCompose) = ONFT721MsgCodec.encode(_sendParam.to, _sendParam.tokenId, composedMessage);

        uint16 msgType = hasCompose ? SEND_AND_COMPOSE : SEND;
        _options = combineOptions(_sendParam.dstEid, msgType, _sendParam.extraOptions);

        address inspector = msgInspector;
        if (inspector != address(0)) IOAppMsgInspector(inspector).inspect(_message, _options);
    }

    /**
     * @notice Receives a composed ONFT message and reconstructs token state on the destination chain
     * @dev Expects a composed message that includes tokenURI and soulbound flag
     * @dev Calls _credit before applying the token URI and soulbound flag locally
     * @param _origin Origin struct containing srcEid and nonce data
     * @param _guid Global unique identifier for the LayerZero message
     * @param _message Encoded ONFT message containing composed payload
     * @param _executor Unused executor parameter for LayerZero interface compatibility
     * @param _executorData Unused executor data parameter for LayerZero interface compatibility
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _executorData
    ) internal override {
        address toAddress = _message.sendTo().bytes32ToAddress();
        uint256 tokenId = _message.tokenId();

        if (!_message.isComposed()) revert MissingComposedMessage();

        bytes memory rawCompose = _message.composeMsg();
        bytes memory rawMessage = rawCompose;
        uint256 len;
        assembly {
            len := mload(rawCompose)
            // shift pointer forward by 32 bytes (skip fromOApp word)
            rawMessage := add(rawMessage, 32)
            // set length = originalLength - 32
            mstore(rawMessage, sub(len, 32))
        }

        (string memory tokenUri, bool isSoulbound) = abi.decode(rawMessage, (string, bool));

        _credit(toAddress, tokenId, _origin.srcEid);
        _setTokenURI(tokenId, tokenUri);
        isNonTransferrable[tokenId] = isSoulbound;

        bytes32 composeFrom = ONFTComposeMsgCodec.addressToBytes32(address(this));
        bytes memory composeInnerMsg = abi.encode(tokenUri, isSoulbound);
        bytes memory composeMsg = abi.encodePacked(composeFrom, composeInnerMsg);

        bytes memory composedMsgEncoded = ONFTComposeMsgCodec.encode(_origin.nonce, _origin.srcEid, composeMsg);
        endpoint.sendCompose(toAddress, _guid, 0, composedMsgEncoded);

        emit ONFTReceived(_guid, _origin.srcEid, toAddress, tokenId);
    }

    // ********** The following functions are overrides required by Solidity. **********

    /**
     * @notice Central transfer hook used by ERC721, Enumerable, and Pausable logic
     * @dev Enforces soulbound rules via _soulboundCheck before delegating to OZ logic
     * @param _to Address receiving the token
     * @param _tokenId Token ID being updated
     * @param _auth Address attempting to authorize the update
     * @return Previous owner address returned by the parent implementation
     */
    function _update(address _to, uint256 _tokenId, address _auth)
        internal
        override(ERC721, ERC721Enumerable, ERC721Pausable)
        returns (address)
    {
        _soulboundCheck(_tokenId);
        return super._update(_to, _tokenId, _auth);
    }

    /**
     * @notice Resolves the multiple inheritance requirement for _increaseBalance
     * @dev Delegates to the OZ implementation to preserve Enumerable invariants
     * @param _account Address whose balance is increased
     * @param _value Amount of balance increase
     */
    function _increaseBalance(address _account, uint128 _value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(_account, _value);
    }

    /**
     * @notice Sets a token URI and emits an IERC4906 MetadataUpdate event
     * @dev This override ensures metadata refresh signals are emitted for indexers
     * @param _tokenId Token ID whose URI is being updated
     * @param _tokenUri New token URI to assign
     */
    function _setTokenURI(uint256 _tokenId, string memory _tokenUri) internal override {
        super._setTokenURI(_tokenId, _tokenUri);
        emit MetadataUpdate(_tokenId);
    }

    /**
     * @notice Returns the token URI for a given tokenId
     * @dev Resolves the multiple inheritance between ERC721 and ERC721URIStorage
     * @param _tokenId Token ID whose URI will be returned
     * @return Token URI string
     */
    function tokenURI(uint256 _tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(_tokenId);
    }

    /**
     * @notice Declares supported interfaces across ERC721 extensions and custom standards
     * @dev Includes IERC7590, IERC6454, IERC4906, and IONFT721 support
     * @param _interfaceId Interface identifier to check
     * @return True if the interface is supported
     */
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(_interfaceId) || _interfaceId == type(IERC7590).interfaceId
            || _interfaceId == type(IERC6454).interfaceId || _interfaceId == type(IERC4906).interfaceId
            || _interfaceId == type(IONFT721).interfaceId;
    }
}
