// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IWstEth is IERC20 {
    /// @notice Exchanges wstETH to stETH
    function unwrap(uint256 _wstETHAmount) external returns (uint256);

    /// @notice Exchanges stETH to wstETH
    function wrap(uint256 _stETHAmount) external returns (uint256);

    /// @notice Get amount of wstETH for a given amount of stETH
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);

    /// @notice Get amount of stETH for a given amount of wstETH
    function getStETHByWstETH(uint256 _stETHAmount) external view returns (uint256);
}
