// common Message types sent between services
module tagion.services.messages;
import tagion.actor.actor;
import tagion.hibon.Document;
import tagion.script.prior.StandardRecords;

/// Msg Type sent to actors who receive the document
alias inputDoc = Msg!"inputDoc";
/// Msg type sent to receiver task along with a hirpc
alias inputHiRPC = Msg!"inputHiRPC";

/// Contracts sent to the collector
alias inputContract = Msg!"contract";
alias signedContract = Msg!"contract-S";
alias consensusContract = Msg!"contract-C";

alias inputRecorder = Msg!"recorder";

alias consensusEpoch = Msg!"consensus_epoch";
alias producedContract = Msg!"produced_contract";

/// dartCRUD
alias dartReadRR = Request!"dartRead";
alias dartCheckReadRR = Request!"dartCheckRead";
alias dartRimRR = Request!"dartRim";
alias dartBullseyeRR = Request!"dartBullseye";
alias dartModifyRR = Request!"dartModify";

alias Payload = Msg!"Payload";
alias ReceivedWavefront = Msg!"ReceivedWavefront";
alias AddedChannels = Msg!"AddedChannels";
alias BeginGossip = Msg!"BeginGossip";

@safe
struct _ContractProduct {
    immutable(_CollectedSignedContract*) contract;
    Document[] outputs;
}

@safe
struct _CollectedSignedContract {
    Document[] inputs;
    Document[] reads;
    SignedContract contract;
    //mixin HiBONRecord;
}
