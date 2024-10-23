# Recon 

The `recon/` directory contains all files related to the invariant fuzzing setup for the system.

## Running The Fuzzer With Local Setup 

To run the fuzzing setup where all contracts are deployed locally there is no further configuration required and can be done using the `make echidna-local` and `make medusa-local` commands defined in the `makefile`. 

## Running The Fuzzer With Forked Setup 

To run the fuzzing setup on the forked chain state, rename the `.env.example` file to `.env` and add an rpc url and block that you want to fork from. 

You can then run Echidna in fork mode using the `echidna-fork` command defined in the `makefile`.

NOTE: only Echidna allows fork testing, Medusa currently doesn't support this.

## Running Reproducers

If a property breaks when a Recon job is run on it, the broken property will automatically show up on the job page with a Foundry unit test to reproduce the broken property locally. 

### For Local Setup

If the Recon job was not run in fork testing mode the reproducer can be added to the `CryticToFoundry` contract. 

### Fork Forked Setup

To ensure consistency between the environment in which Recon ran the fuzzer and your local Foundry environment, grab the block number from the job page (or coverage report for recurring jobs) and add it to the .env file along with an rpc url as described in the _Running The Fuzzer With Forked Setup_ section.

The reproducer can then be added to the `CryticToForkFoundry` contract and you will be able to reproduce the broken property from the same configuration that Echidna used. 