module tagion.testbench.dart.dart_middle_branch;
// Default import list for bdd
import std.algorithm : filter, map;
import std.file : mkdirRecurse;
import std.format : format;
import std.range;
import std.stdio : writefln;
import std.typecons : Tuple;
import tagion.basic.Types : Buffer, mut;
import tagion.behaviour;
import tagion.communication.HiRPC;
import tagion.crypto.SecureInterfaceNet : HashNet, SecureNet;
import tagion.crypto.Types : Fingerprint;
import tagion.dart.DART : DART;
import tagion.dart.DARTBasic : DARTIndex, dartIndex;
import tagion.dart.DARTFakeNet;
import tagion.dart.DARTFile : DARTFile;
import tagion.dart.DARTRim;
import tagion.dart.Recorder : Archive, RecordFactory;
import tagion.hibon.Document;
import tagion.hibon.HiBONJSON : toPretty;
import tagion.hibon.HiBONRecord;
import tagion.testbench.dart.dart_helper_functions : getFingerprints, getRead, getRim, goToSplit;
import tagion.testbench.dart.dartinfo;
import tagion.testbench.tools.Environment;

enum feature = Feature(
            "Dart snap middle branch",
            [
        "All test in this bdd should use dart fakenet. This test covers after a archive has been removed, if when adding a new archive on top, that the branch snaps back."
]);

alias FeatureContext = Tuple!(
        AddOneArchiveAndSnap, "AddOneArchiveAndSnap",
        FeatureGroup*, "result"
);

@safe @Scenario("Add one archive and snap.",
        [])
class AddOneArchiveAndSnap {

    DART db;

    DARTIndex doc_dart_index;
    Fingerprint doc_fingerprint;
    Fingerprint bullseye;
    const DartInfo info;

    this(const DartInfo info) {
        this.info = info;
    }

    @Given("I have a dartfile with one archive.")
    Document archive() {
        Exception dart_exception;
        db = new DART(info.net, info.dartfilename, dart_exception);
        check(dart_exception is null, format("Failed to open DART %s", dart_exception.msg));
        const bullseye = db.bullseye();

        const doc = DARTFakeNet.fake_doc(info.deep_table[1]);
        const doc_bullseye = dartIndex(info.net, doc);

        check(bullseye == doc_bullseye, "Bullseye not equal to doc");
        // db.dump;
        return result_ok;
    }

    @Given("I add one archive2 in the same sector.")
    Document sector() {
        auto recorder = db.recorder();
        const doc = DARTFakeNet.fake_doc(info.deep_table[2]);
        recorder.add(doc);
        pragma(msg, "fixme(cbr): Should this be Fingerprint or DARTIndex");
        doc_dart_index = recorder[].front.dart_index.mut;
        doc_fingerprint = recorder[].front.fingerprint.mut;
        bullseye = db.modify(recorder);

        check(doc_fingerprint != bullseye, "Bullseye not updated");
        // db.dump();
        return result_ok;
    }

    @Then("the branch should snap back.")
    Document back() {
        const doc = goToSplit(Rims.root, info.hirpc, db);

        const DARTIndex[] fingerprints = getFingerprints(doc, db);
        const read_doc = getRead(fingerprints, info.hirpc, db);
        const recorder = db.recorder(read_doc);

        foreach (i, data; recorder[].enumerate) {
            const(ulong) archive = data.filed[info.FAKE].get!ulong;
            check(archive == info.deep_table[i + 1], "Retrieved data not the same");
        }

        auto rim_fingerprints = DARTFile.Branches(doc)
            .fingerprints
            .filter!(f => !f.empty)
            .array;

        foreach (i; 0 .. 2) {
            const rim = Rims(rim_fingerprints[i][0 .. 3]);
            const rim_doc = getRim(rim, info.hirpc, db);

            check(RecordFactory.Recorder.isRecord(rim_doc), format("branch %s not snapped back", rim));
        }

        return result_ok;
    }

}
