module tagion.gossip.GossipNet;

import std.concurrency;
import std.stdio : File;
import std.format;

import tagion.Options;
import tagion.Base : EnumText, convertEnum, consensusCheck, consensusCheckArguments, Pubkey, Buffer, buf_idup;
import tagion.utils.Miscellaneous: cutHex;
import tagion.utils.BSON : HBSON, Document;
import tagion.utils.LRU;
import tagion.utils.Queue;

import tagion.gossip.InterfaceNet;
import tagion.hashgraph.HashGraph;
import tagion.hashgraph.Event;
import tagion.hashgraph.ConsensusExceptions;


import tagion.crypto.aes.AESCrypto;
import tagion.crypto.secp256k1.NativeSecp256k1;

@safe
class StdRequestNet : RequestNet {

    Buffer calcHash(const(ubyte[]) data) const {
        import std.digest.sha : SHA256;
        import std.digest.digest;
        return digest!SHA256(data).idup;
    }

    //TO-DO: Implement a general request func. if makes sense.
    abstract void request(HashGraph hashgraph, immutable(ubyte[]) fingerprint);
}


alias ReceiveQueue = Queue!(immutable(ubyte[]));
alias check=consensusCheck!(GossipConsensusException);
alias consensus=consensusCheckArguments!(GossipConsensusException);

@safe
class StdSecureNet : StdRequestNet, SecureNet {
    // The Eva value is set up a low negative number
    // to check the two-complement round wrapping if the altitude.
    enum AES_KEY_LENGTH=128;

    import tagion.crypto.secp256k1.NativeSecp256k1;
    import std.digest.hmac;

    private Pubkey _pubkey;
    private immutable(ubyte[]) delegate(immutable(ubyte[]) message) @safe _sign;

    Pubkey pubkey() pure const nothrow {
        return _pubkey;
    }

    Buffer hashPubkey() const {
        return calcHash(cast(Buffer)_pubkey);
    }

    bool verify(T)(T pack, immutable(ubyte)[] signature, Pubkey pubkey) if ( __traits(compiles, pack.serialize) ) {
        auto message=calcHash(pack.serialize);
        return verify(message, signature, pubkey);
    }

    private NativeSecp256k1 _crypt;
    bool verify(immutable(ubyte[]) message, immutable(ubyte)[] signature, Pubkey pubkey) {

        if ( signature.length == 0 && signature.length <= 520) {
            consensusCheck!SecurityConsensusException(0, ConsensusFailCode.SECURITY_SIGNATURE_SIZE_FAULT);
        }
        return _crypt.verify(message, signature, cast(Buffer)pubkey);
    }

    immutable(ubyte[]) sign(T)(T pack) if ( __traits(compiles, pack.serialize) ) {
        auto message=calcHash(pack.serialize);
        auto result=sign(message);
        return result;
    }

    immutable(ubyte[]) sign(immutable(ubyte[]) message)
    in {
        assert(_sign !is null, format("Signature function has not been intialized. Use the %s function", basename!generatePrivKey));
        assert(message.length == 32);
    }
    do {
        return _sign(message);
    }

    void generateKeyPair(string passphrase)
        in {
            assert(_sign is null);
        }
    do {
        import std.digest.sha : SHA256;
        import std.string : representation;
        alias AES=AESCrypto!256;

        auto hmac = HMAC!SHA256(passphrase.representation);
        auto data=hmac.finish.dup;

        // Generate Key pair
        do {
            data=hmac.put(data).finish.dup;
        } while (!_crypt.secKeyVerify(data));

        _pubkey=_crypt.computePubkey(data);
        // Generate scramble key for the private key
        import std.random;

        void scramble(ref ubyte[] data, ubyte[] xor=null) @safe {
            import std.random;
            // enum from =ubyte.min;
            // enum to   =ubyte.max;
            auto gen1 = Mt19937(unpredictableSeed); //Random(unpredictableSeed);
            foreach(ref s; data) {
                s=gen1.front & ubyte.max; //cast(ubyte)uniform!("[]")(from, to, gen1);
            }
            foreach(i, ref s; xor) {
                s^=data[i];
            }
        }
        auto seed=new ubyte[32];

        scramble(seed);
        // CBR: Note AES need to be change to beable to handle const keys
        auto aes_key=calcHash(seed).dup;

        scramble(seed);

        // Encrypt private key
        auto encrypted_privkey=new ubyte[data.length];
        AES.encrypt(aes_key, data, encrypted_privkey);

        AES.encrypt(calcHash(seed), encrypted_privkey, data);
        scramble(seed);

        AES.encrypt(aes_key, encrypted_privkey, data);

        AES.encrypt(aes_key, data, seed);

        AES.encrypt(aes_key, encrypted_privkey, data);

        immutable(ubyte[]) local_sign(immutable(ubyte[]) message) @safe {
            // CBR:
            // Yes I know it is security by obscurity
            // But just don't want to have the private in clear text in memory
            // for long period of time
            auto privkey=new ubyte[encrypted_privkey.length];
            scope(exit) {
                auto seed=new ubyte[32];
                scramble(seed, aes_key);
                AES.encrypt(aes_key, privkey, encrypted_privkey);
                AES.encrypt(calcHash(seed), encrypted_privkey, privkey);
            }
            AES.decrypt(aes_key, encrypted_privkey, privkey);
            immutable(ubyte[]) result() @trusted {
                return _crypt.sign(message, privkey);
            }
            return result();
        }

        _sign=&local_sign;
    }

    this(NativeSecp256k1 crypt) {
        this._crypt = crypt;
    }
}

@safe
abstract class StdGossipNet : StdSecureNet, ScriptNet { //GossipNet {
    static File fout;
    static private shared uint _next_global_id;
    static private shared uint[immutable(Pubkey)] _node_id_pair;

    uint globalNodeId(immutable(Pubkey) channel) {
        if ( channel in _node_id_pair ) {
            return _node_id_pair[channel];
        }
        else {
            return setGlobalNodeId(channel);
        }
    }

    @trusted
    static private uint setGlobalNodeId(immutable(Pubkey) channel) {
        import core.atomic;
        auto result = _next_global_id;
        _node_id_pair[channel] = _next_global_id;
        atomicOp!"+="(_next_global_id, 1);
        return result;
    }

    import tagion.hashgraph.Event : Event;
    this(NativeSecp256k1 crypt, HashGraph hashgraph) {
//        _transceiver=transceiver;
        _hashgraph=hashgraph;
        _queue=new ReceiveQueue;
        _event_package_cache=new EventPackageCache(&onEvict);
//        import tagion.crypto.secp256k1.NativeSecp256k1;
        super(crypt);
    }

    protected enum _params = [
        "type",
        "tidewave",
        "wavefront",
        "block"
        ];

    mixin(EnumText!("Params", _params));

    protected enum _gossip = [
        "waveFront",
        "tideWave",
        ];

    mixin(EnumText!("Gossips", _gossip));

    override NetCallbacks callbacks() {
        return (cast(NetCallbacks)Event.callbacks);
        // return Event.callbacks;
    }

    static struct Init {
        uint timeout;
        uint node_id;
        uint N;
        string monitor_ip_address;
        ushort monitor_port;
        uint seed;
        string node_name;
    }

    const(Package) buildEvent(const(HBSON) block, ExchangeState type) {
        return Package(this, block, type);
    }

    void onEvict(const(ubyte[]) key, EventPackageCache.Element* e) @safe {
        //fout.writefln("Evict %s", typeid(e.entry));
    }

    bool online() const  {
        // Does my own node exist and do the node have an event
        auto own_node=_hashgraph.getNode(pubkey);
        return (own_node !is null) && (own_node.event !is null);
        // return _hashgraph.isNodeActive(0) && (_hashgraph.getNode(0).isOnline);
    }

    private ReceiveQueue _queue;
    @property
    ReceiveQueue queue() {
        return _queue;
    }

    alias EventPackageCache=LRU!(const(ubyte[]), EventPackage);
    protected  EventPackageCache _event_package_cache;

    protected ulong _current_time;
    protected HashGraph _hashgraph;

    override void request(HashGraph hashgraph, immutable(ubyte[]) fingerprint) {
        if ( !_hashgraph.isRegistered(fingerprint) ) {
            immutable has_new_event=(fingerprint !is null);
            if ( has_new_event ) {
                EventPackage epack=_event_package_cache[fingerprint];
                _event_package_cache.remove(fingerprint);
                auto event=_hashgraph.registerEvent(this, epack.pubkey, epack.signature,  epack.event_body);
            }
        }
    }

    static struct EventPackage {
        immutable(ubyte[]) signature;
        immutable(Pubkey) pubkey;
        immutable(EventBody) event_body;
        this(Document doc) {
            signature=(doc[Event.Params.signature].get!(immutable(ubyte[]))).idup;
            pubkey=buf_idup!Pubkey(doc[Event.Params.pubkey].get!Buffer);
            auto doc_ebody=doc[Event.Params.ebody].get!Document;
            event_body=immutable(EventBody)(doc_ebody);
        }
        static EventPackage undefined() {
            check(false, ConsensusFailCode.GOSSIPNET_EVENTPACKAGE_NOT_FOUND);
            assert(0);
        }
    }

    /++ to synchronize two nodes A and B
     +  1)
     +  Node A send it's wave front to B
     +  This is done via the waveFront function
     +  2)
     +  B collects all the events it has which is are in front of the
     +  wave front of A.
     +  This is done via the waveFront function
     +  B send the all the collected event to B including B's wave font of all
     +  the node which B know it leads in,
     +  The wave from is collect via the waveFront function by adding the remaining tides
     +  3)
     +  A send the rest of the event which is in front of B's wave-front
     +/
    Tides tideWave(HBSON bson, bool build_tides) {
        HBSON[] fronts;
        Tides tides;
        foreach(n; _hashgraph.nodeiterator) {
            if ( n.isOnline ) {
                auto node=new HBSON;
                node[Event.Params.pubkey]=n.pubkey;
                node[Event.Params.altitude]=n.altitude;
                fronts~=node;
                if ( build_tides ) {
                    tides[n.pubkey] = n.altitude;
                }
            }
        }
        bson[Params.tidewave]=fronts;
        return tides;
    }


    /++
     This function collects the tide wave
     Between the current Hashgraph and the wave-front
     Returns the top most event on node received_pubkey
     +/
    immutable(ubyte[]) waveFront(Pubkey received_pubkey, Document doc, ref Tides tides) {
        immutable(ubyte)[] result;
        int result_altitude;
        immutable is_tidewave=doc.hasElement(Params.tidewave);
        scope(success) {
            if ( callbacks ) {
                callbacks.received_tidewave(received_pubkey, tides);
            }
        }
        if ( is_tidewave ) {
            auto tidewave=doc[Params.tidewave].get!Document;
            foreach(pack; tidewave) {
                auto pack_doc=pack.get!Document;
                immutable _pkey=cast(Pubkey)(pack_doc[Event.Params.pubkey].get!(immutable(Buffer)));
                immutable altitude=pack_doc[Event.Params.altitude].get!int;
                tides[_pkey]=altitude;
            }
        }
        else {
            auto wavefront=doc[Params.wavefront].get!Document;
            foreach(pack; wavefront) {
                auto pack_doc=pack.get!Document;

                // Create event package and cache it
                auto event_package=EventPackage(pack_doc);
                // The message is the hashpointer to the event body
                immutable fingerprint=calcHash(event_package.event_body.serialize);
                if ( !_hashgraph.isRegistered(fingerprint) && !_event_package_cache.contains(fingerprint)) {
                    check(verify(fingerprint, event_package.signature, event_package.pubkey), ConsensusFailCode.EVENT_SIGNATURE_BAD);

                    _event_package_cache[fingerprint]=event_package;
                }

                // Altitude
                auto altitude_p=event_package.pubkey in tides;
                if ( altitude_p ) {
                    immutable altitude=*altitude_p;
                    tides[event_package.pubkey]=highest(altitude, event_package.event_body.altitude);
                }
                else {
                    tides[event_package.pubkey]=event_package.event_body.altitude;
                }
                if ( received_pubkey == event_package.pubkey  ) {
                    if ( (result is null) ||  lower(result_altitude, event_package.event_body.altitude) ) {
                        result_altitude = event_package.event_body.altitude;
                        result=fingerprint;
                    }
                }
                _hashgraph.setAltitude(event_package.pubkey, event_package.event_body.altitude);
            }
        }
        return result;
    }

    HBSON[] buildWavefront(Tides tides, bool is_tidewave) {
        HBSON[] events;
        foreach(i_n, n; _hashgraph.nodeiterator) {
            auto other_altitude_p=n.pubkey in tides;
            if ( other_altitude_p ) {
                immutable other_altitude=*other_altitude_p;
                foreach(e; n) {
                    if ( higher( other_altitude, e.altitude) ) {
                        break;
                    }
                    events~=e.toBSON;
                }
            }
            else if ( is_tidewave ) {
                foreach(e; n) {
                    events~=e.toBSON;
                }
            }
        }
        return events;
    }


    alias convertState=convertEnum!(ExchangeState, GossipConsensusException);

    @trusted
    void trace(string type, immutable(ubyte[]) data) {
        debug {
            if ( options.trace_gossip ) {
                //import std.file;
//                log.writefln("%s/_%d_%s.bson", options.tmp, _type); //.to!string~"_receive.bson";
//                write(packfile, data);
//                _send_count++;
            }
        }
    }

    override Event receive(immutable(ubyte[]) data,
        Event delegate(immutable(ubyte)[] father_fingerprint) @safe register_leading_event ) {
        trace("receive", data);
        if ( callbacks ) {
            callbacks.receive(data);
        }

        Event result;
        auto doc=Document(data);
        Pubkey received_pubkey=doc[Event.Params.pubkey].get!(immutable(ubyte)[]);
        fout.writefln("Receive %s data=%d", received_pubkey.cutHex, data.length);

        check(received_pubkey != pubkey, ConsensusFailCode.GOSSIPNET_REPLICATED_PUBKEY);

        immutable type=doc[Params.type].get!uint;
        immutable received_state=convertState(type);
        // This indicates when a communication sequency ends
        bool end_of_sequence=false;

        // This repesents the current state of the local node
        auto received_node=_hashgraph.getNode(received_pubkey);
        //auto _node=_hashgraph.getNode(pubkey);
        if ( !online ) {
            // Queue the package if we still are busy
            // with the current package
            _queue.write(data);
        }
        else {
            auto signature=doc[Event.Params.signature].get!(immutable(ubyte)[]);
            auto block=doc[Params.block].get!Document;
            immutable message=calcHash(block.data);
            if ( verify(message, signature, received_pubkey) ) {
                if ( callbacks ) {
                    callbacks.wavefront_state_receive(received_node);
                }
                with(ExchangeState) final switch (received_state) {
                    case NONE:
                    case INIT_TIDE:
                        consensus(received_state).check(false, ConsensusFailCode.GOSSIPNET_ILLEGAL_EXCHANGE_STATE);
                        break;
                    case TIDE_WAVE:
                        // Receive the tide wave
                        consensus(received_node.state, INIT_TIDE, NONE).
                            check((received_node.state == INIT_TIDE) || (received_node.state == NONE),  ConsensusFailCode.GOSSIPNET_EXPECTED_OR_EXCHANGE_STATE);
                        Tides tides;
                        immutable father_fingerprint=waveFront(received_pubkey, block, tides);
                        // dump(tides);
                        assert(father_fingerprint is null); // This should be an exception
                        result=register_leading_event(null);
                        HBSON[] events=buildWavefront(tides, true);
                        check(events.length > 0, ConsensusFailCode.GOSSIPNET_MISSING_EVENTS);

                        // Add the new leading event
                        auto wavefront=new HBSON;
                        wavefront[Params.wavefront]=events;
                        // If the this node already have INIT and tide the a braking wave is send
                        auto exchange=(received_node.state == INIT_TIDE)?BREAK_WAVE:FIRST_WAVE;
                        auto wavefront_pack=buildEvent(wavefront, exchange);

                        send(received_pubkey, wavefront_pack.serialize);
                        received_node.state=received_state;
                        break;
                    case FIRST_WAVE:
                    case BREAK_WAVE:
                        // consensus(INIT_TIDE, received_node.state).check(received_node.state == INIT_TIDE,  ConsensusFailCode.GOSSIPNET_EXPECTED_EXCHANGE_STATE);
                        consensus(received_node.state, INIT_TIDE, TIDE_WAVE).
                            check((received_node.state == INIT_TIDE) || (received_node.state == TIDE_WAVE),  ConsensusFailCode.GOSSIPNET_EXPECTED_OR_EXCHANGE_STATE);

                        Tides tides;
                        immutable father_fingerprint=waveFront(received_pubkey, block, tides);
                        // dump(tides);
                        result=register_leading_event(father_fingerprint);
                        immutable send_second_wave=(received_state == FIRST_WAVE);
                        if ( send_second_wave ) {
                            assert(result !is null);
                            assert(result is _hashgraph.getNode(pubkey).event);
                            HBSON[] events=buildWavefront(tides, true);
                            auto wavefront=new HBSON;
                            wavefront[Params.wavefront]=events;

                            // Receive the tide wave and return the wave front
                            auto wavefront_pack=buildEvent(wavefront, SECOND_WAVE);
                            send(received_pubkey, wavefront_pack.serialize);
                        }
                        end_of_sequence=true;
                        received_node.state=NONE;
                        break;
                    case SECOND_WAVE:
                        consensus(received_node.state, TIDE_WAVE).check( received_node.state == TIDE_WAVE,  ConsensusFailCode.GOSSIPNET_EXPECTED_EXCHANGE_STATE);
                        Tides tides;

                        immutable father_fingerprint=waveFront(received_pubkey, block, tides);
                        result=register_leading_event(father_fingerprint);
                        received_node.state=NONE;
                        end_of_sequence=true;
                    }

            }
        }
        if ( !_queue.empty && online ) {

            if ( end_of_sequence ) {
                auto d=_queue.read;
                receive(d, register_leading_event);
            }
        }
        return result;
    }

    version(none)
    void request(HashGraph hashgraph, immutable(ubyte[]) fingerprint) {
        if ( !_hashgraph.isRegistered(fingerprint) ) {
            immutable has_new_event=(fingerprint !is null);
            if ( has_new_event ) {
                EventPackage epack=_event_package_cache[fingerprint];
                _event_package_cache.remove(fingerprint);
                auto event=_hashgraph.registerEvent(this, epack.pubkey, epack.signature,  epack.event_body);
            }
        }
    }

    protected string _node_name;
    @property void node_name(string name)
        in {
            assert(_node_name is null, format("%s is already set", __FUNCTION__));
        }
    do {
        _node_name=name;
    }

    @property string node_name() pure const nothrow {
        return _node_name;
    }

    @property
    void time(const(ulong) t) {
        _current_time=t;
    }

    @property
    const(ulong) time() pure const {
        return _current_time;
    }

    protected Tid _transcript_tid;
    @property void transcript_tid(Tid tid)
        @trusted in {
        assert(_transcript_tid != _transcript_tid.init, format("%s hash already been set", __FUNCTION__));
    }
    do {
        _transcript_tid=tid;
    }

    @property Tid transcript_tid() pure nothrow {
        return _transcript_tid;
    }

    protected Tid _scripting_engine_tid;
    @property void scripting_engine_tid(Tid tid) @trusted in {
        assert(_scripting_engine_tid != _scripting_engine_tid.init, format("%s hash already been set", __FUNCTION__));
    }
    do {
        _scripting_engine_tid=tid;
    }

    @property Tid scripting_engine_tid() pure nothrow {
        return _scripting_engine_tid;
    }
}
