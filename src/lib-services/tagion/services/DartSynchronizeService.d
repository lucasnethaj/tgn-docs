module tagion.services.DartSynchronizeService;

import core.thread;
import std.concurrency;

import tagion.Options;

import p2plib = p2p.node;
import p2p.connection;
import p2p.callback;
import p2p.cgo.helper;
import tagion.services.LoggerService;
import tagion.Base : Buffer, Control;
import std.getopt;
import std.stdio;
import std.conv;
import tagion.utils.Miscellaneous : toHexString, cutHex;
import tagion.dart.DARTFile;
import tagion.dart.DART;
import tagion.dart.BlockFile : fileId;
import tagion.Base;
import tagion.Keywords;
import tagion.crypto.secp256k1.NativeSecp256k1;
import tagion.dart.DARTSynchronization;

import tagion.hibon.HiBONJSON;
import tagion.hibon.Document;
import tagion.hibon.HiBON : HiBON;
import tagion.gossip.InterfaceNet: SecureNet;
import tagion.communication.HiRPC;

alias HiRPCSender = HiRPC.HiRPCSender;
alias HiRPCReceiver = HiRPC.HiRPCReceiver;

enum DartSynchronizeState{
    WAITING = 1,
    SYNCHRONIZING = 2,
    REPLAYING_JOURNALS = 3,
    REPLAYING_RECORDERS = 4,
    READY = 10,
}


struct ServiceState(T) {
    mixin StateT!T;
    this(T initial){
        _state = initial;
    }
    void setState(T state){
        _state = state;
        notifyOwner(); //TODO: manualy notify?
    }

    @property T state(){
        return _state;
    }

    void notifyOwner(){
        send(ownerTid, _state);
    }
}

void dartSynchronizeServiceTask(Net)(immutable(Options) opts, shared(p2plib.Node) node, shared(SecureNet) master_net, immutable(DART.SectorRange) sector_range) {
    try{
        auto state = ServiceState!DartSynchronizeState(DartSynchronizeState.WAITING);
        setOptions(opts);
        immutable task_name=opts.dart.sync.task_name;
        auto pid = opts.dart.sync.protocol_id;
        log.register(task_name);

        log("-----Start Dart Sync service-----");
        scope(success){
            log("------Stop Dart Sync service-----");
            ownerTid.prioritySend(Control.END);
        }
        scope(failure){
            log("------Error Stop Dart Sync service-----");
            ownerTid.prioritySend(Control.END);
        }
        immutable filename = fileId!(DART)(opts.dart.name).fullpath;
        if (opts.dart.initialize) {
            DARTFile.create_dart(filename);
        }
        log("Dart file created with filename: %s", filename);

        auto net = new Net();
        net.drive(opts.dart.sync.task_name, master_net);


        auto dart = new DART(net, filename, sector_range.from_sector, sector_range.to_sector);
        log("DART initialized with angle from: %s", sector_range);

        if (opts.dart.generate) {
            auto fp = SetInitialDataSet(dart, opts.dart.ringWidth, opts.dart.rings);
            log("DART generated: bullseye: %s", fp.cutHex);
            dart.dump;
        }

        node.listen(pid, &StdHandlerCallback, cast(string) task_name, opts.dart.sync.host.timeout.msecs, cast(uint) opts.dart.sync.host.max_size);
        scope(exit){
            node.closeListener(pid);
        }
        bool stop;
        void handleControl (Control ts) {
            with(Control) switch(ts) {
                case STOP:
                    log("Kill dart synchronize service");
                    stop = true;
                    break;
                default:
                    log.error("Bad Control command %s", ts);
                }
        }
        ownerTid.send(Control.LIVE);
        void recorderReplayFunc(immutable(DARTFile.Recorder) recorder){
            dart.modify(cast(DARTFile.Recorder) recorder);
        }
        auto journalReplayFiber= new ReplayFiber!string((string journal) => dart.replay(journal));
        auto recorderReplayFiber= new ReplayFiber!(immutable(DARTFile.Recorder))(&recorderReplayFunc);

        auto connectionPool = new shared(ConnectionPool!(shared p2plib.Stream, ulong))(opts.dart.sync.host.timeout.msecs);
        auto sync_factory = new P2pSynchronizationFactory(dart, node, connectionPool, opts);
        auto syncPool = new DartSynchronizationPool!(StdHandlerPool!(ResponseHandler, uint))(dart.sectors, journalReplayFiber, opts);
        auto discoveryService = DiscoveryService(node, opts);

        scope(exit){
            discoveryService.stop;
            writeln("exit scope: call stop");
            syncPool.stop;
        }

        discoveryService.start();
        if(opts.dart.synchronize) {
            state.setState(DartSynchronizeState.WAITING);
        }else{
            state.setState(DartSynchronizeState.READY);
        }

        HiRPC hrpc;
        auto empty_hirpc = HiRPC(null);
        hrpc.net = net;
        while(!stop) {
            try{
                const tick_timeout = state.checkState(
                    DartSynchronizeState.REPLAYING_JOURNALS,
                    DartSynchronizeState.REPLAYING_RECORDERS)
                    ? opts.dart.sync.replay_tick_timeout.msecs
                    : opts.dart.sync.tick_timeout.msecs;
                receiveTimeout(tick_timeout,
                    &handleControl,
                    (immutable(DARTFile.Recorder) recorder){
                        log("DSS: recorder received");
                        recorderReplayFiber.insert(recorder);
                    },
                    (Response!(ControlCode.Control_Connected) resp) {
                        log("DSS: Client Connected key: %d", resp.key);
                        connectionPool.add(resp.key, resp.stream, true);
                    },
                    (Response!(ControlCode.Control_Disconnected) resp) {
                        log("DSS: Client Disconnected key: %d", resp.key);
                        connectionPool.close(cast(void*)resp.key);
                    },
                    (Response!(ControlCode.Control_RequestHandled) resp) {
                        // log("DSS: Received request from p2p: %s", resp.key);
                        scope(exit){
                            if(resp.stream !is null){
                                destroy(resp.stream);
                            }
                        }
                        auto doc = Document(resp.data);
                        auto message_doc = doc[Keywords.message].get!Document;
                        void closeConnection(){
                            log("DSS: Forced close connection");
                            connectionPool.close(resp.key);
                        }
                        void serverHandler(){
                            if(message_doc[Keywords.method].get!string == DART.Quries.dartModify){  //Not allowed
                                closeConnection();
                            }
                            auto received = hrpc.receive(doc);
                            auto request = dart(received);
                            auto tosend = hrpc.toHiBON(request).serialize;
                            connectionPool.send(resp.key, tosend);
                            // log("DSS: Sended response to connection: %s", resp.key);
                        }
                        if(message_doc.hasElement(Keywords.method) && state.checkState(DartSynchronizeState.READY)){ //TODO: to switch
                            serverHandler();
                        }else if(!message_doc.hasElement(Keywords.method)&& state.checkState(DartSynchronizeState.SYNCHRONIZING)){
                            syncPool.setResponse(resp);
                        }else{
                            closeConnection();
                        }
                    },
                    (string taskName, Buffer data){
                        log("DSS: Received request from service: %s", taskName);
                        const doc = Document(data);
                        auto receiver = empty_hirpc.receive(doc);
                        auto request = dart(receiver);
                        auto tosend = empty_hirpc.toHiBON(request).serialize;
                        auto tid = locate(taskName);
                        if(tid != Tid.init){
                            send(tid, tosend);
                        }
                    },
                    (immutable(Exception) e) {
                        log.fatal(e.msg);
                        stop=true;
                        ownerTid.send(e);
                    },
                    (immutable(Throwable) t) {
                        log.fatal(t.msg);
                        stop=true;
                        ownerTid.send(t);
                    }
                );

                connectionPool.tick();
                discoveryService.tick();
                if(opts.dart.synchronize){
                    syncPool.tick();
                    if(discoveryService.isReady && syncPool.isReady){
                        sync_factory.setNodeTable(discoveryService.node_addrses);
                        syncPool.start(sync_factory);
                        state.setState(DartSynchronizeState.SYNCHRONIZING);
                    }
                    if(syncPool.isOver){
                        syncPool.stop;
                        log("Start replay journals with: %d journals", journalReplayFiber.count);
                        state.setState(DartSynchronizeState.REPLAYING_JOURNALS);
                    }
                    if(syncPool.isError){
                        sync_factory.setNodeTable(discoveryService.node_addrses);
                        syncPool.start(sync_factory);
                        state.setState(DartSynchronizeState.SYNCHRONIZING); //TODO: remove if notification not needed
                    }
                }
                if(state.checkState(DartSynchronizeState.REPLAYING_JOURNALS)){
                    if(!journalReplayFiber.isOver){
                        journalReplayFiber.call;
                    }else{
                        // log("Start replay recorders with: %d recorders", recorders.length);
                        connectionPool.closeAll();
                        state.setState(DartSynchronizeState.REPLAYING_RECORDERS);
                    }
                }
                if(state.checkState(DartSynchronizeState.REPLAYING_RECORDERS)){
                    if(!recorderReplayFiber.isOver){
                        recorderReplayFiber.call;
                    }else{
                        recorderReplayFiber.reset();
                        dart.dump(true);
                        log("DART generated: bullseye: %s", dart.fingerprint.toHexString);
                        state.setState(DartSynchronizeState.READY);
                    }
                }
            }catch(Exception e){
                log("Iteration exception: %s", e);
            }
            catch(Throwable t) {
                log("Iteration throwable: %s", t);
            }
        }
    }catch(Exception e){
        log("EXCEPTION: %s", e);
    }
    catch(Throwable t) {
        log("THROWABLE: %s", t);
    }
}
