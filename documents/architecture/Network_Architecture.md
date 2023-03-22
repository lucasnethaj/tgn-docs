# Tagion Network Architecture

## Description of the services in a node
A node consist of the following services.


* [tagionwave](/src/bin-wave/README.md) is the main task responsible all the service
- Main services
	- [Tagion](/documents/architecture/Tagion.md) is the service which handles the all the services related to the rest of the services (And run the HashGraph).
	- [Tagion Factory](/documents/architecture/TagionFactory.md) This services takes care of the *mode* in which the network is started.
	- [TVM](/documents/architecture/TVM.md) ("Tagion Virtual Machine") is responsible for executing the instructions in the contract ensuring the contracts are compliant with Consensus Rules producing outputs and sending new contracts to the Epoch Creator.
	- [DART](/documents/architecture/DART.md "Distributed Archive of Random Transactions") service is reponsible for executing data-base instruction and read/write to the physical file system.
	- [Replicator](/documents/architecture/Replicator.md) service is responsible for keeping record of the database instructions both to undo, replay and publish the instructions sequantially.
	- [Contract Interface](/documents/architecture/ContractInterface.md) service is responsible for receiving contracts, ensuring a valid data format of HiRPC requests and compliance with the HiRPC protocol before it is executed in the system. 
	- [Collector](/documents/architecture/Collector.md) service is responsible for collecting input data for a Contract and ensuring the data is valid and signed before the contract is executed by the TVM.
	- [Transcript](/documents/architecture/Transcript.md) service is responsible for producing a Recorder ensuring correct inputs and output archives including no double input and output in the same Epoch and sending it to the DART.
	- [Epoch Creator](/documents/architecture/EpochCreator.md) service is responsible for resolving the Hashgraph and producing a consensus ordered list of events, an Epoch. 
	- [Epoch Dump](/documents/architecture/EpochDump.md) Service is responsible for writing the Epoch to a file as a backup.
	- [Node Interface](/documents/architecture/NodeInterface.md) service is responsible for handling and routing requests to and from the p2p node network.

* Support services
	- [Logger](/documents/architecture/Logger.md) takes care of handling the logger information for all the services.
	- [Logger Subscription](/documents/architecture/LoggerSubscription.md) The logger subscript take care of handling remote logger and event logging.
	- [Monitor](/documents/architecture/Monitor.md) Monitor interface to display the state of the HashGraph.


## Data Message flow
This graph show the primary data message flow in the network.

```graphviz
digraph Message_flow {
rankdir=UD;
  compound=true;
  labelangle=35;
  node [style=filled]
  node [ shape = "rect"];
  DART [shape = cylinder];
  TLS [ style=filled fillcolor=green ];
  P2P [ style=filled fillcolor=red]
  ContractInterface [ label="Contract\nInterface"]
  NodeInterface [ label="Node\nInterface"]
  Transcript [shape = note]
  EpochCreator [label="Epoch\nCreator"]
  subgraph cluster_1 {
    peripheries=0;
    TLS -> ContractInterface [label="HiRPC(contract)" color=green];
 	ContractInterface -> Collector [label=contract color=green];
	Collector -> TVM [label="contract-S" color=green];
	EpochCreator -> Collector [label=contract color=darkgreen];
	EpochCreator -> Transcript [label=epoch color=green];
    TVM -> Transcript [label="archives\nin/out" color=red];
  };
 subgraph cluster_2 {
    peripheries=0;
	TVM -> EpochCreator [label="contract-SC" color=green];
    DART -> Replicator [label=recorder color=red dir=both];
  };
  subgraph cluster_3 {
    peripheries=0;
	DART -> NodeInterface [label="DART(ro)\nrecorder" dir=both color=magenta];
    NodeInterface -> P2P [label=Document dir=both];
  };
  DART -> Collector [label=recorder color=red];
  EpochCreator -> NodeInterface [label=gossip dir=both color=cyan4];
  Transcript -> DART [label=recorder color=blue];
  Replicator -> NodeInterface [label=recorder];
}
```

## Tagion Service Hierarchy

This graph show the supervisor hierarchy of the services in the network.

The arrow indicates ownership is means of service-A points to service-B. Service-A has ownership of service-B.

This means that if Service-B fails service-A is responsible to handle and take-care of the action to restart or other action.


```graphviz
digraph tagion_hierarchy {
    rankdir=UD;
    size="8,5"
   node [style=filled shape=rect]
Tagionwave [color=blue]
TagionFactory [label="Tagion\nFactory"]
DART [shape = cylinder]
ContractInterface [label="Contract\nInterface"]
Transcript [shape = note]
Collector [shape=rect]
EpochCreator [label="Epoch\nCreator"]
EpochDump [label="Epoch\nDump"]
NodeInterface [shape=rect label="Node\nInterface"]
LoggerSubscription [label="Logger\nSubscription"]
TLS [color=green]
P2P [color=red]
node [shape = rect];
	Tagionwave -> Logger -> LoggerSubscription;
	Tagionwave -> TagionFactory;
	TagionFactory -> Tagion;
	Tagion -> NodeInterface -> P2P;
	DART -> Replicator;
	Tagion -> DART;
    Tagion -> EpochCreator;
	EpochCreator -> ContractInterface [href="/documents/architecture/ContractInterface.md"];
	EpochCreator -> Transcript;
	EpochCreator -> Collector;
	Transcript -> EpochDump;
	EpochCreator -> Monitor;
	Collector -> TVM;
	ContractInterface -> TLS;
}
```
