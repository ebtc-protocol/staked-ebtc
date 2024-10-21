// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.25;

import { LinearRewardsErc4626 } from "./LinearRewardsErc4626.sol";

interface IStakedEbtc {
    function REWARDS_CYCLE_LENGTH() external view returns (uint256);
    function asset() external view returns (address);
    function donate(uint256 amount) external;
    function syncRewardsAndDistribution() external;
    function rewardsCycleData() external view returns (LinearRewardsErc4626.RewardsCycleData memory);
    function storedTotalAssets() external view returns (uint256);
    function totalBalance() external view returns (uint256);
}
