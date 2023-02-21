// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.13;

import "forge-std/Vm.sol";
import "solidity-stringutils/strings.sol";
import "era-contracts/ethereum/contracts/zksync/interfaces/IMailbox.sol";
import "era-contracts/ethereum/contracts/common/L2ContractHelper.sol";
import "era-contracts/zksync/contracts/vendor/AddressAliasHelper.sol";

import {
    L2_TX_MAX_GAS_LIMIT,
    DEFAULT_L2_GAS_PRICE_PER_PUBDATA,
    ZKSOLC_BIN_REPO
} from "./Constants.sol";

contract Deployer {
    using strings for *;

    VmSafe _vm = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    ///@notice Compiler & deployment config
    string private projectRoot;
    string private zksolcPath;
    address private diamondProxy;

    constructor(string memory _zksolcVersion, address _diamondProxy) {
        ///@notice install bin compiler
        projectRoot = _vm.projectRoot();
        zksolcPath = _installCompiler(_zksolcVersion);

        diamondProxy = _diamondProxy;
    }


    function deployFromL1(string memory fileName, bytes calldata params, bytes32 salt, bool broadcast) public {
        deployFromL1(fileName, params, salt, broadcast, L2_TX_MAX_GAS_LIMIT, DEFAULT_L2_GAS_PRICE_PER_PUBDATA);
    }

    function deployFromL1(string memory fileName, bytes calldata params, bytes32 salt, bool broadcast, uint256 gasLimit, uint256 l2GasPerPubdataByteLimit)
        public
        returns (address)
    {
        bytes memory bytecode = _compileContract(fileName);

        bytes32 bytecodeHash = L2ContractHelper.hashL2Bytecode(bytecode);
        bytes memory encodedDeployment = abi.encodeCall(IContractDeployer.create2, (salt, bytecodeHash, params));

        ///@notice prep factoryDeps
        bytes[] memory factoryDeps = new bytes[](1);
        factoryDeps[0] = bytecode;

        ///@notice Deploy from Layer 1
        if (broadcast) _vm.broadcast(_vm.envUint("PRIVATE_KEY"));
        IMailbox(diamondProxy).requestL2Transaction(
            DEPLOYER_SYSTEM_CONTRACT_ADDRESS, // address _contracts
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

    function _installCompiler(string memory version) internal returns (string memory path) {
        ///@notice Ensure correct compiler bin is installed
        string memory os = _vm.envString("OS");
        string memory arch = _vm.envString("ARCH");
        string memory extension = keccak256(bytes(os)) == keccak256(bytes("windows")) ? "exe" : "";

        ///@notice Get toolchain
        string memory toolchain = "";
        if (keccak256(bytes(os)) == keccak256(bytes("windows"))) {
            toolchain = "-gnu";
        } else if (keccak256(bytes(os)) == keccak256(bytes("linux"))) {
            toolchain = "-musl";
        }

        ///@notice Construct urls/paths
        string memory fileName = string(abi.encodePacked("zksolc-", os, "-", arch, toolchain, "-v", version, extension));
        string memory zksolcUrl = string(abi.encodePacked(ZKSOLC_BIN_REPO, "/raw/main/", os, "-", arch, "/", fileName));
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
