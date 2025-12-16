// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract MockLzEndpoint {
    event ComposeSent(address to, bytes32 guid, uint16 index, bytes message);

    uint32 public immutable EID = 1;
    address public delegateAddress;

    // Minimal function OApp expects in constructor
    function eid() external view returns (uint32) {
        return EID;
    }

    // Some OApp implementations call this in deploy scripts / constructor
    function setDelegate(address _delegate) external {
        delegateAddress = _delegate;
    }

    // Sometimes read back
    function delegate() external view returns (address) {
        return delegateAddress;
    }

    // Used by Fraxiversary._lzReceive -> endpoint.sendCompose(...)
    function sendCompose(address to, bytes32 guid, uint16 index, bytes calldata message) external {
        emit ComposeSent(to, guid, index, message);
    }

    // Safety net: if OApp/ONFT calls any other endpoint function, don't revert
    fallback() external payable {}
    receive() external payable {}
}
