# Proveably Random Raffle Contracts

## About

This code creates a proveably random smart contract lottery

## What it does

1. Users pay for ticket
2. Lottery draws winner
3. Using chainlink VRF and chainlink automation
   1. chainlink vrf -> randomness
   2. chainlink automation -> time based trigger

## Tests

1. Write some deploy scripts
2. Write our tests
   1. local chain
   2. forked testnet
   3. forked mainnet

## Coverage check
forge coverage --report debug > coverage.txt

## NOTE

- This will only work locally on anvil chain as it is configured for VRFCoordinator v2.0 which is now deprecated with v2.5 being the new standard. The code has not been refactored to handle the new v2.5 VRF