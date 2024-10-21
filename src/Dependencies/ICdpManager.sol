// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.25;

interface ICdpManager {
    function getSyncedSystemCollShares() external view returns (uint256);
}
