module tagion.services.HeartBeatService;

import core.thread;
import std.concurrency;

import tagion.Options;

//import tagion.services.ServiceNames;

//import tagion.services.LoggerService;
import tagion.utils.Random;

import tagion.Base : Pubkey, Control;
import tagion.services.LoggerService;
import tagion.services.TagionService;
import tagion.gossip.EmulatorGossipNet;

import std.stdio;
void heartBeatServiceTask(immutable(Options) opts) {
    setOptions(opts);

    immutable tast_name="heatbeat";


    Tid[] tids;
    Pubkey[]  pkeys;

    Control response;
    auto logger_tid=spawn(&loggerTask, opts);
    import std.stdio : stderr;
    stderr.writeln("Waiting for logger");

    response=receiveOnly!Control;
    stderr.writeln("Logger started");
    if ( response !is Control.LIVE ) {
        stderr.writeln("ERROR:Logger %s", response);
    }

    log.register(tast_name);
    scope(exit) {
        log("----- Stop all tasks -----");
        foreach(i, ref tid; tids) {
            log("Send stop to %d", i);
            tid.prioritySend(Control.STOP);
        }
        log("----- Wait for all tasks -----");
        foreach(i, ref tid; tids) {
            auto control=receiveOnly!Control;
            if ( control == Control.END ) {
                log("Thread %d stopped %d", i, control);
            }
            else {
                log("Thread %d stopped %d unexpected control %s", i, control);
            }
        }
        log("----- Stop send to all -----");

        log.close;
    }

    foreach(i;0..opts.nodes) {
        writefln("node=%s", i);
        Options service_options=opts;
        if ( (!opts.monitor.disable) && ((opts.monitor.max == 0) || (i < opts.monitor.max) ) ) {
            service_options.monitor.port=cast(ushort)(opts.monitor.port + i);
        }
        if ( (!opts.transaction.disable) && ((opts.transaction.max == 0) || (i < opts.transaction.max) ) ) {
            service_options.transaction.port=cast(ushort)(opts.transaction.port + i);
        }
        service_options.node_id=cast(uint)i;
        service_options.node_name=node_task_name(service_options);
        immutable(Options) tagion_service_options=service_options;
        auto tid=spawn(&(tagionServiceTask!EmulatorGossipNet), tagion_service_options);
        tids~=tid;
        pkeys~=receiveOnly!(Pubkey);
        log("Start %d", pkeys.length);
    }

    log("----- Receive sync signal from nodes -----");

    log("----- Send acknowlege signals  num of keys=%d -----", pkeys.length);

    foreach(ref tid; tids) {
        foreach(pkey; pkeys) {
            tid.send(pkey);
        }
    }

    uint count = opts.loops;

    bool stop=false;

    if ( opts.sequential ) {
        Thread.sleep(1.seconds);


        log("Start the heart beat");
        uint node_id;
        uint time=opts.delay;
        Random!uint rand;
        rand.seed(opts.seed);
        while(!stop) {
            if ( !opts.infinity ) {
                log("count=%d", count);
            }
            Thread.sleep(opts.delay.msecs);

            tids[node_id].send(time, rand.value);
            if ( !opts.infinity ) {
                log("send time=%d to  %d", time, node_id);
            }

            time+=opts.delay;
            node_id++;
            if ( node_id >= tids.length ) {
                node_id=0;
            }

            if ( !opts.infinity ) {
                stop=(count==0);
                count--;
            }
        }
    }
    else {
        while(!stop) {
            if ( !opts.infinity ) {
                log("count=%d", count);
            }
            Thread.sleep(opts.delay.msecs);
            if ( !opts.infinity ) {
                stop=(count==0);
                count--;
            }
        }
    }
}
