// SPDX-License-Identifier: ISC
pragma solidity ^0.8.25;

import "../../src/StakedEbtc.sol";

library StakedEbtcStructHelper {
    function __rewardsCycleData(StakedEbtc _stakedEbtc)
        internal
        view
        returns (StakedEbtc.RewardsCycleData memory _return)
    {
        (_return.cycleEnd, _return.lastSync, _return.rewardCycleAmount) = _stakedEbtc.rewardsCycleData();
    }
}
