Feature HiRPC format checker
The feature should make sure that the HiRPC has the correct format.


Scenario a data package which exceed the maximum size.

Given a data package with size larger than the maximum.

Given that a connection to the logs on the transaction service.

Given the data package is send to the selected active node A in the network.

When the data package has been received by the network.

Then the size of the data package should be check and the should be rejected,
if the size larger than the maximum size.


Scenario a malformed data packed should be rejected

Given a data package is not a correctly HiRPC format.

When the data package has been receive by the network.

Then network should check if the data package is a valid HiRPC
and if the package is invalid then the should be rejected.


Scenario a data package which is not a HiRPC

Given a data package which is not a correctly HiRPC.

When the data package has been received by the network.

Then the package should be check that it is a correct HiRPC and if it is not it should be rejected.


Scenario corrected format HiRPC

Given a correctly format transaction.

When the data package has been received by the network.

When the data package has been verified that it is correct HiRPC.

Then the HiRPC should be approved.



