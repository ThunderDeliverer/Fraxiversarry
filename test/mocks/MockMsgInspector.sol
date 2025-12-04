// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IOAppMsgInspector} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppMsgInspector.sol";

contract MockMsgInspector is IOAppMsgInspector {
    // Controls whether inspection passes or fails
    bool public shouldPass = true;

    // Allow tests to configure behavior
    function setShouldPass(bool _shouldPass) external {
        shouldPass = _shouldPass;
    }

    function inspect(bytes calldata _message, bytes calldata _options)
        external
        view
        override
        returns (bool valid)
    {
        // silence unused variable warnings if you don't use them
        _message;
        _options;

        if (!shouldPass) {
            // use the interface's custom error
            revert InspectionFailed(_message, _options);
        }

        return true;
    }
}