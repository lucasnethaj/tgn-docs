Feature: double spend scenarios

Scenario: Same inputs spend on one contract
Given i have a malformed contract correctly signed with two inputs which are the same
When i send the contract to the network
Then the contract should be rejected.

Scenario: one contract where some bills are used twice.
Given i have a malformed contract correctly signed with three inputs where to are the same.
When i send the contract to the network
Then the contract should be rejected.

Scenario: Different contracts different nodes.
Given i have two correctly signed contracts.
When i send the contracts to the network at the same time.
Then both contracts should go through.

Scenario: Same contract different nodes.
Given i have a correctly signed contract.
When i send the same contract to two different nodes.
Then the first contract should go through and the second one should be rejected.

Scenario: Same contract in different epochs.
Given i have a correctly signed contract.
When i send the contract to the network in different epochs to the same node.
Then the first contract should go through and the second one should be rejected.

Scenario: Same contract in different epochs different node.
Given i have a correctly signed contract.
When i send the contract to the network in different epochs to different nodes.
Then the first contract should go through and the second one should be rejected.

Scenario: Two contracts same output
Given i have a payment request containing a bill.
When i pay the bill from two different wallets.
Then only one output should be produced.

Scenario: Bill age
Given i pay a contract where the output bills timestamp is newer than epoch_time + constant.
When i send the contract to the network.
Then the contract should be rejected.

 


