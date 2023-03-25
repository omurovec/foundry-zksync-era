// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.13;

uint256 constant L2_TX_MAX_GAS_LIMIT = 2097152;
uint256 constant DEFAULT_L2_GAS_PRICE_PER_PUBDATA = 800;

// Add buffer to base fee since it can change before tx is executed
// In percent form (10%)
uint256 constant L2_BASE_FEE_BUFFER = 10;

string constant ZKSOLC_BIN_REPO = "https://github.com/matter-labs/zksolc-bin";
