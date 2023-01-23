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
        vm.broadcast();

        deployer.deployContract("src/Counter.sol");
    }
}
