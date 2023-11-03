module tagion.services.DARTInterface;

import tagion.utils.JSONCommon;

@safe
struct DARTInterfaceOptions {
    import tagion.services.options : contract_sock_addr;
    string sock_addr;
    string dart_prefix = "DART_";
    int sendtimeout = 5000;
    uint pool_size = 4;
    uint sendbuf = 4096;

    void setDefault() nothrow {
        sock_addr = contract_sock_addr(dart_prefix);
    }

    void setPrefix(string prefix) nothrow {
        sock_addr = contract_sock_addr(prefix ~ dart_prefix);
    }

    mixin JSONCommon;

}

import tagion.actor;
import tagion.utils.pretend_safe_concurrency;
import tagion.logger.Logger;
import tagion.services.messages;
import tagion.hibon.Document;
import tagion.hibon.HiBONRecord : isRecord;
import tagion.services.options;
import nngd;

import std.format;
import core.time;


struct DartWorkerContext {
    string dart_task_name;
    int dart_worker_timeout;
}

void dartHiRPCCallback(NNGMessage* msg, void* ctx) nothrow @trusted {
    // log.register(thisActor.task_name);
    import std.stdio;
    import std.exception;



    try {
        thisActor.task_name = format("%s", thisTid);
    
        auto cnt = cast(DartWorkerContext*) ctx;

        import tagion.hibon.HiBONJSON : toPretty;
        import tagion.communication.HiRPC;

        if (msg.length == 0) {
            writeln("received empty msg");
            return;
        }

        Document doc = msg.body_trim!(immutable(ubyte[]))(msg.length);
        msg.clear();

        if (!doc.isInorder || !doc.isRecord!(HiRPC.Sender)) {
            log("Non-valid request received");
            return;
        }
        writefln("Kernel got: %s", doc.toPretty);
        locate(cnt.dart_task_name).send(dartHiRPCRR(), doc);

        void dartHiRPCResponse(dartHiRPCRR.Response res, Document doc) {
            msg.body_append(doc.serialize);
        }

        auto dart_resp = receiveTimeout(cnt.dart_worker_timeout.msecs, &dartHiRPCResponse);
        if (!dart_resp) {
            writefln("Non-valid request received");
            return;
            // send a error;
        }
    }
    catch(Exception e) {
        assumeWontThrow(writeln(e));
    }
}

@safe
struct DARTInterfaceService {
    immutable(DARTInterfaceOptions) opts;
    immutable(TaskNames) task_names;

    void task() @trusted {

        void checkSocketError(int rc) {
            if (rc != 0) {
                import std.format;

                throw new Exception(format("Failed to dial %s", nng_errstr(rc)));
            }

        }

        DartWorkerContext ctx;
        ctx.dart_task_name = task_names.dart;
        ctx.dart_worker_timeout = opts.sendtimeout;

        NNGSocket sock = NNGSocket(nng_socket_type.NNG_SOCKET_REP);
        sock.sendtimeout = opts.sendtimeout.msecs;
        sock.recvtimeout = 1000.msecs;
        sock.sendbuf = opts.sendbuf;

        NNGPool pool = NNGPool(&sock, &dartHiRPCCallback, opts.pool_size, &ctx);
        scope (exit) {
            pool.shutdown();
        }
        pool.init();
        auto rc = sock.listen(opts.sock_addr);
        checkSocketError(rc);

        setState(Ctrl.ALIVE);

        while (!thisActor.stop) {
            const received = receiveTimeout(
                    Duration.zero,
                    &signal,
                    &ownerTerminated,
                    &unknown
            );
            if (received) {
                continue;
            }
            // Document doc = sock.receive!Document;

        }

    }

}

alias DARTInterfaceServiceHandle = ActorHandle!DARTInterfaceService;
