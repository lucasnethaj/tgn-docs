module tagion.services.messages;
import tagion.actor.actor;
import tagion.hibon.Document;
import tagion.script.StandardRecords;

/// Msg Type sent to actors who receive the document
alias inputDoc = Msg!"inputDoc";
/// Msg type sent to receiver task along with a hirpc
alias inputHiRPC = Msg!"inputHiRPC";

alias inputContract = Msg!"contract";
alias inputRecorder = Msg!"recorder";

alias signedContract = Msg!"contract-S";
alias consensusContract = Msg!"contract-C";

alias consensusEpoch = Msg!"consensus_epoch";
alias producedContract = Msg!"produced_contract";


alias dartReadRR = Request!"dartRead";
alias dartRimRR = Request!"dartRim";
alias dartBullseyeRR = Request!"dartBullseye";
alias dartModifyRR = Request!"dartModify";


@safe
struct ContractProduct {
    CollectedSignedContract contract;
    Document[] outputs;
}

@safe
struct CollectedSignedContract {
    Document[] inputs;
    Document[] reads;
    SignedContract contract;
    //    mixin HiBONRecord;
}
