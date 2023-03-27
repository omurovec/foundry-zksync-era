// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.13;

import "forge-std/Vm.sol";
import "solidity-stringutils/strings.sol";
import "era-contracts/ethereum/contracts/zksync/interfaces/IMailbox.sol";
import "era-contracts/ethereum/contracts/common/L2ContractAddresses.sol";
import "era-contracts/ethereum/contracts/common/libraries/L2ContractHelper.sol";
import "era-contracts/zksync/contracts/vendor/AddressAliasHelper.sol";

import {
    L2_TX_MAX_GAS_LIMIT,
    DEFAULT_L2_GAS_PRICE_PER_PUBDATA,
    L2_BASE_FEE_BUFFER,
    ZKSOLC_BIN_REPO
} from "./Constants.sol";

interface IContractDeployer {
    function create2(bytes32 _salt, bytes32 _bytecodeHash, bytes calldata _input) external;
}

contract Deployer {
    using strings for *;

    VmSafe _vm = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    ///@notice Compiler & deployment config
    string private projectRoot;
    string private zksolcPath;
    address private diamondProxy;

    struct SystemInfo {
        string os;
        string arch;
        string extension;
        string toolchain;
    }

    constructor(string memory _zksolcVersion, address _diamondProxy) {
        ///@notice install bin compiler
        projectRoot = _vm.projectRoot();
        zksolcPath = _installCompiler(_zksolcVersion);

        diamondProxy = _diamondProxy;
    }

    function deployFromL1(string memory fileName, bytes calldata params, bytes32 salt) public returns (address) {
        return deployFromL1(fileName, params, salt,  L2_TX_MAX_GAS_LIMIT, DEFAULT_L2_GAS_PRICE_PER_PUBDATA);
    }

    function deployFromL1(
        string memory fileName,
        bytes calldata params,
        bytes32 salt,
        uint256 gasLimit,
        uint256 l2GasPerPubdataByteLimit
    ) public returns (address) {
        bytes memory bytecode = _compileContract(fileName);

        bytes32 bytecodeHash = L2ContractHelper.hashL2Bytecode(bytecode);
        bytes memory encodedDeployment = abi.encodeCall(IContractDeployer.create2, (salt, bytecodeHash, params));
        IMailbox mailbox = IMailbox(diamondProxy);

        ///@notice prep factoryDeps
        bytes[] memory factoryDeps = new bytes[](1);
        factoryDeps[0] = bytecode;

        ///@notice prep value
        uint256 baseFee = mailbox.l2TransactionBaseCost(tx.gasprice, gasLimit, l2GasPerPubdataByteLimit);

        ///@notice Deploy from Layer 1
        _vm.broadcast(_vm.envUint("PRIVATE_KEY"));
        mailbox.requestL2Transaction{
            value: baseFee * (100 + L2_BASE_FEE_BUFFER) / 100
        }(
            L2_DEPLOYER_SYSTEM_CONTRACT_ADDR, // address _contracts
            0, // uint256 _l2Value
            encodedDeployment, // bytes calldata _calldata
            gasLimit, // uint256 _gasLimit
            l2GasPerPubdataByteLimit, // uint256 _l2GasPerPubdataByteLimit
            factoryDeps, // bytes[] calldata _factoryDeps
            address(this) // address _refundRecipient
        );

        ///@notice Compute deployment address
        address deployer = _vm.addr(_vm.envUint("PRIVATE_KEY"));
        bytes32 paramsHash = keccak256(params);
        return L2ContractHelper.computeCreate2Address(deployer, salt, bytecodeHash, paramsHash);
    }

    function _compileContract(string memory fileName) internal returns (bytes memory bytecode) {
        ///@notice Compiles the contract using zksolc
        string[] memory cmds = new string[](3);
        cmds[0] = zksolcPath;
        cmds[1] = "--bin";
        cmds[2] = fileName;
        string memory compilerOutput = string(_vm.ffi(cmds));

        ///@notice Raw compiler output includes some text as prefix which causes ffi
        ///        to default to reading as utf8 instead of bytes
        string memory utf8Bytecode = compilerOutput.toSlice().rsplit(" ".toSlice()).toString();

        ///@notice Pass stripped bytes back into ffi to parse correctly as bytes
        string[] memory echoCmds = new string[](2);
        echoCmds[0] = "echo";
        echoCmds[1] = utf8Bytecode;
        bytecode = _vm.ffi(echoCmds);
    }

    function _detectSystemInfo() private returns (SystemInfo memory systemInfo) {
        string[] memory cmds = new string[](2);

        ///@notice Try to check arch on windows
        cmds[0] = "echo";
        cmds[1] = "%PROCESSOR_ARCHITECTURE%";

        ///@notice %PROCESS_ARCHITECTURE% evaluated to something
        if (keccak256(bytes(_vm.ffi(cmds))) != keccak256(bytes(cmds[1]))) {
            systemInfo.os = "windows";
            systemInfo.arch = "amd64";
            systemInfo.extension = "exe";
            systemInfo.toolchain = "-gnu";
        } else {
            ///@notice Check os
            cmds[0] = "uname";
            cmds[1] = "-s";
            systemInfo.os = keccak256(bytes(_vm.ffi(cmds))) == keccak256(bytes("Darwin")) ? "macosx" : "linux";
            systemInfo.toolchain = keccak256(bytes(systemInfo.os)) == keccak256(bytes("linux")) ? "-musl" : "";

            ///@notice Check arch
            cmds[0] = "uname";
            cmds[1] = "-m";
            systemInfo.arch = keccak256(bytes(_vm.ffi(cmds))) == keccak256(bytes("arm64")) ? "arm64" : "amd64";
        }
    }

    ///@notice Ensure correct compiler bin is installed
    function _installCompiler(string memory version) internal returns (string memory path) {
        SystemInfo memory systemInfo = _detectSystemInfo();

        ///@notice Construct urls/paths
        string memory fileName = string(
            abi.encodePacked(
                "zksolc-",
                systemInfo.os,
                "-",
                systemInfo.arch,
                systemInfo.toolchain,
                "-v",
                version,
                systemInfo.extension
            )
        );
        string memory zksolcUrl =
            string(abi.encodePacked(ZKSOLC_BIN_REPO, "/raw/main/", systemInfo.os, "-", systemInfo.arch, "/", fileName));
        path = string(abi.encodePacked(projectRoot, "/lib/", fileName));

        ///@notice Download zksolc compiler bin
        string[] memory curlCmds = new string[](6);
        curlCmds[0] = "curl";
        curlCmds[1] = "-L";
        curlCmds[2] = zksolcUrl;
        curlCmds[3] = "--output";
        curlCmds[4] = path;
        curlCmds[5] = "--silent";
        _vm.ffi(curlCmds);

        ///@notice set correct file permissions
        string[] memory chmodCmds = new string[](3);
        chmodCmds[0] = "chmod";
        chmodCmds[1] = "+x";
        chmodCmds[2] = path;
        _vm.ffi(chmodCmds);
    }
}
