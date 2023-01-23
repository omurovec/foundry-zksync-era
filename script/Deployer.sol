// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.13;

import "forge-std/StdJson.sol";
import "solidity-stringutils/strings.sol";

///@notice This cheat codes interface is named _CheatCodes so you can use the CheatCodes interface in other testing files without errors
interface _CheatCodes {
    function ffi(string[] calldata) external returns (bytes memory);
    function envString(string calldata key) external returns (string memory value);
    function parseJson(string memory json, string memory key) external returns (string memory value);
    function writeFile(string calldata, string calldata) external;
    function readFile(string calldata) external returns (string memory);
}

contract Deployer {
    using stdJson for string;
    using strings for *;

    address constant HEVM_ADDRESS = address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));

    _CheatCodes cheatCodes = _CheatCodes(HEVM_ADDRESS);

    function compileContract(string memory fileName) public returns (bytes memory) {
        ///@notice Grabs the path of the config file for zksolc from env.
        ///@notice If none is found, default to the one defined in this project
        string memory configFile;
        try cheatCodes.envString("CONFIG_FILE") returns (string memory value) {
            configFile = value;
        } catch {
            configFile = "zksolc.json";
        }

        ///@notice Parses config values from file
        string memory config = cheatCodes.readFile(configFile);
        string memory os = config.readString("os");
        string memory arch = config.readString("arch");
        string memory version = config.readString("version");

        ///@notice Constructs zksolc path from config
        string memory zksolcPath =
            string(abi.encodePacked("lib/zksolc-bin/", os, "-", arch, "/zksolc-", os, "-", arch, "-v", version));

        ///@notice Compiles the contract using zksolc
        string[] memory cmds = new string[](3);
        cmds[0] = zksolcPath;
        cmds[1] = "--bin";
        cmds[2] = fileName;
        bytes memory output = cheatCodes.ffi(cmds);

        ///@notice Parses bytecode from zksolc output
        strings.slice memory result = string(output).toSlice();
        return bytes(result.rsplit(" ".toSlice()).toString());
    }

    function deployContract(string memory fileName) public returns (address) {
        bytes memory bytecode = compileContract(fileName);

        ///@notice deploy the bytecode with the create instruction
        address deployedAddress;
        assembly {
            deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        ///@notice check that the deployment was successful
        require(
            deployedAddress != address(0),
            "Deployer could not deploy contract"
        );
    }
}
