// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.25;

interface IActivePool {
    function claimFeeRecipientCollShares(uint256 _shares) external;
    function getSystemCollShares() external view returns (uint256);
    function getFeeRecipientClaimableCollShares() external view returns (uint256);
}
