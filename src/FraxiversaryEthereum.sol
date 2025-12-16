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
 * ========================= Fraxiversary ============================
 * ====================================================================
 * Fraxiversary NFT contract for the 5th anniversary of Frax Finance
 * Frax Finance: https://github.com/FraxFinance
 */

import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721Pausable} from "openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import {ERC721URIStorage} from "openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

import {IFraxiversaryErrors} from "./interfaces/IFraxiversaryErrors.sol";
import {IERC6454} from "./interfaces/IERC6454.sol";
import {IERC4906} from "openzeppelin-contracts/contracts/interfaces/IERC4906.sol";

import {ONFT721Core} from "@layerzerolabs/onft-evm/contracts/onft721/ONFT721Core.sol";
import {IONFT721, SendParam} from "@layerzerolabs/onft-evm/contracts/onft721/interfaces/IONFT721.sol";
import {ONFT721MsgCodec} from "@layerzerolabs/onft-evm/contracts/onft721/libs/ONFT721MsgCodec.sol";
import {ONFTComposeMsgCodec} from "@layerzerolabs/onft-evm/contracts/libs/ONFTComposeMsgCodec.sol";
import {IOAppMsgInspector} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppMsgInspector.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

/**
 * @title Fraxiversary
 * @author Frax Finance
 * @notice Fraxiversary Ethereum mirror smart contract to support cross-chain movement
 * @dev Soulbound restrictions are enforced via _update with a bridge-aware bypass used during ONFT operations
 * @dev Frax Reviewer(s) / Contributor(s)
 *  Jan Turk: https://github.com/ThunderDeliverer
 *  Sam Kazemian: https://github.com/samkazemian
 *  Bjirke (honorary mention for the original idea)
 */
contract Fraxiversary is
    ERC721,
    ERC721Enumerable,
    ERC721URIStorage,
    ERC721Pausable,
    IERC6454,
    IFraxiversaryErrors,
    ONFT721Core
{
    using ONFT721MsgCodec for bytes;
    using ONFT721MsgCodec for bytes32;

    /// @notice Marks whether a tokenId is non-transferable under IERC6454 rules
    /// @dev tokenId Fraxiversary token ID to check
    /// @dev nonTransferable True if the token is soulbound
    mapping(uint256 tokenId => bool nonTransferable) public isNonTransferrable;

    /// @dev Flag that disables soulbound checks during bridge operations
    bool private _isBridgeOperation;

    /**
     * @notice Initializes Fraxiversary with supply caps, fee settings, and ONFT configuration
     * @dev The mintingCutoffBlock is calculated assuming a fixed 2 second Fraxtal block time
     * @dev nextGiftTokenId starts immediately after the BASE tokenId range
     * @dev nextPremiumTokenId starts immediately after the GIFT tokenId range
     * @param _initialOwner Address that will own the contract and control admin functions
     * @param _lzEndpoint LayerZero endpoint used by ONFT721Core
     */
    constructor(address _initialOwner, address _lzEndpoint)
        ERC721("Fraxiversary", "FRAX5Y")
        ONFT721Core(_lzEndpoint, _initialOwner)
    {}

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
     * @notice Updates the metadata URI for a specific existing token
     * @dev Only the contract owner can update token URIs
     * @dev Reverts if the token has been burned or never existed
     * @param _tokenId Token ID whose metadata URI will be updated
     * @param _uri New metadata URI for the _tokenId
     */
    function updateSpecificTokenUri(uint256 _tokenId, string memory _uri) public onlyOwner {
        if (_ownerOf(_tokenId) == address(0)) revert TokenDoesNotExist();

        _setTokenURI(_tokenId, _uri);
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
        return super.supportsInterface(_interfaceId) || _interfaceId == type(IERC6454).interfaceId
            || _interfaceId == type(IERC4906).interfaceId || _interfaceId == type(IONFT721).interfaceId;
    }
}
