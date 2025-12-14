// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Fraxiversarry} from "../src/FraxiversarryEthereum.sol";

contract FraxiversarryDeployScript is Script {
    Fraxiversarry public fraxiversarry;
    address constant LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;

    function run() public {
        vm.startBroadcast();

        fraxiversarry = new Fraxiversarry(msg.sender, LZ_ENDPOINT);

        console.log("Ethereum Fraxiversarry deployed at:", address(fraxiversarry));
        console.log("Owner and delegate set to:", msg.sender);
        console.log("LayerZero Endpoint set to:", LZ_ENDPOINT);

        vm.stopBroadcast();
    }
}
