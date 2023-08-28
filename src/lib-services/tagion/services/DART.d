/// Tagion DART actor service
module tagion.services.DART;

import std.path : isValidPath;
import std.format : format;
import std.file;
import std.algorithm : map;
import std.array;
import std.stdio;
import std.path;
import std.exception;

import tagion.utils.pretend_safe_concurrency;
import tagion.utils.JSONCommon;
import tagion.basic.Types : FileExtension;
import tagion.actor;
import tagion.crypto.Types;
import tagion.crypto.SecureInterfaceNet;
import tagion.dart.DART;
import tagion.dart.Recorder;
import tagion.dart.DARTBasic : DARTIndex;
import tagion.hibon.Document;
import tagion.services.messages;

@safe
struct DARTOptions {
    string dart_filename = buildPath(".", "dart".setExtension(FileExtension.dart));
    mixin JSONCommon;
}


@safe
struct DARTService {
    void task(immutable(DARTOptions) opts, immutable(SecureNet) net) {
        DART db;
        Exception dart_exception;
        db = new DART(net, opts.dart_filename);
        if (dart_exception !is null) {
            throw dart_exception;
        }


        scope (exit) {
            db.close();
        }

        void read(dartReadRR req, immutable(DARTIndex)[] fingerprints) {
            RecordFactory.Recorder read_recorder = db.loads(fingerprints);
            req.respond(cast(immutable(RecordFactory.Recorder)) read_recorder);
        }

        // only used from the outside
        void rim(dartRimRR req, DART.Rims rims) {
            // empty  
        }

        void modify(dartModifyRR req, immutable(RecordFactory.Recorder) recorder) {
            immutable eye = DARTIndex(db.modify(recorder));
            req.respond(eye);
        }

        void bullseye(dartBullseyeRR req) {
            immutable eye = DARTIndex(db.bullseye);
            req.respond(eye);
        }

        run(&read, &modify, &bullseye);
        // run(&read, &rim, &modify, &bullseye);

    }
}

alias DARTServiceHandle = ActorHandle!DARTService;
