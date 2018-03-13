module bakery.hashgraph.HashGraph;

import std.stdio;
import std.conv;
//import bakery.hashgraph.Store;
import bakery.hashgraph.Event;
import bakery.hashgraph.GossipNet;
import bakery.utils.LRU;
import bakery.utils.BSON : Document;
import bakery.crypto.Hash;

@safe
class HashGraphConsensusException : ConsensusException {
    this( immutable(char)[] msg, ConcensusFailCode code, string file = __FILE__, size_t line = __LINE__ ) {
        super( msg, code, file, line );
    }
}

@safe
class HashGraph {
    alias immutable(ubyte)[] Pubkey;
    alias immutable(ubyte)[] Privkey;
    alias immutable(ubyte)[] HashPointer;
    alias LRU!(HashPointer, Event) EventCache;

    //alias LRU!(Round, uint*) RoundCounter;
    alias immutable(ubyte)[] function(Pubkey, Privkey,  immutable(ubyte)[] message) Sign;
    private EventCache _event_cache;
    // List of rounds
    private Round _rounds;

    //private RoundCounter _round_counter;
//    private GossipNet _gossip_net;
    // static this() {
    //     event_cache=new EventCache(null);
    //     round_counter=new RoundCounter(null);
//    }

    this() {
        _event_cache=new EventCache(null);
        //_round_counter=new RoundCounter(null);
    }

    struct EventPackage{
        Pubkey pubkey;
//        Privkey privkey;
//        Sign sign;
        immutable(ubyte)[] signature;
        immutable(EventBody) eventbody;
        this(
            Pubkey pubkey,
            Privkey privkey,
            Sign sign,
            const ref EventBody e
            ) {

            this.pubkey=pubkey;
            this.signature=sign(pubkey, privkey, eventbody.serialize);
            this.eventbody=e;
        }
        // Create from an BSON stream
        this(immutable(ubyte)[] data) {
            auto doc=Document(data);
            this(doc);
        }

        @trusted
        this(Document doc) {
            foreach(i, ref m; this.tupleof) {
                alias typeof(m) type;
                enum name=EventPackage.tupleof[i].stringof;
                static if ( __traits(compiles, m.toBSON) ) {
                    static if ( is(type T : immutable(T)) ) {
                        this.tupleof[i]=T(doc[name].get!(Document));
                    }
                }
                else {
                    this.tupleof[i]=doc[name].get!type;
                }
            }
        }

        GBSON toBSON() {
            auto bson=new GBSON;
            foreach(i, m; this.tupleof) {
                enum name=this.tupleof[i].stringof["this.".length..$];
                static if ( __traits(compiles, m.toBSON) ) {
                    bson[name]=m.toBSON;
                }
                else {
                    bool flag=true;
                    static if ( __traits(compiles, m !is null) ) {
                        flag=m !is null;
                    }
                    if (flag) {
                        bson[name]=m;
                    }
                }
            }
            return bson;
        }

        @trusted
        immutable(ubyte)[] serialize() {
            return toBSON.expand;
        }
    }

    package static Round find_previous_round(Event event) {
        Event e;
        for (e=event; e && !e.round; e=e.mother) {
            // Empty
        }
        return e.round;
    }

    class Node {
        //DList!(Event) queue;
        immutable uint node_id;
        immutable ulong discovery_time;
        immutable Pubkey pubkey;
        this(Pubkey pubkey, uint node_id, ulong time) {
            this.pubkey=pubkey;
            this.node_id=node_id;
            this.discovery_time=time;
        }
        // void updateRound(Round round) {
        //     this.round=round;
        // }
        // Counts the number of times that a search has
        // passed this node in the graph search
        int passed;
        uint seeing; // See a witness
        bool voted;
        // uint voting;
        bool fork; // Fork detected in the hashgraph
        Event event; // Last witness
    // private:
    //     Round round;
    }

//    Round round; // Current round
    Node[uint] nodes; // List of participating nodes T
    uint[Pubkey] node_ids; // Translation table from pubkey to node_indices;
    uint[] unused_node_ids; // Stack of unused node ids

    static ulong time;
    static ulong current_time() {
        time+=100;
        return time;
    }

    void assign(Event event) {
        _event_cache[event.toCryptoHash]=event;
    }

    Event lookup(immutable(ubyte[]) fingerprint) @safe {
//        Event result;
//        writefln("Lookup %s", fingerprint.toHexString);
        return _event_cache[fingerprint];
    }


    // Returns the number of active nodes in the network
    uint active_nodes() const pure nothrow {
        return cast(uint)(node_ids.length);
    }

    uint total_nodes() const pure nothrow {
        return cast(uint)(node_ids.length+unused_node_ids.length);
    }

    // uint threshold() const pure nothrow {
    //     return (active_nodes*2)/3;
    // }

    enum minimum_nodes = 4;
    bool isMajority(uint voting) const pure nothrow {
        return (active_nodes >= minimum_nodes) && (3*voting > 2*active_nodes);
    }

    private void remove_node(Node n)
        in {
            assert(n !is null);
            assert(n.node_id < total_nodes);
            assert(n.node_id in nodes, "Node id "~to!string(n.node_id)~" is not removable because it does not exist");
        }
//     out {
//         writefln("node_ids.length=%d active_nodes=%d unused_node_ids.length=%d",
//             node_ids.length, active_nodes, unused_node_ids.length);
// //        assert(node_ids.length == active_nodes + unused_node_ids.length);
//     }
    body {
//        writefln("******* REMOVE %d", n.node_id);
        n.event=null;
        nodes.remove(n.node_id);//=null;
        node_ids.remove(n.pubkey);
        unused_node_ids~=n.node_id;
    }

    // uint countRound(Round round) {
    //     uint* count;
    //     if ( !_round_counter.get(round, count) ) {
    //         count=new uint;
    //         _round_counter.add(round, count);
    //     }
    //     (*count)++;
    //     return (*count);
    // }

    // static void check(immutable bool flag, ConcensusFailCode code, string msg) @safe {
    //     if (!flag) {
    //         throw new EventConsensusException(msg, code);
    //     }
    // }

    enum max_package_size=0x1000;
    alias immutable(Hash) function(immutable(ubyte)[]) @safe Hfunc;
    @trusted
    Event receive(
        GossipNet gossip_net,
        immutable(ubyte)[] data,
        bool delegate(ref const(Pubkey) pubkey, immutable(ubyte[]) msg, Hfunc hfunc) signed,
        Hfunc hfunc) {
        auto doc=Document(data);
        Pubkey pubkey;
        Event event;
        enum pubk=pubkey.stringof;
        enum event_label=event.stringof;
        immutable(ubyte)[] eventbody_data;
        with ( ConcensusFailCode ) {
            check((data.length <= max_package_size), PACKAGE_SIZE_OVERFLOW, "The package size exceeds the max of "~to!string(max_package_size));
            check(doc.hasElement(pubk), EVENT_PACKAGE_MISSING_PUBLIC_KEY, "Event package is missing public key");
            check(doc.hasElement(event_label), EVENT_PACKAGE_MISSING_EVENT, "Event package missing the actual event");
            pubkey=doc[pubk].get!(immutable(ubyte)[]);
            eventbody_data=doc[event_label].get!(immutable(ubyte[]));
            check(signed(pubkey, eventbody_data, hfunc), EVENT_PACKAGE_BAD_SIGNATURE, "Invalid signature on event");
        }
        // Now we come this far so we can register the event
        immutable eventbody=EventBody(eventbody_data);
        event=registerEvent(gossip_net, pubkey, eventbody);
        return event;
    }

    Round nextRound(Event event)
        out(result) {
            assert(result);
        }
    body {
        auto previous=find_previous_round(event);
        auto number=Round.increase_number(previous);
        if ( _rounds ) {
            assert(number <= _rounds.number+1);
            if ( number == _rounds.number+1 ) {
                auto new_round = new Round(_rounds, total_nodes);
                _rounds = new_round;
            }
            else {
                Round search(Round r) {
                    if ( r ) {
                        if ( r.number == number ) {
                            return r;
                        }
                    }
                    return search(r.previous);
                }
                return search(_rounds);
            }
        }
        else {
            _rounds = new Round(previous, total_nodes);
        }
        return _rounds;
    }

    // Event registerEvent(
    //     immutable(Pubkey) pubkey,
    //     ref immutable(EventBody) eventbody,
    //     Hfunc hfunc) {
    //     return null;
    // }

    Event registerEvent(
        GossipNet gossip_net,
        immutable(Pubkey) pubkey,
        ref immutable(EventBody) eventbody) {
        Event event=lookup(Event.fhash(eventbody.serialize).digits);
        if ( !event ) {
            auto get_node_id=pubkey in node_ids;
            uint node_id;
            Node node;

            // foreach(i, ref n; node_ids) {
            //     writefln(" n[%s]", i);
            // }
            // Find a resuable node id if possible
            if ( get_node_id is null ) {
                if ( unused_node_ids.length ) {
                    node_id=unused_node_ids[0];
                    unused_node_ids=unused_node_ids[1..$];
                    node_ids[pubkey]=node_id;
                }
                else {
                    node_id=cast(uint)node_ids.length;
                    node_ids[pubkey]=node_id;
                }
                node=new Node(pubkey, node_id, current_time);
                nodes[node_id]=node;
            }
            else {
                node_id=*get_node_id;
                node=nodes[node_id];
            }
//            node.round=round;
            event=new Event(eventbody, node_id);
            // Add the event to the event cache
            assign(event);
//        event_cache.add(hfunc(eventbody.serialize).digits,

        // Makes sure that we have the tree before the graph is checked
            requestEventTree(gossip_net, event);
            // See if the node is strong seeing the hashgraph
            strongSee(event);
        }
        return event;
    }

//    private uint strong_see_marker;
    /**
       This function makes sure that the HashGraph has all the events connected to this event
     */
    package void requestEventTree(GossipNet gossip_net, Event event, Event child=null, immutable bool is_father=false) {
        if ( event ) {
            if ( child ) {
//                writefln("REQUEST EVENT TREE %d.%s %s", event.id, (child)?to!string(child.id):"#", is_father);
                if ( is_father ) {
//                    writeln("\tset son");
                    event.son=child;
                }
                else {
//                    writeln("\tset daughter");
                    event.daughter=child;
                }
            }
            auto mother=event.mother(this, gossip_net);
            requestEventTree(gossip_net, mother, event, false);
            auto father=event.father(this, gossip_net);
            requestEventTree(gossip_net, father, event, true);
            if ( Event.callbacks ) {
                Event.callbacks.create(event);
            }
        }
    }

    // This function makes the votes for famous event
    package void searchFamous(Event top_event)
    in {
        assert(top_event.witness, "Event should be a witness");
    }
    body {
        void findWitness(Event event) {
            if ( event ) {
                if ( event.witness ) {
                    event.set_witness_mask(top_event.node_id);
                    event.famous=isMajority(event.famous_votes);
                }
                else {
                    findWitness(event.mother);
                    findWitness(event.mother);
                }
            }
        }
        findWitness(top_event.mother);
        findWitness(top_event.father);
    }

    package void strongSee(Event event) {
        void checkStrongSeeing(Event top_event) {
            import std.bitmanip;
            BitArray[] vote_mask=new BitArray[total_nodes];
            @trusted void reset_bitarray(ref BitArray b) {
                b.length=0;
                b.length=total_nodes;
            }

            // Clear the node log
            foreach(i,ref n; nodes) {
                if ( n !is null ) {
                    n.passed=0;
                    n.seeing=0;
                    n.event=null;
                    n.voted=false;
                    //      writefln("Index %d vote_mask.length=%d", i, vote_mask.length);
                    reset_bitarray(vote_mask[i]);
                }
            }

            //        strong_see_marker++;
//            writefln("######################## STRONG SEEING %d ############################", strong_see_marker);
//        bool forked;
            uint count;
            // Seeing is counting the number of witness which can bee seen by top_event
            uint seeing;
            void search(Event event, string indent="") @safe {
                uint vote(ref BitArray mask) @trusted {
                    uint votes;
                    enum self_voting=true;

                    foreach(i, n; nodes) {
                        if ( self_voting || (i != event.node_id) ) {
                            if ( n.passed > 0 ) {
                                mask[i]=true;
                            }
                            if (mask[i]) {
                                votes++;
                            }
                        }
                    }
//                    writefln("\tvoting = %d mask = %s", votes, mask);
                    return votes;
                }
                immutable(char)[] masks(ref const BitArray mask) @trusted {
                    return to!string(mask);
                }
                count++;
//                writefln("%sSearch for famous count=%d ", indent,count);

                // Finde the node for the event
                auto pnode=event.node_id in nodes;
                immutable not_famous_yet=(pnode !is null) && (event !is null) && (!event.famous);
                if ( not_famous_yet ) {
                    auto n=*pnode;
//                    assert(n !is null);
                    // writefln("EVENT %d NODE %d marker %d M=%s F=%s '%s' %s",
                    //     event.id, event.node_id, event.marker,
                    //     (event.mother)?to!string(event.mother.id):"#",
                    //     (event.father)?to!string(event.father.id):"#",
                    //     cast(string)(event.payload),
                    //     event.toCryptoHash.toHexString );
                    // if ( event.marker == strong_see_marker ) {
                    //     n.fork=true;
                    //     writefln("FORKED EVENT %d", event.id);
                    // }
                    // else {
                        // marker secures that the search is not called again
                        // for the same Strong Seeing check
//                        event.marker=strong_see_marker;
                        n.passed++;
//                immutable decrease_passed=true;
                        // writefln("\t%sn.passed=%d node=%d count=%d", indent, n.passed, event.node_id, count);
                        scope(exit) {
                            n.passed--;
                            // writefln("\t%sexit n.passed=%d n.fork=%s node=%d count=%d", indent, n.passed, n.fork, event.node_id, count);
                            assert(n.passed >= 0);
                        }

                        if ( event.witness ) {
                            if ( n.event !is event ) {
                                if ( n.event is null ) {
                                    n.event=event;
                                }
                                else if ( n.event.round.number < event.round.number ) {
                                    n.event=event;
                                    // Clear the vote_mask
                                    reset_bitarray(vote_mask[event.node_id]);
                                    // vote_mask[event.node_id].length=0;
                                    // vote_mask[event.node_id].length=nodes.length;
                                }
                                //n.seeing=1;
                                n.voted=false;
                            }
                            if (!n.voted) {
                                auto votes=vote(vote_mask[event.node_id]);
                                immutable majority=isMajority(votes);
                                if ( majority ) {
//                                    writefln("Majority !!!!");
                                    seeing++;
                                    n.voted=true;
                                }
                            }
//                            writefln("\t%sWITNESS seeing=%d n.voted=%s mask=%s count=%d", indent, seeing, n.voted, masks(vote_mask[event.node_id]), count);
                            return;
                        }
                        auto mother=event.mother;

                        if ( mother ) {
//                            mother.marker=strong_see_marker;
                            search(mother, indent~"M ");
                            if ( event.fatherExists ) {
                                auto father=event.father;
                                search(father, indent~"F ");
                            }
                        }
                        //}
                }
            }
            //uint voting;
            //Node[] forks;
            // Search to the number of witness
            search(top_event);
            //top_event.seeing=seeing;
            // writefln("Nodes %d", nodes.length);
            // foreach(i, ref n; nodes) {
            //     if ( n.event ) {
            //         if ( n.event.famous ) {
            //             voting++;
            //         }
            //     }
            // }
            // writefln("Voting %d", voting);
            bool strong=isMajority(seeing);
            if ( strong ) {
                //assert(top_event.witness);

                Event e;
                // Crawl down to the next witness
                for(e=top_event; !e.witness; e=e.mother) {
                    /* empty */
                }
                // if ( round == e.round+1 ) {
                //     round++;
                // }
                assert(top_event !is e);
                top_event.witness=true;

                top_event.round=nextRound(top_event);
//                assert(top_event.round == e.round+1);
            }
            writefln("Strongly Seeing test return %s", strong);
            top_event.strongly_seeing=strong;
            top_event.strongly_seeing_checked;

//            return strong;
        }
        if ( event && !event.is_strogly_seeing_checked ) {
            auto mother=event.mother;
            strongSee(mother);
            auto father=event.father;
            strongSee(father);
            if ( event.isEva ) {
                event.witness=true;
                event.round=Round.undefined;
            }
            checkStrongSeeing(event);
        }
    }

    version(none)
    unittest { // strongSee
        // This is the example taken from
        // HASHGRAPH CONSENSUS
        // SWIRLDS TECH REPORT TR-2016-01
        import bakery.crypto.SHA256;
        import std.traits;
        import std.conv;
        enum NodeLable {
            Alice,
            Bob,
            Carol,
            Dave,
            Elisa
        };
        struct Emitter {
            Pubkey pubkey;
        }
        auto h=new HashGraph;
        Emitter[NodeLable.max+1] emitters;
//        writefln("@@@ Typeof Emitter=%s %s", typeof(emitters).stringof, emitters.length);
        foreach (immutable l; [EnumMembers!NodeLable]) {
//            writefln("label=%s", l);
            emitters[l].pubkey=cast(Pubkey)to!string(l);
        }
        ulong current_time;
        uint dummy_index;
        ulong dummy_time() {
            current_time+=1;
            return current_time;
        }
        Hash hash(immutable(ubyte)[] data) {
            return new SHA256(data);
        }
        immutable(EventBody) newbody(immutable(EventBody)* mother, immutable(EventBody)* father) {
            dummy_index++;
            if ( father is null ) {
                auto hm=hash(mother.serialize).digits;
                return EventBody(null, hm, null, dummy_time);
            }
            else {
                auto hm=hash(mother.serialize).digits;
                auto hf=hash(father.serialize).digits;
                return EventBody(null, hm, hf, dummy_time);
            }
        }
        // Row number zero
        writeln("Row 0");
        // EventBody* a,b,c,d,e;
        with(NodeLable) {
            immutable a0=EventBody(hash(emitters[Alice].pubkey).digits, null, null, 0);
            immutable b0=EventBody(hash(emitters[Bob].pubkey).digits, null, null, 0);
            immutable c0=EventBody(hash(emitters[Carol].pubkey).digits, null, null, 0);
            immutable d0=EventBody(hash(emitters[Dave].pubkey).digits, null, null, 0);
            immutable e0=EventBody(hash(emitters[Elisa].pubkey).digits, null, null, 0);
            h.registerEvent(emitters[Bob].pubkey,   b0, &hash);
            h.registerEvent(emitters[Carol].pubkey, c0, &hash);
            h.registerEvent(emitters[Alice].pubkey, a0, &hash);
            h.registerEvent(emitters[Elisa].pubkey, e0, &hash);
            h.registerEvent(emitters[Dave].pubkey,  d0, &hash);

            // Row number one
            writeln("Row 1");
            alias a0 a1;
            alias b0 b1;
            immutable c1=newbody(&c0, &d0);
            immutable e1=newbody(&e0, &b0);
            alias d0 d1;
            //with(NodeLable) {
            h.registerEvent(emitters[Carol].pubkey, c1, &hash);
            h.registerEvent(emitters[Elisa].pubkey, e1, &hash);

            // Row number two
            writeln("Row 2");
            alias a1 a2;
            immutable b2=newbody(&b1, &c1);
            immutable c2=newbody(&c1, &e1);
            alias d1 d2;
            immutable e2=newbody(&e1, null);
            h.registerEvent(emitters[Bob].pubkey,   b1, &hash);
            h.registerEvent(emitters[Carol].pubkey, c1, &hash);
            h.registerEvent(emitters[Elisa].pubkey, e1, &hash);
            // Row number 2 1/2
            writeln("Row 2 1/2");

            alias a2 a2a;
            alias b2 b2a;
            alias c2 c2a;
            immutable d2a=newbody(&d2, &c2);
            alias e2 e2a;
            h.registerEvent(emitters[Dave].pubkey,  d2a, &hash);
            // Row number 3
            writeln("Row 3");

            immutable a3=newbody(&a2, &b2);
            immutable b3=newbody(&b2, &c2);
            immutable c3=newbody(&c2, &d2);
            alias d2a d3;
            immutable e3=newbody(&e2, null);
            //
            h.registerEvent(emitters[Alice].pubkey, a3, &hash);
            h.registerEvent(emitters[Bob].pubkey,   b3, &hash);
            h.registerEvent(emitters[Carol].pubkey, c3, &hash);
            h.registerEvent(emitters[Elisa].pubkey, e3, &hash);
            // Row number 4
            writeln("Row 4");


            immutable a4=newbody(&a3, null);
            alias b3 b4;
            alias c3 c4;
            alias d3 d4;
            immutable e4=newbody(&e3, null);
            //
            h.registerEvent(emitters[Alice].pubkey, a4, &hash);
            h.registerEvent(emitters[Elisa].pubkey, e4, &hash);
            // Row number 5
            writeln("Row 5");
            alias a4 a5;
            alias b4 b5;
            immutable c5=newbody(&c4, &e4);
            alias d4 d5;
            alias e4 e5;



            //

            h.registerEvent(emitters[Carol].pubkey, c5, &hash);
            // Row number 6
            writeln("Row 6");

            alias a5 a6;
            alias b5 b6;
            immutable c6=newbody(&c5, &a5);
            alias d5 d6;
            alias e5 e6;

            //
            h.registerEvent(emitters[Alice].pubkey, a6, &hash);
        }
        writeln("Row end");

    }

}
