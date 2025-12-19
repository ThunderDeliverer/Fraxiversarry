// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Fraxiversary} from "../src/Fraxiversary.sol";

contract FraxiversaryMintConfigScript is Script {
    Fraxiversary public fraxiversary;
    address constant FRAXIVERSARY = 0x31e0Ed13B47e77132C32d599314212b325929BcE;
    address internal deployer;
    uint256 internal privateKey;

    function run() public {
        privateKey = vm.envUint("PK");
        deployer = vm.rememberKey(privateKey);
        vm.startBroadcast(deployer);

        fraxiversary = Fraxiversary(FRAXIVERSARY);

        console.log("Fraxiversary loaded at:", address(fraxiversary));
        console.log("Caller set to:", deployer);

        address[] memory erc20s = new address[](4);
        erc20s[0] = 0xFc00000000000000000000000000000000000002; // WFRAX
        erc20s[1] = 0xfc00000000000000000000000000000000000008; // sfrxUSD
        erc20s[2] = 0xFC00000000000000000000000000000000000005; // sfrxETH
        erc20s[3] = 0xFc00000000000000000000000000000000000003; // FPI

        uint256[] memory mintAmounts = new uint256[](4);
        mintAmounts[0] = 1000e18; // 1000 WFRAX
        mintAmounts[1] = 1000e18; // 1000 sfrxUSD
        mintAmounts[2] = 1e18; // 1 sfrxETH
        mintAmounts[3] = 1000e18; // 1000 FPI

        string[] memory tokenUris = new string[](4);
        tokenUris[0] = "https://arweave.net/CxQl0ki_oqypKeGVbVHBIAPjY2QT3jaBDX9FSqrfBd4"; // WFRAX
        tokenUris[1] = "https://arweave.net/VAk7sIe36qVGS80TCBqctI1pZJbwDzx6KytRA5l6VhE"; // sfrxUSD
        tokenUris[2] = "https://arweave.net/Rzs5IiJpVPKIPRHgqmqDhDKikt_miLqJKYTPBEkUSzw"; // sfrxETH
        tokenUris[3] = "https://arweave.net/p9QZj7kpFy_iOCmDxH3gYqqDtvzZsU81QkWYn7DpBUA"; // FPI

        for (uint256 i; i < erc20s.length;) {
            fraxiversary.setBaseAssetTokenUri(erc20s[i], tokenUris[i]);
            console.log("Set token URI for ERC20:", erc20s[i]);

            fraxiversary.updateBaseAssetMintPrice(erc20s[i], mintAmounts[i]);
            console.log("Set mint amount for ERC20:", erc20s[i], "to", mintAmounts[i]);

            unchecked {
                ++i;
            }
        }

        vm.stopBroadcast();
    }
}
