// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

interface IDeployer {
  /**
   * @dev Deploys a contract from L1 to L2 using default gas limit and gas per
          pubdata byte values.
   * @param fileName The name of the Solidity file containing the contract code 
            to be compiled.
   * @param params The initialization parameters for the contract.
   * @param salt A unique salt value used to derive the contract's address.
   * @return The deployed contract's address.
   */
  function deployFromL1(
    string memory fileName,
    bytes calldata params,
    bytes32 salt
  ) external returns (address);

  /**
   * @dev Deploys a contract from L1 to L2.
   * @param fileName The name of the Solidity file containing the contract code
            to be compiled.
   * @param params The initialization parameters for the contract.
   * @param salt A unique salt value used to derive the contract's address.
   * @param gasLimit The maximum amount of gas to be used for the L2 deployment
            transaction.
   * @param l2GasPerPubdataByteLimit The maximum amount of gas to be used per 
            pubdata byte.
   * @return The deployed contract's address.
   */
  function deployFromL1(
      string memory fileName,
      bytes calldata params,
      bytes32 salt,
      uint256 gasLimit,
      uint256 l2GasPerPubdataByteLimit
  ) external returns (address); 
}
