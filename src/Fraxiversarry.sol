// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

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

    address public constant WFRAX_ADDRESS = 0xFc00000000000000000000000000000000000002;
    uint256 public constant MAX_BASIS_POINTS = 1e4;

    mapping(address erc20 => uint256 price) public mintPrices;
    mapping(address erc20 => string uri) public baseAssetTokenUris;
    mapping(address erc20 => uint256 fee) public collectedFees;
    mapping(uint256 index => address erc20) public supportedErc20s;
    mapping(uint256 tokenId => mapping(uint256 index => address underlyingAsset)) public underlyingAssets;
    mapping(uint256 tokenId => uint256 numberOfAssets) public numberOfTokenUnderlyingAssets;
    mapping(uint256 tokenId => uint256 transferOutNonce) public transferOutNonces;
    mapping(uint256 tokenId => mapping(address erc20 => uint256 balance)) public erc20Balances;
    mapping(uint256 tokenId => mapping(uint256 index => uint256 underlyingTokenId)) public underlyingTokenIds;
    mapping(uint256 tokenId => bool nonTransferable) public isNonTransferrable;
    mapping(uint256 tokenId => TokenType tokenType) public tokenTypes;

    uint256 public nextTokenId;
    uint256 public nextGiftTokenId;
    uint256 public nextPremiumTokenId;
    uint256 public totalNumberOfSupportedErc20s;
    uint256 public mintingLimit;
    uint256 public giftMintingLimit;
    uint256 public giftMintingPrice;
    uint256 public mintingFeeBasisPoints;
    uint256 public mintingCutoffBlock;

    bool private _isBridgeOperation;

    enum TokenType {
        NONEXISTENT, // 0 - Token does not exist
        BASE, // 1 - NFTs that are minted using ERC20 tokens
        FUSED, // 2 - NFTs that are created by combining multiple base NFTs
        SOULBOUND, // 3 - NFTs that are non-transferable and tied to a specific user
        GIFT // 4 - NFTs that are gifted and have a separate minting limit and separate mint prices
    }

    string private giftTokenUri;
    string private premiumTokenUri;

    constructor(address initialOwner, address lzEndpoint)
        ERC721("Fraxiversarry", "FRAX5Y")
        ONFT721Core(lzEndpoint, initialOwner)
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

    function _baseURI() internal pure override returns (string memory) {
        return "";
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function paidMint(address erc20Contract) public returns (uint256) {
        if (block.number > mintingCutoffBlock) revert MintingPeriodOver();
        if (nextTokenId >= mintingLimit) revert MintingLimitReached();
        if (mintPrices[erc20Contract] == 0) revert UnsupportedToken();

        uint256 tokenId = nextTokenId++;
        _transferERC20ToToken(erc20Contract, tokenId, msg.sender);

        // Update underlying assets with the asset being used when minting
        underlyingAssets[tokenId][numberOfTokenUnderlyingAssets[tokenId]] = erc20Contract;
        numberOfTokenUnderlyingAssets[tokenId] += 1;

        // Set the token type to BASE
        tokenTypes[tokenId] = TokenType.BASE;

        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, baseAssetTokenUris[erc20Contract]);

        return tokenId;
    }

    function giftMint(address recipient) public returns (uint256) {
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

        _safeMint(recipient, tokenId);
        _setTokenURI(tokenId, giftTokenUri);

        emit GiftMinted(msg.sender, recipient, tokenId, giftMintingPrice);

        return tokenId;
    }

    function soulboundMint(address recipient, string memory tokenUri) public onlyOwner returns (uint256) {
        uint256 tokenId = nextPremiumTokenId;

        _safeMint(recipient, tokenId);
        _setTokenURI(tokenId, tokenUri);

        isNonTransferrable[tokenId] = true;
        tokenTypes[tokenId] = TokenType.SOULBOUND;

        nextPremiumTokenId += 1;

        emit NewSoulboundToken(recipient, tokenId);

        return tokenId;
    }

    function burn(uint256 tokenId) public override(ERC721Burnable) {
        if (msg.sender != ownerOf(tokenId)) revert OnlyTokenOwnerCanBurnTheToken();
        if (tokenTypes[tokenId] == TokenType.FUSED) revert UnfuseTokenBeforeBurning();
        // Transfer out the held ERC20 and then burn the NFT
        for (uint256 i; i < numberOfTokenUnderlyingAssets[tokenId];) {
            _transferHeldERC20FromToken(
                underlyingAssets[tokenId][i], tokenId, msg.sender, erc20Balances[tokenId][underlyingAssets[tokenId][i]]
            );

            unchecked {
                ++i;
            }
        }
        numberOfTokenUnderlyingAssets[tokenId] = 0;
        super.burn(tokenId);
        tokenTypes[tokenId] = TokenType.NONEXISTENT;
    }

    function setBaseAssetTokenUri(address erc20Contract, string memory uri) public onlyOwner {
        baseAssetTokenUris[erc20Contract] = uri;
    }

    function setGiftTokenUri(string memory uri) public onlyOwner {
        giftTokenUri = uri;
    }

    function setPremiumTokenUri(string memory uri) public onlyOwner {
        premiumTokenUri = uri;
    }

    function refreshBaseTokenUris(uint256 firstTokenId, uint256 lastTokenId) public onlyOwner {
        if (lastTokenId < firstTokenId) revert InvalidRange();
        if (lastTokenId >= nextTokenId) revert OutOfBounds();

        for (uint256 tokenId = firstTokenId; tokenId <= lastTokenId;) {
            address underlyingAsset = underlyingAssets[tokenId][0];

            // Only update if there is an underlying asset (if the token exists)
            if (underlyingAsset != address(0) && erc20Balances[tokenId][underlyingAsset] > 0) {
                _setTokenURI(tokenId, baseAssetTokenUris[underlyingAsset]);
            }

            unchecked {
                ++tokenId;
            }
        }

        emit BatchMetadataUpdate(firstTokenId, lastTokenId);
    }

    function refreshGiftTokenUris(uint256 firstTokenId, uint256 lastTokenId) public onlyOwner {
        if (firstTokenId < mintingLimit) revert OutOfBounds();
        if (lastTokenId < firstTokenId) revert InvalidRange();
        if (lastTokenId >= nextGiftTokenId) revert OutOfBounds();

        for (uint256 tokenId = firstTokenId; tokenId <= lastTokenId;) {
            // Only update if there is an underlying asset (if the token exists)
            if (erc20Balances[tokenId][WFRAX_ADDRESS] > 0) {
                _setTokenURI(tokenId, giftTokenUri);
            }

            unchecked {
                ++tokenId;
            }
        }

        emit BatchMetadataUpdate(firstTokenId, lastTokenId);
    }

    function refreshPremiumTokenUris(uint256 firstTokenId, uint256 lastTokenId) public onlyOwner {
        if (lastTokenId < firstTokenId) revert InvalidRange();
        if (firstTokenId < mintingLimit + giftMintingLimit) revert OutOfBounds();
        if (lastTokenId >= nextPremiumTokenId) revert OutOfBounds();

        for (uint256 tokenId = firstTokenId; tokenId <= lastTokenId;) {
            // Only update if the token has underlying tokens (this ensures that the token exists and that it isn't soulbound)
            if (underlyingTokenIds[tokenId][0] != 0 || underlyingTokenIds[tokenId][1] != 0) {
                // This is in case the first underlying token ID is 0

                _setTokenURI(tokenId, premiumTokenUri);
            }

            unchecked {
                ++tokenId;
            }
        }

        emit BatchMetadataUpdate(firstTokenId, lastTokenId);
    }

    function updateSpecificTokenUri(uint256 tokenId, string memory uri) public onlyOwner {
        if (tokenTypes[tokenId] == TokenType.NONEXISTENT) revert TokenDoesNotExist();

        _setTokenURI(tokenId, uri);
    }

    function updateBaseAssetMintPrice(address erc20Contract, uint256 mintPrice) public onlyOwner {
        uint256 previousMintPrice = mintPrices[erc20Contract];
        if (previousMintPrice == mintPrice) revert AttemptigToSetExistingMintPrice();

        mintPrices[erc20Contract] = mintPrice;

        if (previousMintPrice == 0) {
            supportedErc20s[totalNumberOfSupportedErc20s] = erc20Contract;
            totalNumberOfSupportedErc20s += 1;
        }

        if (mintPrice == 0) {
            uint256 erc20Index = type(uint256).max;

            for (uint256 i; i < totalNumberOfSupportedErc20s;) {
                if (supportedErc20s[i] == erc20Contract) {
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

        emit MintPriceUpdated(erc20Contract, previousMintPrice, mintPrice);
    }

    function updateGiftMintingPrice(uint256 newPrice) public onlyOwner {
        if (newPrice <= 1e18) revert InvalidGiftMintPrice(); // Minimum 1 WFRAX
        uint256 previousPrice = giftMintingPrice;
        if (previousPrice == newPrice) revert AttemptigToSetExistingMintPrice();

        giftMintingPrice = newPrice;

        emit GiftMintPriceUpdated(previousPrice, newPrice);
    }

    function updateMintingFeeBasisPoints(uint256 newFeeBasisPoints) public onlyOwner {
        if (newFeeBasisPoints > MAX_BASIS_POINTS) revert OutOfBounds();

        uint256 previousFeeBasisPoints = mintingFeeBasisPoints;
        mintingFeeBasisPoints = newFeeBasisPoints;

        emit MintingFeeUpdated(previousFeeBasisPoints, newFeeBasisPoints);
    }

    function updateMintingCutoffBlock(uint256 newCutoffBlock) public onlyOwner {
        uint256 previousCutoffBlock = mintingCutoffBlock;

        mintingCutoffBlock = newCutoffBlock;

        emit MintingCutoffBlockUpdated(previousCutoffBlock, newCutoffBlock);
    }

    function retrieveCollectedFees(address erc20Contract, address to) public onlyOwner {
        uint256 feeAmount = collectedFees[erc20Contract];
        if (feeAmount == 0) return;

        collectedFees[erc20Contract] = 0;
        if (!IERC20(erc20Contract).transfer(to, feeAmount)) revert TransferFailed();

        emit FeesRetrieved(erc20Contract, to, feeAmount);
    }

    function getMintingPriceWithFee(address erc20Contract)
        public
        view
        returns (uint256 mintPrice, uint256 fee, uint256 totalPrice)
    {
        mintPrice = mintPrices[erc20Contract];
        fee = (mintPrice * mintingFeeBasisPoints) / MAX_BASIS_POINTS;
        totalPrice = mintPrice + fee;
    }

    function getGiftMintingPriceWithFee() public view returns (uint256 mintPrice, uint256 fee, uint256 totalPrice) {
        mintPrice = giftMintingPrice;
        fee = (mintPrice * mintingFeeBasisPoints) / MAX_BASIS_POINTS;
        totalPrice = mintPrice + fee;
    }

    function getUnderlyingTokenIds(uint256 premiumTokenId)
        external
        view
        returns (uint256 tokenId1, uint256 tokenId2, uint256 tokenId3, uint256 tokenId4)
    {
        return (
            underlyingTokenIds[premiumTokenId][0],
            underlyingTokenIds[premiumTokenId][1],
            underlyingTokenIds[premiumTokenId][2],
            underlyingTokenIds[premiumTokenId][3]
        );
    }

    function getUnderlyingBalances(uint256 tokenId)
        external
        view
        returns (address[] memory erc20Contracts, uint256[] memory balances)
    {
        if (tokenTypes[tokenId] == TokenType.NONEXISTENT) revert TokenDoesNotExist();
        if (tokenTypes[tokenId] == TokenType.SOULBOUND) return (new address[](0), new uint256[](0));

        if (tokenTypes[tokenId] == TokenType.BASE || tokenTypes[tokenId] == TokenType.GIFT) {
            erc20Contracts = new address[](1);
            balances = new uint256[](1);

            address erc20Contract = underlyingAssets[tokenId][0];
            erc20Contracts[0] = erc20Contract;
            balances[0] = erc20Balances[tokenId][erc20Contract];

            return (erc20Contracts, balances);
        }

        erc20Contracts = new address[](4);
        balances = new uint256[](4);

        for (uint256 i; i < 4;) {
            uint256 underlyingTokenId = underlyingTokenIds[tokenId][i];
            address erc20Contract = underlyingAssets[underlyingTokenId][0];
            erc20Contracts[i] = erc20Contract;
            balances[i] = erc20Balances[underlyingTokenId][erc20Contract];

            unchecked {
                ++i;
            }
        }

        return (erc20Contracts, balances);
    }

    function getSupportedErc20s()
        external
        view
        returns (address[] memory erc20Contracts, uint256[] memory mintPricesOut)
    {
        erc20Contracts = new address[](totalNumberOfSupportedErc20s);
        mintPricesOut = new uint256[](totalNumberOfSupportedErc20s);

        for (uint256 i; i < totalNumberOfSupportedErc20s;) {
            address erc20Contract = supportedErc20s[i];
            erc20Contracts[i] = erc20Contract;
            mintPricesOut[i] = mintPrices[erc20Contract];

            unchecked {
                ++i;
            }
        }

        return (erc20Contracts, mintPricesOut);
    }

    // Implementtion of IERC6454 interface function
    function isTransferable(uint256 tokenId, address from, address to) public view override returns (bool) {
        return !isNonTransferrable[tokenId];
    }

    // Implementations of IERC7590 interface functions
    function balanceOfERC20(address erc20Contract, uint256 tokenId) external view override returns (uint256) {
        return erc20Balances[tokenId][erc20Contract];
    }

    function transferHeldERC20FromToken(
        address erc20Contract,
        uint256 tokenId,
        address to,
        uint256 amount,
        bytes memory data
    ) external pure override {
        revert TokensCanOnlyBeRetrievedByNftBurn();
    }

    function transferERC20ToToken(address erc20Contract, uint256 tokenId, uint256 amount, bytes memory data)
        external
        pure
        override
    {
        revert TokensCanOnlyBeDepositedByNftMint();
    }

    function erc20TransferOutNonce(uint256 tokenId) external view override returns (uint256) {
        return transferOutNonces[tokenId];
    }

    function fuseTokens(uint256 tokenId1, uint256 tokenId2, uint256 tokenId3, uint256 tokenId4)
        public
        returns (uint256 premiumTokenId)
    {
        if (
            ownerOf(tokenId1) != msg.sender || ownerOf(tokenId2) != msg.sender || ownerOf(tokenId3) != msg.sender
                || ownerOf(tokenId4) != msg.sender
        ) revert OnlyTokenOwnerCanFuseTokens();

        if (
            tokenTypes[tokenId1] != TokenType.BASE || tokenTypes[tokenId2] != TokenType.BASE
                || tokenTypes[tokenId3] != TokenType.BASE || tokenTypes[tokenId4] != TokenType.BASE
        ) revert CanOnlyFuseBaseTokens();

        if (
            underlyingAssets[tokenId1][0] == underlyingAssets[tokenId2][0]
                || underlyingAssets[tokenId1][0] == underlyingAssets[tokenId3][0]
                || underlyingAssets[tokenId1][0] == underlyingAssets[tokenId4][0]
                || underlyingAssets[tokenId2][0] == underlyingAssets[tokenId3][0]
                || underlyingAssets[tokenId2][0] == underlyingAssets[tokenId4][0]
                || underlyingAssets[tokenId3][0] == underlyingAssets[tokenId4][0]
        ) revert SameTokenUnderlyingAssets();

        premiumTokenId = nextPremiumTokenId;

        _update(address(this), tokenId1, msg.sender);
        _update(address(this), tokenId2, msg.sender);
        _update(address(this), tokenId3, msg.sender);
        _update(address(this), tokenId4, msg.sender);

        _safeMint(msg.sender, premiumTokenId);
        _setTokenURI(premiumTokenId, premiumTokenUri);

        // Assign the fused tokens to the premium token, so they can be extracted when unfusing them
        underlyingTokenIds[premiumTokenId][0] = tokenId1;
        underlyingTokenIds[premiumTokenId][1] = tokenId2;
        underlyingTokenIds[premiumTokenId][2] = tokenId3;
        underlyingTokenIds[premiumTokenId][3] = tokenId4;
        tokenTypes[premiumTokenId] = TokenType.FUSED;

        nextPremiumTokenId += 1;

        emit TokenFused(msg.sender, tokenId1, tokenId2, tokenId3, tokenId4, premiumTokenId);
    }

    function unfuseTokens(uint256 premiumTokenId)
        public
        returns (uint256 tokenId1, uint256 tokenId2, uint256 tokenId3, uint256 tokenId4)
    {
        if (ownerOf(premiumTokenId) != msg.sender) {
            revert OnlyTokenOwnerCanUnfuseTokens();
        }
        if (tokenTypes[premiumTokenId] != TokenType.FUSED) revert CanOnlyUnfuseFusedTokens();

        tokenId1 = underlyingTokenIds[premiumTokenId][0];
        tokenId2 = underlyingTokenIds[premiumTokenId][1];
        tokenId3 = underlyingTokenIds[premiumTokenId][2];
        tokenId4 = underlyingTokenIds[premiumTokenId][3];

        _burn(premiumTokenId);
        tokenTypes[premiumTokenId] = TokenType.NONEXISTENT;

        underlyingTokenIds[premiumTokenId][0] = 0;
        underlyingTokenIds[premiumTokenId][1] = 0;
        underlyingTokenIds[premiumTokenId][2] = 0;
        underlyingTokenIds[premiumTokenId][3] = 0;

        _update(msg.sender, tokenId1, address(this));
        _update(msg.sender, tokenId2, address(this));
        _update(msg.sender, tokenId3, address(this));
        _update(msg.sender, tokenId4, address(this));
        emit TokenUnfused(msg.sender, tokenId1, tokenId2, tokenId3, tokenId4, premiumTokenId);
    }

    // ********** ONFT functional overrides **********

    function token() external view override returns (address) {
        return address(this);
    }

    function approvalRequired() public view override returns (bool) {
        return false;
    }

    // ********** Internal functions to facilitate the ERC6454 functionality **********

    function _soulboundCheck(uint256 tokenId) internal view {
        if (!_isBridgeOperation && isNonTransferrable[tokenId]) revert CannotTransferSoulboundToken();
    }

    // ********** Internal functions to facilitate the ERC7590 functionality **********

    function _transferHeldERC20FromToken(address erc20Contract, uint256 tokenId, address to, uint256 amount) internal {
        IERC20 erc20Token = IERC20(erc20Contract);

        if (erc20Balances[tokenId][erc20Contract] < amount) revert InsufficientBalance();

        erc20Balances[tokenId][erc20Contract] -= amount;
        transferOutNonces[tokenId]++;

        if (!erc20Token.transfer(to, amount)) revert TransferFailed();

        emit TransferredERC20(erc20Contract, tokenId, to, amount);
    }

    function _transferERC20ToToken(address erc20Contract, uint256 tokenId, address from) internal {
        uint256 price = mintPrices[erc20Contract];

        _transferERC20ToToken(erc20Contract, tokenId, from, price);
    }

    function _transferERC20ToToken(address erc20Contract, uint256 tokenId, address from, uint256 amount) internal {
        IERC20 erc20Token = IERC20(erc20Contract);
        uint256 fee = (amount * mintingFeeBasisPoints) / MAX_BASIS_POINTS;
        uint256 amountWithFee = amount + fee;

        if (erc20Token.allowance(from, address(this)) < amountWithFee) revert InsufficientAllowance();
        if (erc20Token.balanceOf(from) < amountWithFee) revert InsufficientBalance();

        if (!erc20Token.transferFrom(from, address(this), amountWithFee)) revert TransferFailed();

        erc20Balances[tokenId][erc20Contract] += amount;
        collectedFees[erc20Contract] += fee;

        emit ReceivedERC20(erc20Contract, tokenId, from, amount);
        emit FeeCollected(erc20Contract, from, fee);
    }

    // ********** Internal functions to facilitate the ONFT operations **********

    function _bridgeBurn(address owner, uint256 tokenId) internal {
        _isBridgeOperation = true;
        // Token should only be burned, but the state including ERC20 balances should be preserved
        _update(address(0), tokenId, owner);
        _isBridgeOperation = false;
    }

    function _debit(
        address from,
        uint256 tokenId,
        uint32 /*dstEid*/
    )
        internal
        override
    {
        address owner = ownerOf(tokenId);

        if (from != owner && !isApprovedForAll(owner, from) && getApproved(tokenId) != from) {
            revert ERC721InsufficientApproval(from, tokenId);
        }

        _bridgeBurn(owner, tokenId);
    }

    function _credit(
        address to,
        uint256 tokenId,
        uint32 /*srcEid*/
    )
        internal
        override
    {
        if (_ownerOf(tokenId) != address(0)) revert TokenAlreadyExists(tokenId);

        _isBridgeOperation = true;
        _update(to, tokenId, address(0));
        _isBridgeOperation = false;
    }

    function _buildMsgAndOptions(SendParam calldata sendParam)
        internal
        view
        override
        returns (bytes memory message, bytes memory options)
    {
        if (sendParam.to == bytes32(0)) revert InvalidReceiver();

        string memory tokenUri = tokenURI(sendParam.tokenId);
        bool isSoulbound = isNonTransferrable[sendParam.tokenId];
        bytes memory composedMessage = abi.encode(tokenUri, isSoulbound);

        if (isSoulbound && sendParam.to.bytes32ToAddress() != ownerOf(sendParam.tokenId)) {
            revert CannotTransferSoulboundToken();
        }

        bool hasCompose;
        (message, hasCompose) = ONFT721MsgCodec.encode(sendParam.to, sendParam.tokenId, composedMessage);

        uint16 msgType = hasCompose ? SEND_AND_COMPOSE : SEND;
        options = combineOptions(sendParam.dstEid, msgType, sendParam.extraOptions);

        address inspector = msgInspector;
        if (inspector != address(0)) IOAppMsgInspector(inspector).inspect(message, options);
    }

    function _lzReceive(Origin calldata origin, bytes32 guid, bytes calldata message, address, bytes calldata)
        internal
        override
    {
        address toAddress = message.sendTo().bytes32ToAddress();
        uint256 tokenId = message.tokenId();

        if (!message.isComposed()) revert MissingComposedMessage();

        bytes memory rawCompose = message.composeMsg();
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

        _credit(toAddress, tokenId, origin.srcEid);
        _setTokenURI(tokenId, tokenUri);
        isNonTransferrable[tokenId] = isSoulbound;

        bytes32 composeFrom = ONFTComposeMsgCodec.addressToBytes32(address(this));
        bytes memory composeInnerMsg = abi.encode(tokenUri, isSoulbound);
        bytes memory composeMsg = abi.encodePacked(composeFrom, composeInnerMsg);

        bytes memory composedMsgEncoded = ONFTComposeMsgCodec.encode(origin.nonce, origin.srcEid, composeMsg);
        endpoint.sendCompose(toAddress, guid, 0, composedMsgEncoded);

        emit ONFTReceived(guid, origin.srcEid, toAddress, tokenId);
    }

    // ********** The following functions are overrides required by Solidity. **********

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable, ERC721Pausable)
        returns (address)
    {
        _soulboundCheck(tokenId);
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal override {
        super._setTokenURI(tokenId, _tokenURI);
        emit MetadataUpdate(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId) || interfaceId == type(IERC7590).interfaceId
            || interfaceId == type(IERC6454).interfaceId || interfaceId == type(IERC4906).interfaceId
            || interfaceId == type(IONFT721).interfaceId;
    }
}
