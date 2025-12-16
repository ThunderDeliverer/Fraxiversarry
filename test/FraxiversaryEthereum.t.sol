// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";

import {Fraxiversary} from "../src/FraxiversaryEthereum.sol";
import {IFraxiversaryErrors} from "../src/interfaces/IFraxiversaryErrors.sol";
import {IFraxiversaryEvents} from "../src/interfaces/IFraxiversaryEvents.sol";

import {MockLzEndpoint} from "./mocks/MockLzEndpoint.sol";

import {IONFT721, SendParam} from "@layerzerolabs/onft-evm/contracts/onft721/interfaces/IONFT721.sol";
import {ONFT721MsgCodec} from "@layerzerolabs/onft-evm/contracts/onft721/libs/ONFT721MsgCodec.sol";
import {ONFTComposeMsgCodec} from "@layerzerolabs/onft-evm/contracts/libs/ONFTComposeMsgCodec.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

import {IERC6454} from "../src/interfaces/IERC6454.sol";
import {IERC4906} from "openzeppelin-contracts/contracts/interfaces/IERC4906.sol";
import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

contract FraxiversaryEthereumTest is Test, IFraxiversaryErrors, IFraxiversaryEvents {
    using ONFT721MsgCodec for bytes;
    using ONFT721MsgCodec for bytes32;

    MockLzEndpoint endpoint;
    FraxiversaryEthHarness nft;

    address owner = address(0xA11CE);
    address alice = address(0xB0B);
    address bob = address(0xCAFE);

    function setUp() public {
        endpoint = new MockLzEndpoint();
        nft = new FraxiversaryEthHarness(owner, address(endpoint));
    }

    // ------------------------------------------------------------
    // Ownership & admin controls
    // ------------------------------------------------------------

    function testOnlyOwnerPauseUnpause() public {
        vm.prank(alice);
        vm.expectRevert();
        nft.pause();

        vm.prank(owner);
        nft.pause();

        vm.prank(owner);
        nft.unpause();
    }

    function testOnlyOwnerUpdateSpecificTokenUri() public {
        uint256 id = 1;

        vm.prank(owner);
        vm.expectRevert(TokenDoesNotExist.selector);
        nft.updateSpecificTokenUri(id, "ipfs://nope");

        nft.testMint(alice, id, "ipfs://old");

        vm.prank(alice);
        vm.expectRevert();
        nft.updateSpecificTokenUri(id, "ipfs://new");

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit IERC4906.MetadataUpdate(id);
        nft.updateSpecificTokenUri(id, "ipfs://new");

        assertEq(nft.tokenURI(id), "ipfs://new");
    }

    // ------------------------------------------------------------
    // Soulbound behavior (IERC6454 + internal gate)
    // ------------------------------------------------------------

    function testIsTransferableReflectsFlag() public {
        uint256 id = 1;
        nft.testMint(alice, id, "ipfs://x");

        assertTrue(nft.isTransferable(id, alice, bob));

        nft.testSetSoulbound(id, true);
        assertFalse(nft.isTransferable(id, alice, bob));
    }

    function testSoulboundBlocksNormalTransfer() public {
        uint256 id = 1;
        nft.testMint(alice, id, "ipfs://x");
        nft.testSetSoulbound(id, true);

        vm.prank(alice);
        vm.expectRevert(CannotTransferSoulboundToken.selector);
        nft.transferFrom(alice, bob, id);
    }

    function testPauseBlocksTransfer() public {
        uint256 id = 1;
        nft.testMint(alice, id, "ipfs://x");

        vm.prank(owner);
        nft.pause();

        vm.prank(alice);
        vm.expectRevert();
        nft.transferFrom(alice, bob, id);
    }

    // ------------------------------------------------------------
    // Bridge-specific behavior
    // ------------------------------------------------------------

    function testDebitBypassesSoulboundCheck() public {
        uint256 id = 1;
        nft.testMint(alice, id, "ipfs://x");
        nft.testSetSoulbound(id, true);

        nft.exposedDebit(alice, id, 30101);

        assertEq(nft.ownerOfUnsafe(id), address(0));
    }

    function testDebitRequiresOwnerOrApproval() public {
        uint256 id = 1;
        nft.testMint(alice, id, "ipfs://x");

        vm.expectRevert(
            abi.encodeWithSelector(bytes4(keccak256("ERC721InsufficientApproval(address,uint256)")), bob, id)
        );
        nft.exposedDebit(bob, id, 30101);
    }

    function testCreditSetsOwnerWhenTokenAbsent() public {
        uint256 id = 1;

        nft.exposedCredit(alice, id, 30101);

        assertEq(nft.ownerOf(id), alice);
    }

    function testCreditRevertsIfTokenExists() public {
        uint256 id = 1;
        nft.testMint(alice, id, "ipfs://x");

        vm.expectRevert(abi.encodeWithSelector(TokenAlreadyExists.selector, id));
        nft.exposedCredit(bob, id, 30101);
    }

    // ------------------------------------------------------------
    // _buildMsgAndOptions
    // ------------------------------------------------------------

    function testBuildMsgAndOptionsRevertsOnZeroReceiver() public {
        uint256 id = 1;
        nft.testMint(alice, id, "ipfs://x");

        SendParam memory sp;
        sp.to = bytes32(0);
        sp.tokenId = id;
        sp.dstEid = 30101;

        vm.expectRevert(bytes4(keccak256("InvalidReceiver()")));
        nft.exposedBuildMsgAndOptions(sp);
    }

    function testBuildMsgAndOptionsRevertsWhenSoulboundToNotOwner() public {
        uint256 id = 1;
        nft.testMint(alice, id, "ipfs://x");
        nft.testSetSoulbound(id, true);

        SendParam memory sp;
        sp.to = bytes32(uint256(uint160(bob)));
        sp.tokenId = id;
        sp.dstEid = 30101;

        vm.expectRevert(CannotTransferSoulboundToken.selector);
        nft.exposedBuildMsgAndOptions(sp);
    }

    // ------------------------------------------------------------
    // _lzReceive path
    // ------------------------------------------------------------

    function testLzReceiveReconstructsUriAndSoulbound() public {
        uint256 id = 777;
        string memory uri = "ar://some-uri";

        // inner compose payload for the ONFT message
        bytes memory inner = abi.encode(uri, true);

        bytes32 toB32 = bytes32(uint256(uint160(alice)));
        (bytes memory message, bool hasCompose) = ONFT721MsgCodec.encode(toB32, id, inner);
        assertTrue(hasCompose);

        Origin memory origin;
        origin.srcEid = 30101;
        origin.nonce = 123;

        bytes32 guid = keccak256("guid");

        bytes32 composeFrom = ONFTComposeMsgCodec.addressToBytes32(address(nft));
        bytes memory composeInnerMsg = abi.encode(uri, true);
        bytes memory composeMsg = abi.encodePacked(composeFrom, composeInnerMsg);
        bytes memory composedMsgEncoded = ONFTComposeMsgCodec.encode(origin.nonce, origin.srcEid, composeMsg);

        vm.recordLogs();

        nft.exposedLzReceive(origin, guid, message, address(0), "");

        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 composeSig = keccak256("ComposeSent(address,bytes32,uint16,bytes)");

        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(endpoint) && logs[i].topics.length > 0 && logs[i].topics[0] == composeSig) {
                (address to, bytes32 g, uint16 index, bytes memory msgData) =
                    abi.decode(logs[i].data, (address, bytes32, uint16, bytes));

                assertEq(to, alice);
                assertEq(g, guid);
                assertEq(index, 0);
                assertEq(msgData, composedMsgEncoded);

                found = true;
                break;
            }
        }

        assertTrue(found, "ComposeSent not emitted");

        assertEq(nft.ownerOf(id), alice);
        assertEq(nft.tokenURI(id), uri);
        assertTrue(nft.isNonTransferrable(id));
    }

    function testLzReceiveRevertsWithoutComposedMessageIfCodecMarksNonComposed() public {
        uint256 id = 1;

        bytes32 toB32 = bytes32(uint256(uint160(alice)));
        (bytes memory message, bool hasCompose) = ONFT721MsgCodec.encode(toB32, id, bytes(""));

        if (hasCompose) {
            return;
        }

        Origin memory origin;
        origin.srcEid = 30101;
        origin.nonce = 123;

        vm.expectRevert(MissingComposedMessage.selector);
        nft.exposedLzReceive(origin, keccak256("guid"), message, address(0), "");
    }

    // ------------------------------------------------------------
    // supportsInterface sanity
    // ------------------------------------------------------------

    function testSupportsInterface() public {
        assertTrue(nft.supportsInterface(type(IERC6454).interfaceId));
        assertTrue(nft.supportsInterface(type(IERC4906).interfaceId));
        assertTrue(nft.supportsInterface(type(IONFT721).interfaceId));
    }

    function testApprovalRequiredFalse() public {
        assertFalse(nft.approvalRequired());
    }

    function testTokenReturnsSelf() public {
        assertEq(nft.token(), address(nft));
    }

    // ------------------------------------------------------------
    // edge cases
    // ------------------------------------------------------------

    function testPauseBlocksDebit() public {
        uint256 id = 1;
        nft.testMint(alice, id, "ipfs://x");

        vm.prank(owner);
        nft.pause();

        vm.expectRevert();
        nft.exposedDebit(alice, id, 30101);
    }

    function testPauseBlocksCredit() public {
        uint256 id = 1;

        vm.prank(owner);
        nft.pause();

        vm.expectRevert();
        nft.exposedCredit(alice, id, 30101);
    }

    function testIsTransferableForNonexistentTokenDefaultsTrue() public {
        assertTrue(nft.isTransferable(999, alice, bob));
    }

    function testBuildMsgAndOptionsRevertsForNonexistentToken() public {
        SendParam memory sp;
        sp.to = bytes32(uint256(uint160(alice)));
        sp.tokenId = 12345;
        sp.dstEid = 30101;

        vm.expectRevert();
        nft.exposedBuildMsgAndOptions(sp);
    }

    function testBuildMsgAndOptionsEncodesUriAndFlag() public {
        uint256 id = 1;
        string memory uri = "ar://meta";

        nft.testMint(alice, id, uri);
        nft.testSetSoulbound(id, true);

        SendParam memory sp;
        sp.to = bytes32(uint256(uint160(alice)));
        sp.tokenId = id;
        sp.dstEid = 30101;

        (bytes memory message,) = nft.exposedBuildMsgAndOptions(sp);

        (bytes32 toB32, uint256 tokenId, bool isComposed, bytes memory compose) = nft.exposedDecodeONFT(message);

        assertEq(toB32, sp.to);
        assertEq(tokenId, id);
        assertTrue(isComposed);

        bytes memory raw = compose;
        uint256 len;
        assembly {
            len := mload(compose)
            raw := add(raw, 32)
            mstore(raw, sub(len, 32))
        }

        (string memory decodedUri, bool decodedFlag) = abi.decode(raw, (string, bool));

        assertEq(decodedUri, uri);
        assertTrue(decodedFlag);
    }

    function testLzReceiveRevertsOnMalformedComposePayload() public {
        uint256 id = 1;
        bytes32 toB32 = bytes32(uint256(uint160(alice)));

        // Force a composed message with garbage inner bytes
        (bytes memory message, bool hasCompose) = ONFT721MsgCodec.encode(toB32, id, hex"deadbeef");
        assertTrue(hasCompose);

        Origin memory origin;
        origin.srcEid = 30101;
        origin.nonce = 123;

        vm.expectRevert();
        nft.exposedLzReceive(origin, keccak256("guid"), message, address(0), "");
    }

    function testLzReceiveEmitsONFTReceived() public {
        uint256 id = 2;
        string memory uri = "ar://x";
        bytes memory inner = abi.encode(uri, false);

        bytes32 toB32 = bytes32(uint256(uint160(alice)));
        (bytes memory message, bool hasCompose) = ONFT721MsgCodec.encode(toB32, id, inner);
        assertTrue(hasCompose);

        Origin memory origin;
        origin.srcEid = 30101;
        origin.nonce = 1;

        bytes32 guid = keccak256("g");

        vm.recordLogs();
        nft.exposedLzReceive(origin, guid, message, address(0), "");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("ONFTReceived(bytes32,uint32,address,uint256)");

        bool found;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(nft) && logs[i].topics.length > 0 && logs[i].topics[0] == sig) {
                found = true;
                break;
            }
        }

        assertTrue(found, "ONFTReceived not emitted");
    }

    function testDebitAllowsTokenApproval() public {
        uint256 id = 1;
        nft.testMint(alice, id, "ipfs://x");

        vm.prank(alice);
        nft.approve(bob, id);

        nft.exposedDebit(bob, id, 30101);
        assertEq(nft.ownerOfUnsafe(id), address(0));
    }

    function testDebitAllowsOperatorApproval() public {
        uint256 id = 1;
        nft.testMint(alice, id, "ipfs://x");

        vm.prank(alice);
        nft.setApprovalForAll(bob, true);

        nft.exposedDebit(bob, id, 30101);
        assertEq(nft.ownerOfUnsafe(id), address(0));
    }

    function testNameSymbol() public {
        assertEq(nft.name(), "Fraxiversary");
        assertEq(nft.symbol(), "FRAX5Y");
    }

    function testOwnerIsInitialOwner() public {
        assertEq(nft.owner(), owner);
    }

    function testNoPublicMintFunctionExists() public {
        (bool ok,) = address(nft).call(abi.encodeWithSignature("mint(address,uint256)"));
        assertFalse(ok);
    }

    function testSoulboundBlocksSafeTransferFrom() public {
        uint256 id = 1;
        nft.testMint(alice, id, "ipfs://x");
        nft.testSetSoulbound(id, true);

        vm.prank(alice);
        vm.expectRevert(CannotTransferSoulboundToken.selector);
        nft.safeTransferFrom(alice, bob, id);
    }

    function testTransferToZeroReverts() public {
        uint256 id = 1;
        nft.testMint(alice, id, "ipfs://x");

        vm.prank(alice);
        vm.expectRevert();
        nft.transferFrom(alice, address(0), id);
    }

    function testLzReceiveRevertsIfTokenAlreadyExists() public {
        uint256 id = 777;
        nft.testMint(alice, id, "ar://old");

        bytes memory inner = abi.encode("ar://new", false);
        bytes32 toB32 = bytes32(uint256(uint160(alice)));
        (bytes memory message, bool hasCompose) = ONFT721MsgCodec.encode(toB32, id, inner);
        assertTrue(hasCompose);

        Origin memory origin;
        origin.srcEid = 30101;
        origin.nonce = 123;

        vm.expectRevert(abi.encodeWithSelector(TokenAlreadyExists.selector, id));
        nft.exposedLzReceive(origin, keccak256("guid"), message, address(0), "");
    }

    function testLzReceiveSetsSoulboundFalseCorrectly() public {
        uint256 id = 100;
        string memory uri = "ar://meta-false";

        bytes memory inner = abi.encode(uri, false);
        bytes32 toB32 = bytes32(uint256(uint160(alice)));
        (bytes memory message, bool hasCompose) = ONFT721MsgCodec.encode(toB32, id, inner);
        assertTrue(hasCompose);

        Origin memory origin;
        origin.srcEid = 30101;
        origin.nonce = 1;

        nft.exposedLzReceive(origin, keccak256("g"), message, address(0), "");

        assertEq(nft.ownerOf(id), alice);
        assertEq(nft.tokenURI(id), uri);
        assertFalse(nft.isNonTransferrable(id));
    }

    function testApprovalDoesNotBypassSoulboundTransferBlock() public {
        uint256 id = 1;
        nft.testMint(alice, id, "ipfs://x");
        nft.testSetSoulbound(id, true);

        vm.prank(alice);
        nft.approve(bob, id);

        vm.prank(bob);
        vm.expectRevert(CannotTransferSoulboundToken.selector);
        nft.transferFrom(alice, bob, id);
    }

    function testOwnerCanUpdateUriWhilePaused() public {
        uint256 id = 1;
        nft.testMint(alice, id, "ipfs://old");

        vm.prank(owner);
        nft.pause();

        vm.prank(owner);
        nft.updateSpecificTokenUri(id, "ipfs://new");

        assertEq(nft.tokenURI(id), "ipfs://new");
    }

    function testFuz_DebitCreditSupplyInvariant(uint256 id) public {
        vm.assume(id > 0 && id < 1e18);

        nft.testMint(alice, id, "ipfs://x");
        assertEq(nft.totalSupply(), 1);
        assertEq(nft.balanceOf(alice), 1);

        nft.exposedDebit(alice, id, 30101);
        assertEq(nft.totalSupply(), 0);
        assertEq(nft.balanceOf(alice), 0);

        nft.exposedCredit(alice, id, 30101);
        assertEq(nft.totalSupply(), 1);
        assertEq(nft.balanceOf(alice), 1);
    }

    function testSoulboundBlocksBurnIfEverExposed() public {
        uint256 id = 1;
        nft.testMint(alice, id, "ipfs://x");
        nft.testSetSoulbound(id, true);

        vm.expectRevert(CannotTransferSoulboundToken.selector);
        nft.testBurn(id);
    }
}

contract FraxiversaryEthHarness is Fraxiversary {
    using ONFT721MsgCodec for bytes;
    using ONFT721MsgCodec for bytes32;

    constructor(address _initialOwner, address _lzEndpoint) Fraxiversary(_initialOwner, _lzEndpoint) {}

    // -------------------------
    // Test-only helpers
    // -------------------------

    function testMint(address _to, uint256 _tokenId, string memory _uri) external {
        _safeMint(_to, _tokenId);
        _setTokenURI(_tokenId, _uri);
    }

    function testSetSoulbound(uint256 _tokenId, bool _val) external {
        isNonTransferrable[_tokenId] = _val;
    }

    function ownerOfUnsafe(uint256 _tokenId) external view returns (address) {
        return _ownerOf(_tokenId);
    }

    // -------------------------
    // Expose internal ONFT hooks
    // -------------------------

    function exposedDebit(address _from, uint256 _tokenId, uint32 _dstEid) external {
        _debit(_from, _tokenId, _dstEid);
    }

    function exposedCredit(address _to, uint256 _tokenId, uint32 _srcEid) external {
        _credit(_to, _tokenId, _srcEid);
    }

    function exposedBuildMsgAndOptions(SendParam calldata _sp) external view returns (bytes memory m, bytes memory o) {
        return _buildMsgAndOptions(_sp);
    }

    function exposedLzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _executorData
    ) external {
        _lzReceive(_origin, _guid, _message, _executor, _executorData);
    }

    function exposedDecodeONFT(bytes calldata _message)
        external
        pure
        returns (bytes32 toB32, uint256 tokenId, bool isComposed, bytes memory compose)
    {
        toB32 = _message.sendTo();
        tokenId = _message.tokenId();
        isComposed = _message.isComposed();
        compose = isComposed ? _message.composeMsg() : bytes("");
    }

    function testBurn(uint256 _tokenId) external {
        _burn(_tokenId);
    }
}
