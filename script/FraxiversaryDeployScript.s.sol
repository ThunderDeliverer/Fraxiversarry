// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Fraxiversary} from "../src/Fraxiversary.sol";

contract FraxiversaryDeployScript is Script {
    Fraxiversary public fraxiversary;
    address constant LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;

    function run() public {
        vm.startBroadcast();

        fraxiversary = new Fraxiversary(msg.sender, LZ_ENDPOINT);

        console.log("Fraxiversary deployed at:", address(fraxiversary));
        console.log("Owner and delegate set to:", msg.sender);
        console.log("LayerZero Endpoint set to:", LZ_ENDPOINT);

        vm.stopBroadcast();
    }
}
