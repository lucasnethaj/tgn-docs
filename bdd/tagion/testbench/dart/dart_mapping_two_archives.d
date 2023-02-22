module tagion.testbench.dart.dart_mapping_two_archives;
// Default import list for bdd
import tagion.behaviour;
import tagion.hibon.Document;
import std.typecons : Tuple;
import std.path : setExtension, buildPath;
import std.file : mkdirRecurse;
import std.stdio : writefln;
import std.format : format;

import tagion.dart.DARTFakeNet;
import tagion.crypto.SecureInterfaceNet : SecureNet, HashNet;
import tagion.dart.DART : DART;
import tagion.dart.DARTFile : DARTFile;
import tagion.dart.Recorder : Archive, RecordFactory;

import tagion.dart.DARTBasic : DARTIndex, dartIndex;
import tagion.testbench.tools.Environment;
import tagion.actor.TaskWrapper;
import tagion.utils.Miscellaneous : toHexString;
import tagion.testbench.dart.dartinfo;

import tagion.communication.HiRPC;
import tagion.hibon.HiBONJSON : toPretty;
import tagion.Keywords;
import tagion.basic.Types : Buffer;
import std.range;
import std.digest;

import tagion.hibon.HiBONType;


enum feature = Feature(
        "Dart mapping of two archives",
        ["All test in this bdd should use dart fakenet."]);

alias FeatureContext = Tuple!(
    AddOneArchive, "AddOneArchive",
    AddAnotherArchive, "AddAnotherArchive",
    RemoveArchive, "RemoveArchive",
    FeatureGroup*, "result"
);

DARTIndex[] fingerprints;

@safe @Scenario("Add one archive.",
    ["mark #one_archive"])
class AddOneArchive {
    DART db;

    DARTIndex doc_fingerprint;
    DARTIndex bullseye;
    const DartInfo info;

    this(const DartInfo info) {
        this.info = info;
    }

    @Given("I have a dartfile.")
    Document dartfile() {
        // create the directory to store the DART in.
        mkdirRecurse(info.module_path);
        // create the dartfile
        DART.create(info.dartfilename);

        Exception dart_exception;
        db = new DART(info.net, info.dartfilename, dart_exception);
        check(dart_exception is null, format("Failed to open DART %s", dart_exception.msg));

        return result_ok;
    }

    @Given("I add one archive1 in sector A.")
    Document a() {

        auto recorder = db.recorder();
        const doc = DARTFakeNet.fake_doc(info.table[0]);
        recorder.add(doc);
        doc_fingerprint = DARTIndex(recorder[].front.fingerprint);
        bullseye = db.modify(recorder);
        return result_ok;
    }

    @Then("the archive should be read and checked.")
    Document checked() {
        check(doc_fingerprint == bullseye, "fingerprint and bullseyes not the same");
        fingerprints ~= doc_fingerprint;
        db.close();
        return result_ok;
    }

}

@safe @Scenario("Add another archive.",
    ["mark #two_archives"])
class AddAnotherArchive {

    DART db;
    DARTIndex doc_fingerprint;
    DARTIndex bullseye;
    enum FAKE = "$fake#";

    const DartInfo info;
    this(const DartInfo info) {
        this.info = info;
    }

    @Given("#one_archive")
    Document onearchive() {
        Exception dart_exception;
        db = new DART(info.net, info.dartfilename, dart_exception);
        check(dart_exception is null, format("Failed to open DART %s", dart_exception.msg));

        const bullseye = db.bullseye();
        const doc = DARTFakeNet.fake_doc(info.table[0]);
        const doc_bullseye = dartIndex(info.net, doc);
        check(bullseye == doc_bullseye, "Bullseye not equal to doc");

        return result_ok;
    }

    @Given("i add another archive2 in sector A.")
    Document inSectorA() {
        auto recorder = db.recorder();
        const doc = DARTFakeNet.fake_doc(info.table[1]);
        recorder.add(doc);
        doc_fingerprint = DARTIndex(recorder[].front.fingerprint);
        bullseye = db.modify(recorder);

        check(doc_fingerprint != bullseye, "Bullseye not updated");

        fingerprints ~= doc_fingerprint;

        return result_ok;

    }

    @Then("both archives should be read and checked.")
    Document readAndChecked() {

        const sender = DART.dartRead(fingerprints, info.hirpc);
        auto receiver = info.hirpc.receive(sender.toDoc);
        auto result = db(receiver, false);
        const doc = result.message[Keywords.result].get!Document;
        const recorder = db.recorder(doc);

        foreach (i, data; recorder[].enumerate) {
            const(ulong) archive = data.filed[FAKE].get!ulong;
            check(archive == info.table[i], "Retrieved data not the same");
        }

        return result_ok;
    }

    @Then("check the branch of sector A.")
    Document ofSectorA() @trusted {

        const sender = DART.dartRim(DART.Rims.root, info.hirpc);
        auto receiver = info.hirpc.receive(sender.toDoc);
        auto result = db(receiver, false);
        const doc = result.message[Keywords.result].get!Document;

        auto branches = DARTFile.Branches(doc);
        check(DARTFile.Branches.isRecord(doc) == true, "Should not be an archive because multiple data is stored");


        // auto test = doc["$prints"].get!uint;
        writefln("%s", branches);
        
        return result_ok;
    }

    @Then("check the bullseye.")
    Document checkTheBullseye() {
        check(bullseye == info.net.calcHash(fingerprints[0], fingerprints[1]), "Bullseye not equal to the hash of the two archives");
        db.close();
        return result_ok;
    }
}

@safe @Scenario("Remove archive", [])
class RemoveArchive {
    DART db;

    DARTIndex doc_fingerprint;
    DARTIndex bullseye;
    const DartInfo info;

    this(const DartInfo info) {
        this.info = info;
    }

    @Given("#two_archives")
    Document twoarchives() {
        Exception dart_exception;
        db = new DART(info.net, info.dartfilename, dart_exception);
        check(dart_exception is null, format("Failed to open DART %s", dart_exception.msg));

        // should we check something here???
        return result_ok;
    }

    @Given("i remove archive1.")
    Document archive1() {

        auto recorder = db.recorder();
        recorder.remove(fingerprints[0]);
        bullseye = db.modify(recorder);
        
        return result_ok;
    }

    @Then("check that archive2 has been moved from the branch in sector A.")
    Document a() {
        return Document();
    }

    @Then("check the bullseye.")
    Document _bullseye() {
        check(bullseye == fingerprints[1], "Bullseye not updated correctly. Not equal to other element");
        return result_ok;
    }
}
