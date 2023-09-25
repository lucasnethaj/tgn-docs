module tagion.testbench.services.DARTService;

import tagion.behaviour;
import tagion.hibon.Document;
import std.typecons : Tuple;
import tagion.testbench.tools.Environment;

import tagion.actor;
import tagion.services.DART;
import tagion.services.messages;
import std.stdio;
import std.path;
import std.file : exists, remove;
import std.algorithm;
import std.array;
import tagion.testbench.dart.dart_helper_functions;
import tagion.dart.Recorder;
import tagion.utils.pretend_safe_concurrency;
import tagion.dart.DARTBasic : DARTIndex;

// import tagion.crypto.SecureNet;
import tagion.crypto.SecureInterfaceNet;
import tagion.crypto.SecureNet : StdSecureNet;
import tagion.dart.DART;
import tagion.dart.DARTBasic;
import std.random;
import tagion.hibon.HiBONRecord;
import tagion.basic.Types;
import tagion.crypto.Types;
import tagion.communication.HiRPC;
import tagion.dart.DARTcrud : dartRead, dartBullseye, dartCheckRead;
import tagion.dart.DARTFile : DARTFile;
import tagion.hibon.HiBONJSON;
import tagion.Keywords;
import tagion.services.replicator;

enum feature = Feature(
            "see if we can read and write trough the dartservice",
            []);

alias FeatureContext = Tuple!(
        WriteAndReadFromDartDb, "WriteAndReadFromDartDb",
        FeatureGroup*, "result"
);

@safe @Scenario("write and read from dart db",
        [])
class WriteAndReadFromDartDb {

    DARTServiceHandle handle;
    SecureNet dart_net;
    SecureNet supervisor_net;
    DARTOptions opts;
    ReplicatorOptions replicator_opts;
    Mt19937 gen;
    RandomArchives random_archives;
    Document[] docs;
    RecordFactory.Recorder insert_recorder;
    RecordFactory record_factory;
    HiRPC hirpc;

    struct SimpleDoc {
        ulong n;
        mixin HiBONRecord!(q{
            this(ulong n) {
                this.n = n;
            }
        });
    }

    this(DARTOptions opts, ReplicatorOptions replicator_opts) {

        this.opts = opts;
        this.replicator_opts = replicator_opts;
        dart_net = new StdSecureNet();
        dart_net.generateKeyPair("dartnet very secret");
        supervisor_net = new StdSecureNet();
        supervisor_net.generateKeyPair("supervisor very secret");

        record_factory = RecordFactory(supervisor_net);
        hirpc = HiRPC(supervisor_net);

        gen = Mt19937(1234);

    }

    @Given("I have a dart db")
    Document dartDb() {
        if (opts.dart_filename.exists) {
            opts.dart_filename.remove;
        }

        DART.create(opts.dart_filename, dart_net);
        return result_ok;
    }

    @Given("I have an dart actor with said db")
    Document saidDb() {
        thisActor.task_name = "dart_supervisor";
        register(thisActor.task_name, thisTid);

        import tagion.services.options : TaskNames;

        handle = (() @trusted => spawn!DARTService("DartService", cast(immutable) opts, cast(immutable) replicator_opts, TaskNames(), cast(
                immutable) dart_net))();
        waitforChildren(Ctrl.ALIVE);

        return result_ok;
    }

    @When("I send a dartModify command with a recorder containing changes to add")
    Document toAdd() {

        foreach (i; 0 .. 100) {
            gen.popFront;
            random_archives = RandomArchives(gen.front, 4, 10);
            insert_recorder = record_factory.recorder;
            docs = (() @trusted => cast(Document[]) random_archives.values.map!(a => SimpleDoc(a).toDoc).array)();

            insert_recorder.insert(docs, Archive.Type.ADD);
            auto modify_send = dartModify();
            (() @trusted => handle.send(modify_send, cast(immutable) insert_recorder, immutable int(0)))();

            handle.send(dartBullseyeRR());
            const bullseye_res = receiveOnly!(dartBullseyeRR.Response, Fingerprint);
            check(bullseye_res[1]!is Fingerprint.init, "bullseyes not the same");

            Document bullseye_sender = dartBullseye(hirpc).toDoc;

            handle.send(dartHiRPCRR(), bullseye_sender);
            // writefln("SENDER: %s", bullseye_sender.toPretty);
            auto hirpc_bullseye_res = receiveOnly!(dartHiRPCRR.Response, Document);
            // writefln("RECEIVER %s", hirpc_bullseye_res[1].toPretty);

            auto hirpc_bullseye_receiver = hirpc.receive(hirpc_bullseye_res[1]);
            auto hirpc_message = hirpc_bullseye_receiver.message[Keywords.result].get!Document;
            auto hirpc_bullseye = hirpc_message[DARTFile.Params.bullseye].get!DARTIndex;
            check(bullseye_res[1] == hirpc_bullseye, "hirpc bullseye not the same");

            /// read the archives
            auto fingerprints = docs
                .map!(d => supervisor_net.dartIndex(d))
                .array;

            auto read_request = dartReadRR();
            handle.send(read_request, fingerprints);
            auto read_tuple = receiveOnly!(dartReadRR.Response, immutable(RecordFactory.Recorder));
            auto read_recorder = read_tuple[1];

            check(equal(read_recorder[].map!(a => a.filed), insert_recorder[].map!(a => a.filed)), "Data not the same");

            Document read_sender = dartRead(fingerprints, hirpc).toDoc;

            handle.send(dartHiRPCRR(), read_sender);

            auto read_hirpc = receiveOnly!(dartHiRPCRR.Response, Document);
            auto read_hirpc_recorder = hirpc.receive(read_hirpc[1]);
            auto hirpc_recorder_message = read_hirpc_recorder.message[Keywords.result].get!Document;

            const hirpc_recorder = record_factory.recorder(hirpc_recorder_message);

            check(equal(hirpc_recorder[].map!(a => a.filed), insert_recorder[].map!(a => a.filed)), "hirpc data not the same as insertion");

            Document check_read_sender = dartCheckRead(fingerprints, hirpc).toDoc;
            handle.send(dartHiRPCRR(), check_read_sender);
            auto read_check_tuple = receiveOnly!(dartHiRPCRR.Response, Document);
            auto read_check = hirpc.receive(read_check_tuple[1]);

            auto hirpc_check = read_check.message[Keywords.result].get!Document;
            writefln("hirpc_check %s", hirpc_check.toPretty);
            auto check_fingerprints = (() @trusted => cast(DARTIndex[]) hirpc_check[DARTFile.Params.fingerprints].get!(Buffer))();

            check(check_fingerprints.length == 0, "should be empty");

        }
        auto dummy_indexes = [DARTIndex([1, 2, 3, 4]), DARTIndex([2, 3, 4, 5])];
        Document check_read_sender = dartCheckRead(dummy_indexes, hirpc).toDoc;
        writefln("read_sender %s", check_read_sender.toPretty);
        handle.send(dartHiRPCRR(), check_read_sender);
        auto read_check_tuple = receiveOnly!(dartHiRPCRR.Response, Document);
        auto read_check = hirpc.receive(read_check_tuple[1]);

        auto hirpc_check = read_check.message[Keywords.result].get!Document;
        auto check_fingerprints = (() @trusted => cast(DARTIndex[]) hirpc_check[DARTFile.Params.fingerprints].get!(Buffer))();
        check(equal(check_fingerprints, dummy_indexes), "error in hirpc checkread");

        return result_ok;
    }

    @When("I send a dartRead command to see if it has the changed")
    Document theChanged() @trusted {
        // checked above

        return result_ok;
    }

    @Then("the read recorder should be the same as the dartModify recorder")
    Document dartModifyRecorder() {
        // checked above

        handle.send(Sig.STOP);
        waitforChildren(Ctrl.END);

        return result_ok;
    }

}
