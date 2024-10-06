// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface ICollateral is IERC20 {
  function getSharesByPooledEth(uint256 _ethAmount) external view returns (uint256);
}
