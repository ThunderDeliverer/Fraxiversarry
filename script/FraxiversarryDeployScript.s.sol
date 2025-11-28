// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Fraxiversarry} from "../src/Fraxiversarry.sol";

contract FraxiversarryDeployScript is Script {
    Fraxiversarry public fraxiversarry;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        fraxiversarry = new Fraxiversarry(msg.sender);

        vm.stopBroadcast();
    }
}
