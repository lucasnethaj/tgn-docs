module tagion.script.common;
@safe:

import std.algorithm;
import std.range;
import std.array;
import tagion.script.TagionCurrency;
import tagion.utils.StdTime;
import tagion.basic.Types;
import tagion.crypto.Types;
import tagion.crypto.SecureInterfaceNet;
import tagion.hibon.HiBONRecord;
import tagion.hibon.Document;
import tagion.dart.DARTBasic;
import tagion.script.ScriptException;
import tagion.basic.Types : Buffer;

enum StdNames {
    owner = "$Y",
    value = "$V",
    time = "$t",
    nonce = "$x",
    values = "$vals",
    derive = "$D",
}

@recordType("TGN") struct TagionBill {
    @label(StdNames.value) TagionCurrency value; /// Tagion bill 
    @label(StdNames.time) sdt_t time; // Time stamp
    @label(StdNames.owner) Pubkey owner; // owner key
    @label(StdNames.nonce, true) Buffer nonce; // extra nonce 
    mixin HiBONRecord!(
            q{
                this(const(TagionCurrency) value, const sdt_t time, Pubkey owner, Buffer nonce) pure {
                    this.value = value;
                    this.time = time;
                    this.owner = owner;
                    this.nonce = nonce;
                }
            });
}

@recordType("SMC") struct Contract {
    @label("$in") const(DARTIndex)[] inputs; /// Hash pointer to input (DART)
    @label("$read", true) const(DARTIndex)[] reads; /// Hash pointer to read-only input (DART)
    @label("$run") Document script; // Smart contract 
    bool verify() {
        return (inputs.length > 0);
    }

    mixin HiBONRecord!(
            q{
                this(const(DARTIndex)[] inputs, const(DARTIndex)[] reads, Document script) pure nothrow {
                    this.inputs = inputs;
                    this.reads = reads;
                    this.script = script; 
                }
                this(immutable(DARTIndex)[] inputs, immutable(DARTIndex)[] reads, immutable(Document) script) immutable nothrow {
                    this.inputs = inputs;
                    this.reads = reads;
                    this.script = script; 
                }
            });
}

@recordType("SSC") struct SignedContract {
    @label("$signs") const(Signature)[] signs; /// Signature of all inputs
    @label("$contract") Contract contract; /// The contract must signed by all inputs
    mixin HiBONRecord!(
            q{
                this(const(Signature)[] signs, Contract contract) pure nothrow {
                    this.signs = signs;
                    this.contract = contract;
                }
                this(immutable(Signature)[] signs, immutable(Contract) contract) nothrow immutable {
                    this.signs = signs;
                    this.contract = contract;
                }
            });
}

@recordType("pay")
struct PayScript {
    @label(StdNames.values) const(TagionBill)[] outputs;
    mixin HiBONRecord!(
            q{
                this(const(TagionBill)[] outputs) pure nothrow {
                    this.outputs = outputs;
                }
            });
}

Signature[] sign(const(SecureNet[]) nets, const(Contract) contract) {
    const message = nets[0].calcHash(contract);
    return nets
        .map!(net => net.sign(message))
        .array;
}

const(SignedContract) sign(const(SecureNet[]) nets, const(Document[]) inputs, const(Document[]) reads, const(Document) script) {
    check(nets.length > 0, "At least one input contract");
    check(nets.length == inputs.length, "Number of signature does not match the number of inputs");
    const net = nets[0];
    SignedContract result;
    auto sorted_inputs = inputs
        .map!((input) => cast(DARTIndex) net.dartIndex(input))
        .enumerate
        .array
        .sort!((a, b) => a.value < b.value)
        .array;

    result.contract = Contract(
            sorted_inputs.map!((input) => input.value).array,
            reads.map!(doc => net.dartIndex(doc)).array,
            Document(script),
    );
    result.signs = sign(sorted_inputs.map!((input) => nets[input.index]).array, result.contract);
    return result;
}

bool verify(const(SecureNet) net, const(SignedContract*) signed_contract, const(Pubkey[]) owners) nothrow {
    try {
        if (signed_contract.contract.inputs.length == owners.length) {
            const message = net.calcHash(signed_contract.contract);
            return zip(signed_contract.signs, owners)
                .all!((a) => net.verify(message, a[0], a[1]));
        }
    }
    catch (Exception e) {
        // ignore
    }
    return false;
}

bool verify(const(SecureNet) net, const(SignedContract*) signed_contract, const(Document[]) inputs) nothrow {
    try {
        return verify(net, signed_contract, inputs.map!(doc => doc[StdNames.owner].get!Pubkey).array);
    }
    catch (Exception e) {
        //ignore
    }
    return false;
}
