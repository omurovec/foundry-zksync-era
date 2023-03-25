// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "./Deployer.sol";

contract CounterScript is Script {
    address DIAMOND_PROXY_GOERLI = 0x1908e2BF4a88F91E4eF0DC72f02b8Ea36BEa2319;

    function run() public {
        Deployer deployer = new Deployer("1.3.7", DIAMOND_PROXY_GOERLI);
        deployer.deployFromL1("src/Counter.sol", new bytes(0), bytes32(uint256(1234)));
    }
}
