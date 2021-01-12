module tagion.services.TagionService;

import std.concurrency;
import std.exception : assumeUnique;
//import std.stdio;
import std.conv : to;
import std.traits : hasMember;
import core.thread;

import tagion.utils.Miscellaneous: cutHex;
import tagion.hashgraph.Event;
import tagion.hashgraph.HashGraph;
import tagion.basic.ConsensusExceptions;
import tagion.gossip.InterfaceNet;
import tagion.gossip.EmulatorGossipNet;
import tagion.basic.TagionExceptions : fatal, TaskFailure;


import tagion.services.ScriptCallbacks;
import tagion.services.EpochDebugService;
import tagion.crypto.secp256k1.NativeSecp256k1;

import tagion.communication.Monitor;
import tagion.ServiceNames;
import tagion.services.MonitorService;
import tagion.services.TransactionService;
import tagion.services.TranscriptService;
//import tagion.services.ScriptingEngineService;
import tagion.basic.Logger;
//import tagion.basic.TagionExceptions;

import tagion.Options : Options, setOptions, options;
import tagion.basic.Basic : Pubkey, Buffer, Payload, Control;
import tagion.hibon.HiBON : HiBON;
import tagion.hibon.Document : Document;


// If no monitor should be enable set the address to empty or the port below min_port.
// void tagionNode(Net)(uint timeout, immutable uint node_id,
//     immutable uint N,
//     string monitor_ip_address,
//     const ushort monitor_port)  {
void tagionServiceTask(Net)(immutable(Options) args, shared(SecureNet) master_net) {
    Options opts=args;
    opts.node_name=node_task_name(opts);
    log.register(opts.node_name);
    opts.monitor.task_name=monitor_task_name(opts);
    opts.transaction.task_name=transaction_task_name(opts);
    opts.transcript.task_name=transcript_task_name(opts);
    opts.transaction.service.task_name=transervice_task_name(opts);
    setOptions(opts);

    log("task_name=%s options.mode_name=%s", opts.node_task_name, options.node_name);

//    HRPC hrpc;
    import std.datetime.systime;

    auto hashgraph=new HashGraph();
    // Create hash-graph
    Net net;
    net=new Net(hashgraph);
    net.drive("tagion_service", master_net);
    hashgraph.request_net=net;
    // synchronized(master_net) {
    //     auto unshared_net = cast(SecureDriveNet)master_net;
    //     unshared_net.drive("tagion_service", net1);
    // }


    log("\n\n\n\n\n##### Received %s #####", opts.node_name);

    Tid monitor_socket_tid;
    Tid transaction_socket_tid;
//    Tid transcript_tid;

    // scope(failure) {
    //     log.fatal("Unexpected Termination");
    // }

    scope(exit) {
        log("!!!==========!!!!!! Existing %s", opts.node_name);

        if ( net.transcript_tid != net.transcript_tid.init ) {
            log("Send stop to %s", opts.transcript.task_name);
            net.transcript_tid.send(Control.STOP);
            receive(
                (Control ctrl) {
                    if ( ctrl is Control.END ) {
                        log("Closed monitor");
                    }
                    else {
                        log.warning("Unexpected control code %s", ctrl);
                    }

                    // else if ( ctrl is Control.FAIL ) {
                    //     log.error("Closed monitor with failure");
                    // }
                },
                (immutable(TaskFailure) t) {
                    ownerTid.send(t);
                });
            // if ( receiveOnly!Control is Control.END ) {
            //     log("Scripting api end!!");
            // }
        }

        // log("Send stop to the engine");

        // if ( Event.scriptcallbacks ) {
        //     if ( Event.scriptcallbacks.stop && (receiveOnly!Control == Control.END) ) {
        //         log("Scripting engine end!!");
        //     }
        // }

        if ( net.callbacks ) {
            net.callbacks.exiting(hashgraph.getNode(net.pubkey));
        }


        // version(none)
        if ( transaction_socket_tid != transaction_socket_tid.init ) {
            log("send stop to %s", opts.transaction.task_name);

            transaction_socket_tid.send(Control.STOP);
            //writefln("Send stop %s", opts.transaction.task_name);
            // auto control=receiveOnly!Control;
            // log("Control %s", control);
            receive(
                (Control ctrl) {
                    if ( ctrl is Control.END ) {
                        log("Closed monitor");
                    }
                    else {
                        log.warning("Unexpected control code %s", ctrl);
                    }

                    // else if ( ctrl is Control.FAIL ) {
                    //     log.error("Closed monitor with failure");
                    // }
                },
                (immutable(TaskFailure) t) {
                    ownerTid.send(t);
                });
            // if ( control is Control.END ) {
            //     log("Closed transaction");
            // }
            // else if ( control is Control.FAIL ) {
            //     log.error("Closed transaction with failure");
            // }
        }

        if ( monitor_socket_tid != monitor_socket_tid.init ) {
            log("send stop to %s", opts.monitor.task_name);
//            try {
            monitor_socket_tid.send(Control.STOP);

            receive(
                (Control ctrl) {
                    if ( ctrl is Control.END ) {
                        log("Closed monitor");
                    }
                    else {
                        log.warning("Unexpected control code %s", ctrl);
                    }
                    // else if ( ctrl is Control.FAIL ) {
                    //     log.error("Closed monitor with failure");
                    // }
                },
                (immutable(TaskFailure) t) {
                    ownerTid.send(t);
                });
        }


        log("End");
        ownerTid.send(Control.END);
    }


    // Pseudo passpharse
    // immutable passphrase=opts.node_name;
    // net.generateKeyPair(passphrase);

    ownerTid.send(net.pubkey);

    Pubkey[] received_pkeys;
    foreach(i;0..opts.nodes) {
        received_pkeys~=receiveOnly!(Pubkey);
        log("@@@@ Receive %s %s", opts.node_name, received_pkeys[i].cutHex);
    }
    immutable pkeys=assumeUnique(received_pkeys);

    hashgraph.createNode(net.pubkey);
    log("Ownkey %s num=%d", net.pubkey.cutHex, pkeys.length);
//    stderr.writefln("@@@@ Ownkey %s num=%d", net.pubkey.cutHex, pkeys.length);
    foreach(i, p; pkeys) {
        if ( hashgraph.createNode(p) ) {
            log("%d] %s", i, p.cutHex);
        }
    }

    // scope tids=new Tid[N];
    // getTids(tids);
    net.set(pkeys);
    if ( ((opts.node_id < opts.monitor.max) || (opts.monitor.max == 0) ) &&
        (opts.monitor.port >= opts.min_port) ) {
        monitor_socket_tid = spawn(&monitorServiceTask, opts);
        Event.callbacks = new MonitorCallBacks(monitor_socket_tid, opts.node_id, net.globalNodeId(net.pubkey), opts.monitor.dataformat);
        log("@@@@ Wait for monitor %s", opts.node_name,);

        if ( receiveOnly!Control is Control.LIVE ) {
            log("Monitor started");
        }
    }

    log("@@@@ opts.transaction.port=%d", opts.transaction.service.port);
    // version(none)
    if ( ( (opts.node_id < opts.transaction.max) || (opts.transaction.max == 0) ) &&
        (opts.transaction.service.port >= opts.min_port) ) {
        transaction_socket_tid = spawn(&transactionServiceTask, opts);
        //stderr.writefln("@@@@ Wait for transaction %s", opts.node_name);
        log("@@@@ Wait for transaction %s", opts.node_name);
        if ( receiveOnly!Control is Control.LIVE ) {
            log("Transaction started port %d", opts.transaction.service.port);
        }
        log("@@@@ after %s", opts.node_name);
    }

    // All tasks is in sync
    //stderr.writefln("@@@@ All tasks are in sync %s", opts.node_name);
    log("All tasks are in sync %s", opts.node_name);

    //Event.scriptcallbacks=new ScriptCallbacks(thisTid);

//    version(none)
    //  if ( opts.transcript.enable ) {6dZDv7NC

    //version(none) {
//    Tid transcript_tid=spawn(&transcriptServiceTask, opts);
    string epoch_debug_task_name;
    if (opts.transcript.epoch_debug) {
        import std.array : join;
        epoch_debug_task_name=["epoch", opts.transcript.task_name].join("_");
        spawn(&epochDebugServiceTask, epoch_debug_task_name);
    }
    scope(exit) {
        auto tid = locate(epoch_debug_task_name);
        if (tid != tid.init) {
            tid.send(Control.STOP);
            if (receiveOnly!Control != Control.END) {
                log("Epoch Debug ended");
            }
        }
    }

    Event.scriptcallbacks=new ScriptCallbacks(&transcriptServiceTask, opts.transcript.task_name, opts.dart.task_name);
    scope(exit) {
        Event.scriptcallbacks.stop;
    }


    // if ( receiveOnly!Control is Control.LIVE ) {
    //     log("Transcript started");
    // }


    enum max_gossip=1;
    uint gossip_count=max_gossip;
    bool stop=false;
    // // True of the network has been initialized;
    // bool initialised=false;
    enum timeout_end=10;
    uint timeout_count;
//    Event mother;
    Event event;
    auto own_node=hashgraph.getNode(net.pubkey);
    log("Wait for some delay %s", opts.node_name);
//    Thread.sleep(2.seconds);

    auto net_random=cast(Net)net;
    enum bool has_random_seed=__traits(compiles, net_random.random.seed(0));
//    pragma(msg, has_random_seed);
    static if ( has_random_seed ) {
//        pragma(msg, "Random seed works");
        if ( !opts.sequential ) {
            net_random.random.seed(cast(uint)(Clock.currTime.toUnixTime!int));
        }
    }

    //
    // Start Script API task
    //

    Payload empty_payload;

    // Set thread global options


//    log("opts.sequential=%s", opts.sequential);
//        stdout.flush;
    immutable(ubyte)[] data;
    void receive_buffer(const(Document) doc) {
        timeout_count=0;
        net.time=net.time+100;
        log("\n*\n*\n*\n******* receive %s [%s] %s", opts.node_name, opts.node_id, doc.data.length);
//        auto own_node=hashgraph.getNode(net.pubkey);

        // version(none)
        // Event register_leading_event(Buffer father_fingerprint) @safe {
        //     auto mother=own_node.event;
        //     immutable ebody=immutable(EventBody)(empty_payload, mother.fingerprint,
        //         father_fingerprint, net.time, mother.altitude+1);
        //     //const pack=net.buildPackage(ebody.toHiBON, ExchangeState.NONE);
        //     // immutable signature=net.sign(ebody);
        //     return hashgraph.registerEvent(net.pubkey, pack.signature, ebody);
        // }
        net.receive(doc); //, &register_leading_event);
    }

    void next_mother(Payload payload) {
        auto own_node=hashgraph.getNode(net.pubkey);
        if ( (gossip_count >= max_gossip) || (payload.length) ) {
            // fout.writeln("After build wave front");
            if ( own_node.event is null ) {
                immutable ebody=EventBody.eva(net);
                immutable epack=new immutable(EventPackage)(net, ebody);
                event=hashgraph.registerEvent(epack);
            }
            else {
                auto mother=own_node.event;
                immutable mother_hash=mother.fingerprint;
                immutable ebody=immutable(EventBody)(payload, mother_hash, null, net.time, mother.altitude+1);
                immutable epack=new immutable(EventPackage)(net, ebody);
                event=hashgraph.registerEvent(epack);
            }
            immutable send_channel=net.selectRandomNode;
            auto send_node=hashgraph.getNode(send_channel);
            if ( send_node.state is ExchangeState.NONE ) {
                send_node.state = ExchangeState.INIT_TIDE;
                auto tidewave   = new HiBON;
                auto tides      = net.tideWave(tidewave, net.callbacks !is null);
                const pack_doc  = net.buildPackage(tidewave, ExchangeState.TIDAL_WAVE);

                net.send(send_channel, pack_doc);
                if ( net.callbacks ) {
                    net.callbacks.sent_tidewave(send_channel, tides);
                }
            }
            gossip_count=0;
        }
        else {
            gossip_count++;
        }
    }

    void receive_payload(Payload pload) {
        log("payload.length=%d", pload.length);
        next_mother(pload);
    }

    void controller(Control ctrl) {
        with(Control) switch(ctrl) {
            case STOP:
                stop=true;
                log("##### Stop %s", opts.node_name);
                break;
            default:
                log.error("Unsupported control %s", ctrl);
            }
    }

//     void tagionexception(immutable(TagionException) e) {
//         ownerTid.send(e);
//     }

//     void exception(immutable(Exception) e) {
//         ownerTid.send(e);
//     }

//     void error(immutable(Error) t) {
// //        log(t);
//         log.fatal("-->%s", t);
//         ownerTid.send(t);
//         stop=true;
//     }

    void _taskfailure(immutable(TaskFailure) t) {
        ownerTid.send(t);
        if (cast(Error)(t.throwable) is null) {
            stop=true;
        }
    }

    static if (has_random_seed) {
        void sequential(uint time, uint random)
            in {
                assert(opts.sequential);
            }
        do {

            immutable(ubyte[]) payload;
            net_random.random.seed(random);
            net_random.time=time;
            next_mother(empty_payload);
        }
    }

    log("SEQUENTIAL=%s", opts.sequential);
    ownerTid.send(Control.LIVE);
    try {
        while(!stop) {
            if ( opts.sequential ) {
                immutable message_received=receiveTimeout(
                    opts.timeout.msecs,
                    &receive_payload,
                    &controller,
                    &sequential,
                    &receive_buffer,
                    // &tagionexception,
                    // &exception,
                    // &error,
                    &_taskfailure,

                    );
                if ( !message_received ) {
                    log("TIME OUT");
                    timeout_count++;
                    if ( !net.queue.empty ) {
                        receive_buffer(net.queue.read);
                    }
                }
            }
            else {
                immutable message_received=receiveTimeout(
                    opts.timeout.msecs,
                    &receive_payload,
                    &controller,
                    // &sequential,
                    &receive_buffer,
                    // &tagionexception,
                    // &exception,
                    &_taskfailure,
                    );
                if ( !message_received ) {
                    log("TIME OUT");
                    timeout_count++;
                    net.time=Clock.currTime.toUnixTime!long;
                    if ( !net.queue.empty ) {
                        receive_buffer(net.queue.read);
                    }
                    next_mother(empty_payload);
                }
            }
        }
    }
    catch (Throwable t) {
        fatal(t);
        // log.error(e.toString);
        // log.fatal("Unexpected Termination");
        // ownerTid.send(e.taskException);
//        error(cast(immutable)e.taskException);
    }
}
