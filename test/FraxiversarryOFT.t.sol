// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, Vm} from "forge-std/Test.sol";

import {Fraxiversarry} from "../src/Fraxiversarry.sol";
import {IFraxiversarryErrors} from "../src/interfaces/IFraxiversarryErrors.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockMsgInspector} from "./mocks/MockMsgInspector.sol";
import {MockLzEndpoint} from "./mocks/MockLzEndpoint.sol";

import {SendParam} from "@layerzerolabs/onft-evm/contracts/onft721/interfaces/IONFT721.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {ONFT721MsgCodec} from "@layerzerolabs/onft-evm/contracts/onft721/libs/ONFT721MsgCodec.sol";

error InvalidReceiver();

/// ----------------------------------------------------------
/// Minimal endpoint stub used only for these tests
/// ----------------------------------------------------------

contract NoopLzEndpoint {
    // Matches the event we look for in the tests
    event ComposeSent(address indexed to, bytes32 indexed guid, uint256 value, bytes message);

    // Needed by OAppCore constructor: endpoint.setDelegate(address)
    function setDelegate(address /*delegate*/) external {
        // no-op
    }

    function sendCompose(
        address to,
        bytes32 guid,
        uint256 value,
        bytes calldata message
    ) external {
        // Do NOT revert – just log the compose message
        emit ComposeSent(to, guid, value, message);
    }
}

/// ----------------------------------------------------------
/// ONFT behaviour tests
/// ----------------------------------------------------------

contract FraxiversarryONFTTest is Test, IFraxiversarryErrors {
    using ONFT721MsgCodec for bytes;
    using ONFT721MsgCodec for bytes32;

    FraxiversarryONFTHarness internal fraxiversarry;    // source chain
    FraxiversarryONFTHarness internal fraxDst; // destination chain
    ONFT721MsgCodecHarness internal codecHarness;
    MockLzEndpoint internal endpoint;
    MockMsgInspector internal inspector;
    MockERC20 internal wfrax;

    address internal owner = address(this);
    address internal alice = address(0xB0B);
    address internal bob   = address(0xC0C);

    uint256 constant WFRAX_PRICE = 100e18;

    function setUp() public {
        endpoint = new MockLzEndpoint();

        // Source-chain instance
        fraxiversarry = new FraxiversarryONFTHarness(owner, address(endpoint));

        // Destination-chain instance
        fraxDst = new FraxiversarryONFTHarness(owner, address(endpoint));

        codecHarness = new ONFT721MsgCodecHarness();

        inspector = new MockMsgInspector();
        fraxiversarry.exposedSetMsgInspector(address(inspector));
        fraxDst.exposedSetMsgInspector(address(inspector));

        // Deploy wFRAX at canonical address and wire into *source* Fraxiversarry
        address wFraxAddress = fraxiversarry.WFRAX_ADDRESS();
        MockERC20 tmp = new MockERC20("Wrapped FRAX", "wFRAX");
        vm.etch(wFraxAddress, address(tmp).code);
        wfrax = MockERC20(wFraxAddress);

        fraxiversarry.setBaseAssetTokenUri(address(wfrax), "https://tba.fraxiversarry/wfrax.json");

        // Fund alice and set mint price on *source* chain
        wfrax.mint(alice, 1e22);

        vm.prank(owner);
        fraxiversarry.updateBaseAssetMintPrice(address(wfrax), WFRAX_PRICE);
    }

    function _mintBase(address to) internal returns (uint256 tokenId) {
        vm.startPrank(to);
        wfrax.approve(address(fraxiversarry), WFRAX_PRICE);
        tokenId = fraxiversarry.paidMint(address(wfrax));
        vm.stopPrank();
    }

    function _origin(uint32 srcEid) internal pure returns (Origin memory o) {
        o = Origin({
            srcEid: srcEid,
            sender: bytes32(uint256(uint160(address(0xCAFE)))),
            nonce: 1
        });
    }

    // ------------------------------------------------------
    // _bridgeBurn behaviour
    // ------------------------------------------------------

    function testBridgeBurnForBaseBurnsTokenButPreservesBalances() public {
        uint256 tokenId = _mintBase(alice);

        uint256 contractBalBefore = wfrax.balanceOf(address(fraxiversarry));
        uint256 storedBalBefore   = fraxiversarry.balanceOfERC20(address(wfrax), tokenId);

        fraxiversarry.exposedBridgeBurn(alice, tokenId);

        // Token should no longer exist
        vm.expectRevert();
        fraxiversarry.ownerOf(tokenId);

        // Underlying ERC20s must remain locked and accounted
        uint256 contractBalAfter = wfrax.balanceOf(address(fraxiversarry));
        uint256 storedBalAfter   = fraxiversarry.balanceOfERC20(address(wfrax), tokenId);

        assertEq(contractBalAfter, contractBalBefore, "bridge burn must not move ERC20s");
        assertEq(storedBalAfter, storedBalBefore, "internal ERC20 balance must remain");
    }

    function testBridgeBurnForSoulboundDoesNotRevertAndBurnsToken() public {
        // Soulbound tokens should be bridgeable as well
        vm.prank(owner);
        uint256 sbId = fraxiversarry.soulboundMint(alice, "uri");

        // pre: soulbound flag set
        assertTrue(fraxiversarry.exposedIsNonTransferrable(sbId));

        fraxiversarry.exposedBridgeBurn(alice, sbId);

        vm.expectRevert();
        fraxiversarry.ownerOf(sbId);

        // Soulbound flag can remain set; important part is that bridge burn
        // bypassed the normal soulbound transfer check.
        assertTrue(fraxiversarry.exposedIsNonTransferrable(sbId));
    }

    function testBridgeBurnWithWrongOwnerReverts() public {
        uint256 tokenId = _mintBase(alice);

        // Pass a bogus "owner" to _bridgeBurn – ERC721 auth inside _update must reject it
        vm.expectRevert();
        fraxiversarry.exposedBridgeBurn(bob, tokenId);
    }

    // ------------------------------------------------------
    // _debit / _credit behaviour
    // ------------------------------------------------------

    function testDebitThenCreditRoundtrip() public {
        uint256 tokenId = _mintBase(alice);

        // Debit (source chain) – mimic ONFT send, msg.sender == from
        vm.prank(alice);
        fraxiversarry.exposedDebit(alice, tokenId, 2);

        // After debit, token should be burned locally
        vm.expectRevert();
        fraxiversarry.ownerOf(tokenId);

        // Credit (destination chain) – same tokenId comes back to alice
        fraxiversarry.exposedCredit(alice, tokenId, 1);

        // After credit, token should exist again and be owned by alice
        assertEq(fraxiversarry.ownerOf(tokenId), alice);
    }

    function testDebitRevertsIfCallerNotOwnerOrApproved() public {
        uint256 tokenId = _mintBase(alice);

        // Bob tries to debit without approval
        vm.prank(bob);
        vm.expectRevert(); // ERC721InsufficientApproval
        fraxiversarry.exposedDebit(bob, tokenId, 2);
    }

    function testDebitRevertsForNonexistentToken() public {
        // tokenId 123 was never minted
        vm.expectRevert();
        fraxiversarry.exposedDebit(alice, 123, 2);
    }

    function testCreditRevertsIfTokenAlreadyExists() public {
        uint256 tokenId = _mintBase(alice);

        // Token exists locally, so credit for same id must revert with TokenAlreadyExists(tokenId)
        vm.expectRevert(abi.encodeWithSelector(TokenAlreadyExists.selector, tokenId));
        fraxiversarry.exposedCredit(alice, tokenId, 1);
    }

    // ------------------------------------------------------
    // _buildMsgAndOptions behaviour + inspector
    // ------------------------------------------------------

    function testBuildMsgAndOptionsPreservesNonEmptyOptions() public {
        uint256 tokenId = _mintBase(alice);

        SendParam memory sp;
        sp.dstEid       = 2;
        sp.to           = bytes32(uint256(uint160(alice)));
        sp.tokenId      = tokenId; // must exist – underlying implementation calls tokenURI()
        sp.extraOptions = abi.encode("my-options");
        sp.composeMsg   = abi.encode("ignored-in-contract"); // contract builds its own compose payload

        (bytes memory msgData, bytes memory opts) = fraxiversarry.exposedBuildMsgAndOptions(sp);

        // Just basic invariants: call didn't revert and outputs are non-empty
        assertTrue(msgData.length > 0, "message must be non-empty");
        assertTrue(opts.length > 0, "options must be non-empty");
    }

    function testBuildMsgAndOptionsRevertsOnZeroReceiver() public {
        uint256 tokenId = _mintBase(alice);

        SendParam memory sp;
        sp.dstEid  = 2;
        sp.to      = bytes32(0); // invalid receiver
        sp.tokenId = tokenId;

        vm.expectRevert(InvalidReceiver.selector);
        fraxiversarry.exposedBuildMsgAndOptions(sp);
    }

    // ------------------------------------------------------
    // _lzReceive success path – valid composed message
    //
    // IMPORTANT: we now generate the ONFT message by calling the contract's
    // own _buildMsgAndOptions on the *source* Fraxiversarry and feed that
    // into _lzReceive on the *destination* Fraxiversarry. This exactly
    // mirrors the production flow (_buildMsgAndOptions → endpoint → _lzReceive).
    // ------------------------------------------------------

    function testLzReceiveWithValidComposedMessageMintsTokenToRecipient() public {
        // ----- SOURCE CHAIN SETUP -----
        uint256 tokenId = _mintBase(alice);
        string memory uri = fraxiversarry.tokenURI(tokenId);
        address recipientOnDst = bob;

        // Build ONFT message using the source contract's own builder
        SendParam memory sp;
        sp.dstEid       = 10;
        sp.to           = bytes32(uint256(uint160(recipientOnDst)));
        sp.tokenId      = tokenId;
        sp.extraOptions = bytes("");
        sp.composeMsg   = bytes(""); // ignored in contract

        (bytes memory msgData,) = fraxiversarry.exposedBuildMsgAndOptions(sp);

        // Source: bridge burn token from alice
        vm.prank(alice);
        fraxiversarry.exposedDebit(alice, tokenId, sp.dstEid);
        vm.expectRevert();
        fraxiversarry.ownerOf(tokenId); // gone on source chain

        // ----- DESTINATION CHAIN RECEIVE -----
        Origin memory o = _origin(sp.dstEid);
        bytes32 guid = keccak256("bridge-guid-base");

        vm.recordLogs();
        fraxDst.exposedLzReceive(o, guid, msgData, address(this), "");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // After receive, token must exist on destination and be owned by recipient
        assertEq(fraxDst.ownerOf(tokenId), recipientOnDst, "bridged token owner mismatch");
        assertEq(fraxDst.tokenURI(tokenId), uri, "bridged token URI mismatch");
        assertFalse(
            fraxDst.exposedIsNonTransferrable(tokenId),
            "bridged BASE token must not be soulbound"
        );

        // Check ONFTReceived + ComposeSent events on destination chain
        // Check ONFTReceived event on destination chain
        bytes32 onftReceivedSig = keccak256("ONFTReceived(bytes32,uint32,address,uint256)");

        bool foundONFTReceived;

        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == onftReceivedSig) {
                foundONFTReceived = true;
                assertEq(logs[i].topics[1], guid, "ONFTReceived.guid mismatch");
            }
        }

        assertTrue(foundONFTReceived, "ONFTReceived event not found");
    }

    function testBuildMsgAndOptionsEncodesSoulboundONFTPayload() public {
        // Mint soulbound token on source
        vm.prank(owner);
        uint256 sbId = fraxiversarry.soulboundMint(alice, "https://sb.uri/1");
        string memory uri = fraxiversarry.tokenURI(sbId);
        assertTrue(fraxiversarry.exposedIsNonTransferrable(sbId));

        // Build send params
        SendParam memory sp;
        sp.dstEid       = 10;
        sp.to           = bytes32(uint256(uint160(alice)));
        sp.tokenId      = sbId;
        sp.extraOptions = bytes("");
        sp.composeMsg   = bytes(""); // ignored

        (bytes memory msgData,) = fraxiversarry.exposedBuildMsgAndOptions(sp);

        // Decode ONFT wrapper via codec harness
        (
            address decodedTo,
            uint256 decodedId,
            bool hasCompose,
            bytes memory composeBlob
        ) = codecHarness.decodeAll(msgData);

        assertEq(decodedTo, alice, "sendTo mismatch");
        assertEq(decodedId, sbId, "tokenId mismatch");
        assertTrue(hasCompose, "expected composed message");

        // Slice off fromOApp (first 32 bytes) to get abi.encode(string,bool)
        bytes memory raw = composeBlob;
        uint256 len = raw.length;
        bytes memory inner = raw;
        assembly {
            inner := add(inner, 32)
            mstore(inner, sub(len, 32))
        }

        (string memory decodedUri, bool isSoulbound) = abi.decode(inner, (string, bool));

        assertEq(decodedUri, uri, "URI mismatch in compose payload");
        assertTrue(isSoulbound, "soulbound flag should be true in compose payload");
    }

    // ------------------------------------------------------
    // _lzReceive + inspector on bogus payloads
    // ------------------------------------------------------

    function testLzReceiveWithoutInspectorRevertsOnBogusPayload() public {
        fraxiversarry.exposedSetMsgInspector(address(0));

        Origin memory o = _origin(1);
        bytes32 guid = keccak256("guid-no-inspector");
        bytes memory payload = abi.encode("hello");
        bytes memory opts    = abi.encode("opts");

        vm.expectRevert();
        fraxiversarry.exposedLzReceive(o, guid, payload, address(this), opts);
    }

    function testLzReceiveRevertsWhenMessageIsNotComposedRawCodec() public {
        // We simulate a "send" that produces a non-composed message by calling
        // ONFT721MsgCodec.encode with an empty compose payload and then feeding
        // that into _lzReceive. According to your implementation this should
        // result in isComposed() == false and trigger MissingComposedMessage.
        uint256 bridgedTokenId = 999;
        address recipient = alice;
        bytes32 toEncoded = bytes32(uint256(uint160(recipient)));

        (bytes memory message,) = ONFT721MsgCodec.encode(toEncoded, bridgedTokenId, bytes(""));

        Origin memory o = _origin(1);
        bytes32 guid = keccak256("guid-missing-compose");

        vm.expectRevert(MissingComposedMessage.selector);
        fraxiversarry.exposedLzReceive(o, guid, message, address(this), "");
    }

    function testLzReceiveRevertsWhenMessageIsNotComposedAfterDebit() public {
        uint256 tokenId = _mintBase(alice);
        address recipientOnDst = bob;

        // Build an ONFT message with hasCompose == false
        bytes32 to = bytes32(uint256(uint160(recipientOnDst)));
        (bytes memory msgData, bool hasCompose) =
            ONFT721MsgCodec.encode(to, tokenId, bytes("")); // empty composeMsg

        assertFalse(hasCompose, "expected hasCompose == false");

        // Simulate debit on source chain
        vm.prank(alice);
        fraxiversarry.exposedDebit(alice, tokenId, 10);

        Origin memory o = _origin(10);
        bytes32 guid = keccak256("lzReceiveRevertsNotComposed");

        vm.expectRevert(MissingComposedMessage.selector);
        fraxDst.exposedLzReceive(o, guid, msgData, address(this), "");
    }

    function testLzReceiveRevertsOnMalformedComposePayload() public {
        uint256 tokenId = 99;
        address recipientOnDst = bob;

        // Start with a valid inner payload, then truncate it to break abi.decode
        bytes memory inner = abi.encode("https://fraxiversarry.test/bad.json", true);
        // remove last 32 bytes (the bool) to make it invalid
        bytes memory truncated = new bytes(inner.length - 32);
        for (uint256 i; i < truncated.length; ++i) {
            truncated[i] = inner[i];
        }

        bytes32 fromOApp = bytes32(uint256(uint160(address(fraxiversarry))));
        bytes memory composeBlob = abi.encodePacked(fromOApp, truncated);

        bytes32 to = bytes32(uint256(uint160(recipientOnDst)));
        (bytes memory msgData,) =
            ONFT721MsgCodec.encode(to, tokenId, composeBlob);

        Origin memory o = _origin(10);
        bytes32 guid = keccak256("lzReceiveMalformed");

        vm.expectRevert(); // generic abi.decode revert
        fraxDst.exposedLzReceive(o, guid, msgData, address(this), "");
    }

    function testBuildMsgAndOptionsEncodesCorrectONFTPayload() public {
        uint256 tokenId = _mintBase(alice);
        string memory uri = fraxiversarry.tokenURI(tokenId);

        // Build send params in memory (fine for tests)
        SendParam memory sp;
        sp.dstEid       = 10;
        sp.to           = bytes32(uint256(uint160(bob)));
        sp.tokenId      = tokenId;
        sp.extraOptions = bytes("");
        sp.composeMsg   = bytes(""); // ignored by contract

        (bytes memory msgData,) = fraxiversarry.exposedBuildMsgAndOptions(sp);

        // Decode with ONFT721MsgCodec via the harness
        (
            address decodedTo,
            uint256 decodedId,
            bool hasCompose,
            bytes memory composeBlob
        ) = codecHarness.decodeAll(msgData);

        assertEq(decodedTo, bob, "sendTo mismatch");
        assertEq(decodedId, tokenId, "tokenId mismatch");
        assertTrue(hasCompose, "expected composed message");

        // --- Now verify the compose payload itself ---
        // Layout: [ fromOApp (bytes32) ][ abi.encode(string tokenUri, bool isSoulbound) ]

        bytes memory raw = composeBlob;
        uint256 len = raw.length;

        // Slice off the first word (fromOApp) to mimic what _lzReceive does
        bytes memory inner = raw;
        assembly {
            inner := add(inner, 32)
            mstore(inner, sub(len, 32))
        }

        (string memory decodedUri, bool isSoulbound) = abi.decode(inner, (string, bool));

        assertEq(decodedUri, uri, "token URI mismatch in compose payload");
        assertFalse(isSoulbound, "base token should be non-soulbound in compose payload");
    }

    function testBuildMsgAndOptionsRevertsWhenSoulboundToDifferentRecipient() public {
        vm.prank(owner);
        uint256 sbId = fraxiversarry.soulboundMint(alice, "uri");
        assertTrue(fraxiversarry.exposedIsNonTransferrable(sbId));

        SendParam memory sp;
        sp.dstEid  = 10;
        sp.to      = bytes32(uint256(uint160(bob))); // not the owner
        sp.tokenId = sbId;

        vm.expectRevert(CannotTransferSoulboundToken.selector);
        fraxiversarry.exposedBuildMsgAndOptions(sp);
    }
}

/// ----------------------------------------------------------
/// ONFT harness – exposes internal ONFT helpers
/// ----------------------------------------------------------

contract FraxiversarryONFTHarness is Fraxiversarry {
    constructor(address initialOwner, address lzEndpoint)
        Fraxiversarry(initialOwner, lzEndpoint)
    {}

    function exposedIncreaseBalance(address account, uint128 value) external {
        _increaseBalance(account, value);
    }

    function exposedBaseURI() external pure returns (string memory) {
        return _baseURI();
    }

    function exposedBridgeBurn(address owner, uint256 tokenId) external {
        _bridgeBurn(owner, tokenId);
    }

    function exposedDebit(address from, uint256 tokenId, uint32 dstEid) external {
        _debit(from, tokenId, dstEid);
    }

    function exposedCredit(address to, uint256 tokenId, uint32 srcEid) external {
        _credit(to, tokenId, srcEid);
    }

    function exposedBuildMsgAndOptions(SendParam calldata sp)
        external
        view
        returns (bytes memory msgData, bytes memory opts)
    {
        return _buildMsgAndOptions(sp);
    }

    function exposedLzReceive(
        Origin calldata origin,
        bytes32 guid,
        bytes calldata message,
        address executor,
        bytes calldata extraData
    ) external {
        _lzReceive(origin, guid, message, executor, extraData);
    }

    function exposedSetMsgInspector(address inspector) external onlyOwner {
        msgInspector = inspector;
    }

    // READ-ONLY helper to introspect soulbound flag in tests
    function exposedIsNonTransferrable(uint256 tokenId) external view returns (bool) {
        return isNonTransferrable[tokenId];
    }
}

contract ONFT721MsgCodecHarness {
    function decodeAll(bytes calldata msgData)
        external
        pure
        returns (
            address to,
            uint256 tokenId,
            bool hasCompose,
            bytes memory composeBlob
        )
    {
        bytes32 toBytes = ONFT721MsgCodec.sendTo(msgData);
        to = address(uint160(uint256(toBytes)));

        tokenId     = ONFT721MsgCodec.tokenId(msgData);
        hasCompose  = ONFT721MsgCodec.isComposed(msgData);
        composeBlob = ONFT721MsgCodec.composeMsg(msgData);
    }
}