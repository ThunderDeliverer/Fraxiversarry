// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Fraxiversary} from "../src/FraxiversaryEthereum.sol";

contract FraxiversaryDeployScript is Script {
    Fraxiversary public fraxiversary;
    address constant LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address internal deployer;
    uint256 internal privateKey;

    function run() public {
        privateKey = vm.envUint("PK");
        deployer = vm.rememberKey(privateKey);
        vm.startBroadcast(deployer);

        fraxiversary = new Fraxiversary(deployer, LZ_ENDPOINT);

        console.log("Ethereum Fraxiversary deployed at:", address(fraxiversary));
        console.log("Owner and delegate set to:", deployer);
        console.log("LayerZero Endpoint set to:", LZ_ENDPOINT);

        vm.stopBroadcast();
    }
}
