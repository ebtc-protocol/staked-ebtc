# staked-ebtc
Staked eBTC (steBTC) is designed to be a yield-bearing version of eBTC.

It's a fork of sFRAX with some changes
* Authorized donations
    * Authorized donors can donate eBTC via the `donate()` function. This is done on a weekly basis to reward steBTC depositors.
* Minting fee mechanism
    * eBTC depends on stETH rebases to generate protocol revenue (PYS). Since rebases happen daily, it's possible to mint eBTC right after a rebase and pay it back 1-2 hours before the next rebase. This allows someone to bypass the PYS completely. To avoid the possibility of gaming the system like this, we've decided to introduce a minting fee mechanism.
* Token sweeping
    * Remove unauthorized donations to the contract
