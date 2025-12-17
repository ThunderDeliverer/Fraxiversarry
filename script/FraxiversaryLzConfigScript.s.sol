// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Fraxiversary} from "../src/Fraxiversary.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

interface IOAppCore {
    function setPeer(uint32 _eid, bytes32 _peer) external;
}

interface IOAppOptionsType3 {
    struct EnforcedOptionParam {
        uint32 eid;
        uint16 msgType;
        bytes options;
    }

    function setEnforcedOptions(EnforcedOptionParam[] calldata _params) external;
}

interface IMessageLibManager {
    struct SetConfigParam {
        uint32 _eid;
        uint32 _configType;
        bytes _config;
    }

    function isSupportedEid(uint32 _eid) external view returns (bool);

    function getSendLibrary(address _sender, uint32 _eid) external view returns (address lib_);

    function isDefaultSendLibrary(address _sender, uint32 _eid) external view returns (bool);

    function getReceiveLibrary(address _receiver, uint32 _eid) external view returns (address lib_, bool isDefault_);

    function setSendLibrary(address _sender, uint32 _eid, address _lib) external;

    function setReceiveLibrary(address _receiver, uint32 _eid, address _lib, uint256 _libConfig) external;

    function getConfig(address _oapp, address _lib, uint32 _eid, uint32 _configType)
        external
        view
        returns (bytes memory);

    function setConfig(address _oapp, address _lib, SetConfigParam[] calldata _params) external;
}

contract FraxiversaryLzConfigScript is Script {
    using OptionsBuilder for bytes;

    uint256 constant CHAINID_ETHEREUM = 1;
    uint256 constant CHAINID_FRAXTAL = 252;

    address constant ENDPOINT_ETHEREUM = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant ENDPOINT_FRAXTAL = 0x1a44076050125825900e736c501f859c50fE728c;

    uint32 constant EID_ETHEREUM = 30101;
    uint32 constant EID_FRAXTAL = 30255;

    address constant FRAXIVERSARY_ETHEREUM = 0x49498c779933941747884FF25b494444a44f0AA2;
    address constant FRAXIVERSARY_FRAXTAL = 0x2Ee68dE9e4FD0F35409a00bA46953782b5491250;

    address constant SEND_LIB_302_ETHEREUM = 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1;
    address constant RECEIVE_LIB_302_ETHEREUM = 0xc02Ab410f0734EFa3F14628780e6e695156024C2;

    address constant SEND_LIB_302_FRAXTAL = 0x377530cdA84DFb2673bF4d145DCF0C4D7fdcB5b6;
    address constant RECEIVE_LIB_302_FRAXTAL = 0x8bC1e36F015b9902B54b1387A4d733cebc2f5A4e;

    uint32 constant CONFIG_TYPE_ULN = 2;

    address constant TEMPLATE_OFT_ETHEREUM = 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29; //frxUSD
    address constant TEMPLATE_OFT_FRAXTAL = 0x96A394058E2b84A89bac9667B19661Ed003cF5D4; //frxUSD

    address internal deployer;
    uint256 internal privateKey;

    function run() public {
        privateKey = vm.envUint("PK");
        deployer = vm.rememberKey(privateKey);
        vm.startBroadcast(deployer);

        if (block.chainid == CHAINID_ETHEREUM) {
            _configureEthereumSide();
        } else if (block.chainid == CHAINID_FRAXTAL) {
            _configureFraxtalSide();
        } else {
            revert("Unsupported chain");
        }

        vm.stopBroadcast();
    }

    function _configureEthereumSide() internal {
        console.log("Configuring Ethereum connections...");

        address localOnft = FRAXIVERSARY_ETHEREUM;
        address endpoint = ENDPOINT_ETHEREUM;
        uint32 remoteEid = EID_FRAXTAL;
        address remoteOnft = FRAXIVERSARY_FRAXTAL;
        address sendLib302 = SEND_LIB_302_ETHEREUM;
        address recvLib302 = RECEIVE_LIB_302_ETHEREUM;
        address templateOapp = TEMPLATE_OFT_ETHEREUM;

        _configurePair(localOnft, endpoint, remoteEid, remoteOnft, sendLib302, recvLib302, templateOapp);
    }

    function _configureFraxtalSide() internal {
        console.log("Configuring Fraxtal connections...");

        address localOnft = FRAXIVERSARY_FRAXTAL;
        address endpoint = ENDPOINT_FRAXTAL;
        uint32 remoteEid = EID_ETHEREUM;
        address remoteOnft = FRAXIVERSARY_ETHEREUM;
        address sendLib302 = SEND_LIB_302_FRAXTAL;
        address recvLib302 = RECEIVE_LIB_302_FRAXTAL;
        address templateOapp = TEMPLATE_OFT_FRAXTAL;

        _configurePair(localOnft, endpoint, remoteEid, remoteOnft, sendLib302, recvLib302, templateOapp);
    }

    function _configurePair(
        address _localOnft,
        address _endpoint,
        uint32 _remoteEid,
        address _remoteOnft,
        address _sendLib302,
        address _recvLib302,
        address _templateOapp
    ) internal {
        console.log("Local ONFT: ", _localOnft);
        console.log("Endpoint: ", _endpoint);
        console.log("Remote EID: ", _remoteEid);
        console.log("Remote ONFT: ", _remoteOnft);

        IMessageLibManager msgLibMgr = IMessageLibManager(_endpoint);
        require(msgLibMgr.isSupportedEid(_remoteEid), "Remote EID not supported by endpoint");

        bytes32 peer = bytes32(uint256(uint160(_remoteOnft)));
        IOAppCore(_localOnft).setPeer(_remoteEid, peer);
        console.log("Set peer to remote ONFT");

        _setEnforcedOptions(_localOnft, _remoteEid);
        console.log("Set enforced options for remote EID");

        _setLibs(msgLibMgr, _localOnft, _remoteEid, _sendLib302, _recvLib302);
        console.log("Set send/receive libraries");

        _validateConfig(msgLibMgr, _localOnft, _remoteEid, _sendLib302, _recvLib302);

        _copyDvnConfig(msgLibMgr, _localOnft, _templateOapp, _remoteEid);
    }

    function _setEnforcedOptions(address _localOnft, uint32 _remoteEid) internal {
        bytes memory optionsTypeOne = OptionsBuilder.newOptions().addExecutorLzReceiveOption(275_000, 0);
        bytes memory optionsTypeTwo = OptionsBuilder.newOptions().addExecutorLzReceiveOption(340_000, 0);

        IOAppOptionsType3.EnforcedOptionParam[] memory params = new IOAppOptionsType3.EnforcedOptionParam[](2);

        params[0] = IOAppOptionsType3.EnforcedOptionParam({eid: _remoteEid, msgType: 1, options: optionsTypeOne});
        params[1] = IOAppOptionsType3.EnforcedOptionParam({eid: _remoteEid, msgType: 2, options: optionsTypeTwo});

        IOAppOptionsType3(_localOnft).setEnforcedOptions(params);
        console.log("Enforced options set for msgTypes 1 and 2");
    }

    function _setLibs(
        IMessageLibManager _msgLibMgr,
        address _localOnft,
        uint32 _remoteEid,
        address _sendLib302,
        address _recvLib302
    ) internal {
        address currentSendLib = _msgLibMgr.getSendLibrary(_localOnft, _remoteEid);
        bool isDefaultSend = _msgLibMgr.isDefaultSendLibrary(_localOnft, _remoteEid);

        if (currentSendLib != _sendLib302 || isDefaultSend) {
            _msgLibMgr.setSendLibrary(_localOnft, _remoteEid, _sendLib302);
            console.log("Send library to updated");
        } else {
            console.log("Send library already configured");
        }

        (address currentRecvLib, bool isDefaultRecv) = _msgLibMgr.getReceiveLibrary(_localOnft, _remoteEid);

        if (currentRecvLib != _recvLib302 || isDefaultRecv) {
            _msgLibMgr.setReceiveLibrary(_localOnft, _remoteEid, _recvLib302, 0);
            console.log("Receive library updated");
        } else {
            console.log("Receive library already configured");
        }

        // Validations
        require(_msgLibMgr.getSendLibrary(_localOnft, _remoteEid) == _sendLib302, "Send lib not set correctly");
        (address setRecvLib,) = _msgLibMgr.getReceiveLibrary(_localOnft, _remoteEid);
        require(setRecvLib == _recvLib302, "Receive lib not set correctly");
    }

    function _validateConfig(
        IMessageLibManager _msgLibMgr,
        address _localOnft,
        uint32 _remoteEid,
        address _expectedSendLib,
        address _expectedRecvLib
    ) internal view {
        address sendLib = _msgLibMgr.getSendLibrary(_localOnft, _remoteEid);
        require(sendLib == _expectedSendLib, "Send library mismatch");

        (address recvLib,) = _msgLibMgr.getReceiveLibrary(_localOnft, _remoteEid);
        require(recvLib == _expectedRecvLib, "Receive library mismatch");

        console.log("Configuration validated successfully");
    }

    function _copyDvnConfig(IMessageLibManager _msgLibMgr, address _localOnft, address _templateOapp, uint32 _remoteEid)
        internal
    {
        if (_templateOapp == address(0)) {
            console.log("No template OApp provided, skipping DVN config copy");
            return;
        }

        address templateSendLib = _msgLibMgr.getSendLibrary(_templateOapp, _remoteEid);
        address localSendLib = _msgLibMgr.getSendLibrary(_localOnft, _remoteEid);

        require(templateSendLib != address(0), "Template send lib not set");
        require(localSendLib != address(0), "Local send lib not set");
        require(templateSendLib == localSendLib, "Send libs do not match, cannot copy config");

        bytes memory ulnConfig = _msgLibMgr.getConfig(_templateOapp, templateSendLib, _remoteEid, CONFIG_TYPE_ULN);
        require(ulnConfig.length != 0, "No ULN config in template");

        IMessageLibManager.SetConfigParam[] memory params = new IMessageLibManager.SetConfigParam[](1);
        params[0] =
            IMessageLibManager.SetConfigParam({_eid: _remoteEid, _configType: CONFIG_TYPE_ULN, _config: ulnConfig});

        _msgLibMgr.setConfig(_localOnft, localSendLib, params);

        console.log("Copied ULN config from template OApp to local ONFT");
    }
}
