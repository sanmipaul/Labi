// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title CrossChainUtils
/// @notice Utility functions for cross-chain operations
library CrossChainUtils {
    /// @notice Checks if a dstEid is supported
    /// @param dstEid The destination endpoint ID
    /// @return bool True if supported
    function isSupportedChain(uint32 dstEid) internal pure returns (bool) {
        // For now, support Ethereum and Base
        return dstEid == 30101 || dstEid == 184; // Ethereum mainnet and Base
    }

    /// @notice Gets the chain name for an eid
    /// @param eid The endpoint ID
    /// @return string The chain name
    function getChainName(uint32 eid) internal pure returns (string memory) {
        if (eid == 30101) return "Ethereum";
        if (eid == 184) return "Base";
        return "Unknown";
    }
}