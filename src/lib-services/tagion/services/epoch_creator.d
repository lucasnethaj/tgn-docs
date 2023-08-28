// Service for creating epochs
/// [Documentation](https://docs.tagion.org/#/documents/architecture/EpochCreator)
module tagion.services.epoch_creator;

// tagion
import tagion.logger.Logger;
import tagion.actor;
import tagion.communication.HiRPC;
import tagion.hibon.Document;
import tagion.utils.JSONCommon;
import tagion.hashgraph.HashGraph;
import tagion.gossip.GossipNet;
import tagion.crypto.SecureNet : StdSecureNet;
import tagion.crypto.SecureInterfaceNet : SecureNet;
import tagion.crypto.Types : Pubkey;
import tagion.basic.Types : Buffer;
import tagion.hashgraph.Refinement;
import tagion.gossip.InterfaceNet : GossipNet;
import tagion.gossip.EmulatorGossipNet;
import tagion.utils.Queue;
import tagion.utils.Random;
import tagion.utils.pretend_safe_concurrency;
import tagion.utils.Miscellaneous : cutHex;
import tagion.gossip.AddressBook;

// core
import core.time;

// std
import std.algorithm;
import std.typecons : No;
import std.stdio;

// alias ContractSignedConsensus = Msg!"ContractSignedConsensus";
alias payload = Msg!"Payload";
alias ReceivedWavefront = Msg!"ReceivedWavefront";
alias AddedChannels = Msg!"AddedChannels";
alias PayloadQueue = Queue!Document;


enum NetworkMode {
    internal,
    local,
    pub
}

@safe
struct EpochCreatorOptions {

    uint timeout; // timeout between nodes in milliseconds;
    size_t nodes;
    uint scrap_depth;
    string task_name = "epoch_creator";
    mixin JSONCommon;
}

@safe
struct EpochCreatorService {

    void task(immutable(EpochCreatorOptions) opts, immutable(SecureNet) net) {

        // writeln("IN TASK");
        // const hirpc = HiRPC(net);

        // GossipNet gossip_net;
        // gossip_net = new NewEmulatorGossipNet(net.pubkey, opts.timeout.msecs);

        Pubkey[] channels = addressbook.activeNodeChannels;
        /*
        foreach (i; 0 .. opts.nodes) {
            log.trace("Waiting for Receive %d", i);
            // writeln("before receive");
            pkeys ~= receiveOnly!(Pubkey);
            // pkeys ~= p;
            // receive((Pubkey p) {pkeys ~= p;});
            log.trace("Receive %d %s", i, pkeys[i].cutHex);
        }

        // foreach(p; pkeys) {
        //     gossip_net.add_channel(p);
        // }
        ownerTid.send(AddedChannels());

        receiveOnly!(Msg!"BEGIN");
        log.trace("After begin");
    */
        // auto refinement = new StdRefinement;

        // HashGraph hashgraph = new HashGraph(opts.nodes, net, refinement, &gossip_net.isValidChannel, No.joining);
        // hashgraph.scrap_depth = opts.scrap_depth;

        // PayloadQueue payload_queue = new PayloadQueue();
        // writeln("before eva");
        // {
        //     immutable buf = cast(Buffer) hashgraph.channel;
        //     const nonce = cast(Buffer) net.calcHash(buf);
        //     auto eva_event = hashgraph.createEvaEvent(gossip_net.time, nonce);
        // }

        // const(Document) payload() {
        //     if (!hashgraph.active || payload_queue.empty) {
        //         return Document();
        //     }
        //     return payload_queue.read;
        // }

        // void receivePayload(Payload, Document pload) {
        //     log.trace("Received Payload");
        //     payload_queue.write(pload);
        // }

        // void receiveWavefront(ReceivedWavefront, const(Document) wave_doc) {
        //     log.trace("Received wavefront");
        //     const receiver = HiRPC.Receiver(wave_doc);
        //     hashgraph.wavefront(
        //             receiver,
        //             gossip_net.time,
        //             (const(HiRPC.Sender) return_wavefront) { gossip_net.send(receiver.pubkey, return_wavefront); },
        //             &payload);
        // }

        // Random!size_t random;
        // random.seed(123456789);
        // void timeout() {
        //     writefln("%s areweingraph: %s", net.pubkey.cutHex, hashgraph.areWeInGraph);

        //     const init_tide = random.value(0, 3) is 1;
        //     if (!init_tide) {
        //         return;
        //     }
        //     hashgraph.init_tide(&gossip_net.gossip, &payload, gossip_net.time);
        // }

        void receivePayload(payload, Document payload) {
        }

        void timeout() {
            log.trace("TEST %s", channels.map!(p => p.cutHex));
        }

        // runTimeout(100.msecs, &timeout, &receivePayload, &receiveWavefront);
        runTimeout(100.msecs, &timeout, &receivePayload);

    }

}
