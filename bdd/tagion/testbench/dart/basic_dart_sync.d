module tagion.testbench.dart.basic_dart_sync;
// Default import list for bdd
import tagion.behaviour;
import tagion.hibon.Document;
import std.typecons : Tuple;
import std.path : setExtension, buildPath;
import std.file : mkdirRecurse;
import std.stdio;
import std.format : format;
import std.algorithm : map, filter, each, sort, equal;

import tagion.dart.DARTFakeNet;
import tagion.crypto.SecureInterfaceNet : SecureNet, HashNet;
import tagion.dart.DART : DART;
import tagion.dart.DARTFile : DARTFile;
import tagion.dart.Recorder : Archive, RecordFactory;

import tagion.dart.DARTBasic : DARTIndex, dartIndex;
import tagion.testbench.tools.Environment;
import tagion.utils.Miscellaneous : toHexString;
import tagion.testbench.dart.dartinfo;

import tagion.communication.HiRPC;
import tagion.hibon.HiBONJSON : toPretty;
import tagion.Keywords;
import std.range;
import tagion.utils.Random;
import std.random : randomShuffle, MinstdRand0, randomSample;


import tagion.hibon.HiBONRecord;

import tagion.testbench.dart.dart_helper_functions;
import std.digest;

enum feature = Feature(
        "DARTSynchronization",
        ["All test in this bdd should use dart fakenet."]);

alias FeatureContext = Tuple!(
    FullSync, "FullSync",
    PartialSync, "PartialSync",
    FeatureGroup*, "result"
);

@safe @Scenario("Full sync.",
    [])
class FullSync {
    DART db1;
    DART db2;

    DARTIndex[] db1_fingerprints;

    DartInfo info;

    this(DartInfo info) {
        this.info = info;
    }

    @Given("I have a dartfile1 with pseudo random data.")
    Document randomData() {
        check(!info.states.empty, "Pseudo random sequence not generated");

        mkdirRecurse(info.module_path);
        // create the dartfile
        DART.create(info.dartfilename);

        Exception dart_exception;
        db1 = new DART(info.net, info.dartfilename, dart_exception);
        check(dart_exception is null, format("Failed to open DART %s", dart_exception.msg));

        db1_fingerprints = randomAdd(info.states, MinstdRand0(312), db1);
        
        return result_ok;
    }

    @Given("I have a empty dartfile2.")
    Document emptyDartfile2() {
        DART.create(info.dartfilename2);
        
        Exception dart_exception;
        db2 = new DART(info.net, info.dartfilename2, dart_exception);
        check(dart_exception is null, format("Failed to open DART %s", dart_exception.msg));


        return result_ok;
    }

    @Given("I synchronize dartfile1 with dartfile2.")
    Document withDartfile2() {


        
        return Document();
    }

    @Then("the bullseyes should be the same.")
    Document theSame() {
        return Document();
    }

}

@safe @Scenario("Partial sync.",
    [])
class PartialSync {

    @Given("I have a dartfile1 with pseudo random data.")
    Document randomData() {
        return Document();
    }

    @Given("I have added some of the pseudo random data to dartfile2.")
    Document toDartfile2() {
        return Document();
    }

    @Given("I synchronize dartfile1 with dartfile2.")
    Document withDartfile2() {
        return Document();
    }

    @Then("the bullseyes should be the same.")
    Document theSame() {
        return Document();
    }

}
