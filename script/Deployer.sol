// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.13;

import "forge-std/StdJson.sol";
import "forge-std/Test.sol";
import "solidity-stringutils/strings.sol";
import "era-contracts/ethereum/contracts/zksync/interfaces/IMailbox.sol";
import "era-contracts/ethereum/contracts/common/L2ContractHelper.sol";
import "era-contracts/zksync/contracts/vendor/AddressAliasHelper.sol";

///@notice This cheat codes interface is named _CheatCodes so you can use the CheatCodes interface in other testing files without errors
interface _CheatCodes {
    function ffi(string[] calldata) external returns (bytes memory);
    function envString(string calldata key) external returns (string memory value);
    function envUint(string calldata key) external returns (uint256 value);
    function parseJson(string memory json, string memory key) external returns (string memory value);
    function writeFile(string calldata, string calldata) external;
    function readFile(string calldata) external returns (string memory);
    function createFork(string calldata) external returns (uint256);
    function selectFork(uint256 forkId) external;
    function broadcast(uint256 privateKey) external;
    function allowCheatcodes(address) external;
    function addr(uint256 privateKey) external returns (address);
}

contract Deployer is Test {
    using stdJson for string;
    using strings for *;

    ///@notice Addresses taken from zksync-v2-testnet/l2/system-contracts/Constants.sol
    ///@notice Cannot import due to conflicts
    uint160 constant SYSTEM_CONTRACTS_OFFSET = 0x8000; // 2^15
    IContractDeployer constant DEPLOYER_SYSTEM_CONTRACT = IContractDeployer(address(SYSTEM_CONTRACTS_OFFSET + 0x06));

    ///@notice Custom override for cheatCodes
    /* address constant HEVM_ADDRESS = address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))); */
    _CheatCodes cheatCodes = _CheatCodes(HEVM_ADDRESS);

    ///@notice Fork IDs
    uint256 public l1;
    uint256 public l2;

    constructor() {
        l1 = cheatCodes.createFork("layer_1");
    }

    function compileContract(string memory fileName) public returns (bytes memory bytecode) {
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
        cmds[0] = "./helper.sh";
        cmds[1] = zksolcPath;
        cmds[2] = fileName;

        bytecode = cheatCodes.ffi(cmds);

        if(bytecode.length % 64 > 32) {
            bytes memory padding = new bytes(64 - bytecode.length % 64);
            bytecode = abi.encodePacked(padding, bytecode);
        } else if(bytecode.length % 64 < 32) {
            bytes memory padding = new bytes(32 - bytecode.length % 64);
            bytecode = abi.encodePacked(padding, bytecode);
        }
    }

    ///@notice taken from zksync-v2-testnet/l1/contracts/common/L2ContractHelper.sol
    function hashL2Bytecode(bytes memory _bytecode) internal pure returns (bytes32 hashedBytecode) {
        // Note that the length of the bytecode
        // must be provided in 32-byte words.
        require(_bytecode.length % 32 == 0, "po");

        uint256 bytecodeLenInWords = _bytecode.length / 32;
        require(bytecodeLenInWords < 2**16, "pp"); // bytecode length must be less than 2^16 words
        require(bytecodeLenInWords % 2 == 1, "pr"); // bytecode length in words must be odd
        hashedBytecode = sha256(_bytecode) & 0x00000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        // Setting the version of the hash
        hashedBytecode = (hashedBytecode | bytes32(uint256(1 << 248)));
        // Setting the length
        hashedBytecode = hashedBytecode | bytes32(bytecodeLenInWords << 224);
    }

    function deployContract(string memory fileName, bytes calldata params, bool broadcast, address diamondProxy) public returns (address) {
        bytes memory bytecode = compileContract(fileName);

        bytes32 salt = bytes32(0);
        bytes32 bytecodeHash = hashL2Bytecode(bytecode);
        bytes memory encodedDeployment = abi.encodeCall(IContractDeployer.create2, (salt, bytecodeHash, params));

        ///@notice prep factoryDeps
        bytes[] memory factoryDeps = new bytes[](1);
        factoryDeps[0] = bytecode;

        // Switch to L1
        cheatCodes.allowCheatcodes(address(this));
        cheatCodes.selectFork(l1);

        ///@notice Deploy from Layer 1
        if (broadcast) cheatCodes.broadcast(cheatCodes.envUint("PRIVATE_KEY"));
        bytes32 txHash = IMailbox(diamondProxy).requestL2Transaction(
            address(DEPLOYER_SYSTEM_CONTRACT), // address _contracts
            0, // uint256 _l2Value
            encodedDeployment, // bytes calldata _calldata
            2097152, // uint256 _ergsLimit
            800, // uint256 _l2GasPerPubdataByteLimit
            factoryDeps, // bytes[] calldata _factoryDeps
            address(this) // address _refundRecipient
        );

        ///@notice Log deployment txHash
        emit log_named_bytes32(string(abi.encodePacked("Deploying ", fileName, " in transaction ")), txHash);

        ///@notice Compute deployment address
        address deployer = cheatCodes.addr(cheatCodes.envUint("PRIVATE_KEY"));
        address deployerAlias = AddressAliasHelper.applyL1ToL2Alias(deployer);
        bytes32 paramsHash = keccak256(params);
        address contractAddress = L2ContractHelper.computeCreate2Address(deployerAlias, salt, bytecodeHash, paramsHash);

        ///@notice Log deployment address
        emit log_named_address(string(abi.encodePacked(fileName, " to be deployed to")), contractAddress);
    }

}
