/// Tagion DART actor service
module tagion.services.DART;

import std.algorithm : map, filter;
import std.array;
import std.exception;
import std.file;
import std.format : format;
import std.path : isValidPath;
import std.path;
import std.stdio;
import tagion.actor;
import tagion.basic.Types : FileExtension;
import tagion.communication.HiRPC;
import tagion.crypto.SecureInterfaceNet;
import tagion.crypto.SecureNet;
import tagion.crypto.Types;
import tagion.dart.DART;
import tagion.dart.DARTBasic : DARTIndex, dartIndex;
import tagion.dart.DARTException;
import tagion.dart.Recorder;
import tagion.hibon.Document;
import tagion.hibon.HiBONRecord : isRecord;
import tagion.logger.Logger;
import tagion.services.messages;
import tagion.services.options : TaskNames;
import tagion.services.replicator;
import tagion.utils.JSONCommon;
import tagion.utils.pretend_safe_concurrency;

@safe
struct DARTOptions {
    string folder_path = buildPath(".");
    string dart_filename = "dart".setExtension(FileExtension.dart);
    string dart_path;

    this(string folder_path, string dart_filename) {
        this.folder_path = folder_path;
        this.dart_filename = dart_filename;
        dart_path = buildPath(folder_path, dart_filename);
    }

    void setPrefix(string prefix) nothrow {
        dart_filename = prefix ~ dart_filename;
        dart_path = buildPath(folder_path, dart_filename);
    }

    mixin JSONCommon;
}

@safe
struct DARTService {
    void task(immutable(DARTOptions) opts,
            immutable(TaskNames) task_names,
            shared(StdSecureNet) shared_net) {

        DART db;
        Exception dart_exception;

        const net = new StdSecureNet(shared_net);

        db = new DART(net, opts.dart_path);
        if (dart_exception !is null) {
            throw dart_exception;
        }

        scope (exit) {
            db.close();
        }

        void read(dartReadRR req, immutable(DARTIndex)[] fingerprints) @safe {
            import std.algorithm;
            import tagion.hibon.HiBONtoText;
            import tagion.utils.Miscellaneous;

            RecordFactory.Recorder read_recorder = db.loads(fingerprints);
            req.respond(RecordFactory.uniqueRecorder(read_recorder));
        }

        void checkRead(dartCheckReadRR req, immutable(DARTIndex)[] fingerprints) @safe {
            import tagion.utils.Miscellaneous : toHexString;

            // log("Received checkread response %s", fingerprints.map!(f => f.toHexString));

            immutable(DARTIndex)[] check_read = (() @trusted => cast(immutable) db.checkload(fingerprints))();
            log("after checkread response");

            req.respond(check_read);
        }

        import tagion.utils.Miscellaneous : toHexString;

        log("Starting dart with %s", db.bullseye.toHexString);

        auto hirpc = HiRPC(net);
        import tagion.Keywords;

        void dartHiRPC(dartHiRPCRR req, Document doc) {
            import tagion.hibon.HiBONJSON;

            log("Received HiRPC request");

            if (!doc.isRecord!(HiRPC.Sender)) {
                import tagion.hibon.HiBONJSON;

                log("wrong request sent to dartservice. Expected HiRPC.Sender got %s", doc.toPretty);
                return;
            }

            immutable receiver = hirpc.receive(doc);

            if (receiver.method.name == "search") {
                log("SEARCH REQUEST");
                // log("%s", receiver.method.params.toPretty);

                import tagion.basic.Types;

                auto owner_doc = receiver.method.params;
                Buffer[] owner_pkeys;
                foreach (owner; owner_doc[]) {
                    owner_pkeys ~= owner.get!Buffer;
                }
                auto res = db.search(owner_pkeys, net);

                Document response = hirpc.result(receiver, Document(res)).toDoc;
                req.respond(response);
                return;
            }
            if (!(receiver.method.name == DART.Queries.dartRead || receiver.method.name == DART.Queries.dartBullseye || receiver
                    .method.name == DART.Queries.dartCheckRead)) {
                log("unsupported request");
                return;
            }

            Document result = db(receiver, false).toDoc;
            log("darthirpc response: %s", result.toPretty);
            req.respond(result);
        }

        void modify(dartModifyRR req, immutable(RecordFactory.Recorder) recorder, immutable(long) epoch_number) @trusted {

            log("Received modify request with length=%s", recorder.length);

            immutable fingerprint_before = Fingerprint(db.bullseye);
            import core.exception : AssertError;

            try {

                auto eye = db.modify(recorder);
                log("New bullseye is %s", eye.toHexString);

                req.respond(eye);
                auto replicator_tid = locate(task_names.replicator);
                if (replicator_tid !is Tid.init) {
                    replicator_tid.send(SendRecorder(), recorder, eye, epoch_number);
                }
            }
            catch (AssertError e) {
                log("Received ASSERT ERROR bullseye before %(%02x%), %s archives that were tried to be added \n%s", fingerprint_before, e, recorder
                        .toPretty);
                fail(e);
            }
            catch (Error e) {
                log("DART Error %s", e);
            }

        }

        void bullseye(dartBullseyeRR req) @safe {
            auto eye = Fingerprint(db.bullseye);
            req.respond(eye);
        }

        run(&read, &checkRead, &modify, &bullseye, &dartHiRPC);

    }
}
