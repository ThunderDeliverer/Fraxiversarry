// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Fraxiversarry} from "../src/Fraxiversarry.sol";

contract CounterTest is Test {
    Fraxiversarry public fraxiversarry;

    function setUp() public {
        fraxiversarry = new Fraxiversarry(msg.sender);
    }
}
