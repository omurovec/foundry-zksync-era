// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "./Deployer.sol";

contract CounterScript is Script {
    Deployer public deployer;

    function setUp() public {
        deployer = new Deployer();
    }

    function run() public {
        bytes memory params;
        deployer.deployContract("src/Counter.sol", params, false, address(0x1908e2BF4a88F91E4eF0DC72f02b8Ea36BEa2319));
    }
}
