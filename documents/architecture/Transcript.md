# Transcript Service

This service is responsible for producing a Recorder ensuring correct inputs and output archives including no double input and output in the same Epoch and sending it to the DART.

Input:
  - Receives an Epoch list contaning ordered events from the [Epoch Creator](/documents/architecture/EpochCreator.md).

Request:
  - Request to all the inputs and draft outputs archives from the TVM.

Output:
  - A DART-recorder is sent to the [DART](/documents/architecture/DART.md)

The acceptance criteria specification can be found in [Transcript_services](/bdd/tagion/testbench/services/ContractInterface_service.md).

```mermaid
sequenceDiagram
    participant TVM 
    participant Epoch Creator 
    participant Transcript
    participant DART 
    Epoch Creator ->> Transcript: Epoch list  
    TVM ->> Transcript: Input/Draft Output Archives
    Transcript ->> DART: Recorder
```

