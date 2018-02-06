module bakery.hashgraph.HashGraph;

import std.stdio;
import std.conv;
//import bakery.hashgraph.Store;
import bakery.hashgraph.Event;
import bakery.utils.LRU;
import bakery.utils.BSON : Document;
import bakery.crypto.Hash;

@safe
class HashGraphConsensusException : ConsensusException {
    this( immutable(char)[] msg ) {
//        writefln("msg=%s", msg);
        super( msg );
    }
}

class HashGraph {
    alias immutable(ubyte)[] Pubkey;
    alias immutable(ubyte)[] Privkey;
    alias immutable(ubyte)[] HashPointer;
    alias LRU!(HashPointer, Event) EventCache;
    alias LRU!(Round, uint*) RoundCounter;
    alias immutable(ubyte)[] function(Pubkey, Privkey,  immutable(ubyte)[] message) Sign;
    static EventCache event_cache;
    static RoundCounter round_counter;
    static this() {
        event_cache=new EventCache(null);
        round_counter=new RoundCounter(null);
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
                    bson[name]=m;
                }
            }
            return bson;
        }
        immutable(ubyte)[] serialize() {
            return toBSON.expand;
        }
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
        void updateRound(Round round) {
            this.round=round;
        }
        // Counts the number of times that a search has
        // passed this node in the graph search
        int passed;
        uint seeing; // See a witness
        bool voted;
        // uint voting;
        bool fork; // Fork detected in the hashgraph
        Event event; // Last witness
    private:
        Round round;
    }

    Round round; // Current round
    Node[uint] nodes; // List of participating nodes T
    uint[Pubkey] node_ids; // Translation table from pubkey to node_indices;
    uint[] unused_node_ids; // Stack of unused node ids

    static ulong time;
    static ulong current_time() {
        time+=100;
        return time;
    }

    // Returns the number of active nodes in the network
    uint active_nodes() const pure nothrow {
        return cast(uint)(node_ids.length-unused_node_ids.length);
    }

    uint threshold() const pure nothrow {
        return (active_nodes*2)/3+1;
    }

    bool isMajority(uint voting) const pure nothrow {
        return voting > threshold;
    }

    private void remove_node(Node n)
        in {
            assert(n !is null);
            assert(n.node_id < nodes.length);
        }
    out {
        assert(node_ids.length == active_nodes);
    }
    body {
        nodes[n.node_id]=null;
        node_ids.remove(n.pubkey);
        unused_node_ids~=n.node_id;
    }

    uint countRound(Round round) {
        uint* count;
        if ( !round_counter.get(round, count) ) {
            count=new uint;
            round_counter.add(round, count);
        }
        (*count)++;
        return (*count);
    }

    static void check(immutable bool flag, string msg) @safe {
        if (!flag) {
            throw new EventConsensusException(msg);
        }
    }

    enum max_package_size=0x1000;
    alias Hash delegate(immutable(ubyte)[]) Hfunc;
    Event receive(
        immutable(ubyte)[] data,
        bool delegate(ref const(Pubkey) pubkey, immutable(ubyte[]) msg, Hfunc hfunc) signed,
        Hfunc hfunc) {
        auto doc=Document(data);
        Pubkey pubkey;
        Event event;
        enum pubk=pubkey.stringof;
        enum event_label=event.stringof;
        check((data.length <= max_package_size), "The package size exceeds the max of "~to!string(max_package_size));
        check(doc.hasElement(pubk), "Event package is missing public key");
        check(doc.hasElement(event_label), "Event package missing the actual event");
        pubkey=doc[pubk].get!(immutable(ubyte)[]);
        auto eventbody_data=doc[event_label].get!(immutable(ubyte[]));
        check(signed(pubkey, eventbody_data, hfunc), "Invalid signature on event");
        // Now we come this far so we can register the event
        immutable(EventBody) eventbody=EventBody(eventbody_data);
        event=registerEvent(pubkey, eventbody, hfunc);
        // See if the node is strong seeing the hashgraph
        event.strongly_seeing=strongSee(event);
        return event;
    }

    package Event registerEvent(
        ref const(Pubkey) pubkey,
        ref immutable(EventBody) eventbody,
        Hfunc hfunc) {
        auto get_node_id=pubkey in node_ids;
        uint node_id;
        Node node;
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
        node.round=round;
        auto event=new Event(eventbody, node_id);
        // Add the event to the event cache
        // auto ee=eventbody.serialize;
        //       auto hf=hfunc(eventbody.serialize);
        event_cache.add(hfunc(eventbody.serialize).digits, event);
        return event;
    }

    private static uint strong_see_marker;
    package bool strongSee(Event event) {
        import std.bitmanip;
        BitArray[] vote_mask=new BitArray[nodes.length];
        // Clear the node log
        foreach(i,ref n; nodes) {
            if ( n !is null ) {
                n.passed=0;
                n.seeing=0;
//                n.fork=false;
//                n.famous=false;
                n.event=null;
                n.voted=false;
                vote_mask[i].length=nodes.length;
            }
        }

        strong_see_marker++;
        bool forked;
        void search(Event event) {
            uint vote(ref BitArray mask) {
                uint votes;
                foreach(i, n; nodes) {
                    if (i != event.node_id) {
                        if ( n.passed > 0 ) {
                            mask[i]=true;
                        }
                        if (mask[i]) {
                            votes++;
                        }
                    }
                }
                return votes;
            }
            if ( (event !is null) && (!event.famous) ) {
                auto n=nodes[event.node_id];
                assert(n !is null);
                n.passed++;
                scope(exit) {
                    n.passed--;
                    assert(n.passed >= 0);
                }
                if ( n.fork ) return;
                if ( event.witness ) {
                    if ( n.event !is event ) {
                        if ( n.event is null ) {
                            n.event=event;
                        }
                        else if ( n.event.round < event.round ) {
                            n.event=event;
                            // Clear the vote_mask
                            vote_mask[event.node_id].length=0;
                            vote_mask[event.node_id].length=nodes.length;
                        }
                        n.seeing=1;
                        n.voted=false;
                    }
                    auto votes=vote(vote_mask[event.node_id]);
                    if ( isMajority(votes) ) {
                        n.seeing++;
                        n.voted=true;
                    }
                    return;
                }
                auto mother=event.mother;
                if ( mother.marker != strong_see_marker ) {
                    // marker secures that the
                    mother.marker=strong_see_marker;
                    search(mother);
                    search(event.father);
                }
                else {
                    n.fork=true;
                    n.event=null;
//                    n.seeing=0;
                }
            }
        }
        uint voting;
        Node[] forks;
        foreach(ref n; nodes) {
            if (n.fork ) {
                // If we have a forks the nodes is removed
                remove_node(n);
            }
            else if ( n.event ) {
                if ( n.event.famous ) {
                    voting++;
                }
            }
        }
        bool strong=isMajority(voting);
        if ( strong ) {
            event.witness=true;
            Event e;
            for(e=event.mother; !event.witness; e=e.mother) {
                /* empty */
            }
            if ( round == e.round+1 ) {
                round++;
            }
            event.round=round;
            assert(event.round == e.round+1);
        }
        return strong;
    }

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
        writefln("@@@ Typeof Emitter=%s %s", typeof(emitters).stringof, emitters.length);
        foreach (immutable l; [EnumMembers!NodeLable]) {
            writefln("label=%s", l);
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

/++
    uint[string] Participants;         //[public key] => id
    uint[string] ReverseParticipants;  //[id] => public key
    Store        Store;                //store of Events and Rounds
    Hash[]       UndeterminedEvents;   //[index] => hash
    int[]        UndecidedRounds;      //queue of Rounds which have undecided witnesses
    int*         LastConsensusRound;   //index of last round where the fame of all witnesses has been decided
    int LastCommitedRoundEvents;       //number of events in round before LastConsensusRound
    int ConsensusTransactions;         //number of consensus transactions
    int PendingLoadedEvents;           //number of loaded events that are not yet committed
//	commitCh                chan []Event   //channel for committing events
    Event[] commitCh;
    int topologicalIndex;              //counter used to order events in topological order
    int superMajority;

	ancestorCache           *common.LRU
	selfAncestorCache       *common.LRU
	oldestSelfAncestorCache *common.LRU
	stronglySeeCache        *common.LRU
	parentRoundCache        *common.LRU
	roundCache              *common.LRU

	logger *logrus.Logger


        this(participants map[string]int, store Store, commitCh chan []Event, logger *logrus.Logger) *Hashgraph {
	if logger == nil {
		logger = logrus.New()
		logger.Level = logrus.DebugLevel
	}

	reverseParticipants := make(map[int]string)
	for pk, id := range participants {
		reverseParticipants[id] = pk
	}

	cacheSize := store.CacheSize()
	return &Hashgraph{
		Participants:            participants,
		ReverseParticipants:     reverseParticipants,
		Store:                   store,
		commitCh:                commitCh,
		ancestorCache:           common.NewLRU(cacheSize, nil),
		selfAncestorCache:       common.NewLRU(cacheSize, nil),
		oldestSelfAncestorCache: common.NewLRU(cacheSize, nil),
		stronglySeeCache:        common.NewLRU(cacheSize, nil),
		parentRoundCache:        common.NewLRU(cacheSize, nil),
		roundCache:              common.NewLRU(cacheSize, nil),
		logger:                  logger,
		superMajority:           2*len(participants)/3 + 1,
		UndecidedRounds:         []int{0}, //initialize
	}
}

    }
// func (h *Hashgraph) SuperMajority() int {
// 	return h.superMajority
// }

//true if y is an ancestor of x
func (h *Hashgraph) Ancestor(x, y string) bool {
	if c, ok := h.ancestorCache.Get(Key{x, y}); ok {
		return c.(bool)
	}
	a := h.ancestor(x, y)
	h.ancestorCache.Add(Key{x, y}, a)
	return a
}

func (h *Hashgraph) ancestor(x, y string) bool {
	if x == y {
		return true
	}

	ex, err := h.Store.GetEvent(x)
	if err != nil {
		return false
	}

	ey, err := h.Store.GetEvent(y)
	if err != nil {
		return false
	}

	eyCreator := h.Participants[ey.Creator()]
	lastAncestorKnownFromYCreator := ex.lastAncestors[eyCreator].index

	return lastAncestorKnownFromYCreator >= ey.Index()
}

//true if y is a self-ancestor of x
func (h *Hashgraph) SelfAncestor(x, y string) bool {
	if c, ok := h.selfAncestorCache.Get(Key{x, y}); ok {
		return c.(bool)
	}
	a := h.selfAncestor(x, y)
	h.selfAncestorCache.Add(Key{x, y}, a)
	return a
}

func (h *Hashgraph) selfAncestor(x, y string) bool {
	if x == y {
		return true
	}
	ex, err := h.Store.GetEvent(x)
	if err != nil {
		return false
	}
	exCreator := h.Participants[ex.Creator()]

	ey, err := h.Store.GetEvent(y)
	if err != nil {
		return false
	}
	eyCreator := h.Participants[ey.Creator()]

	return exCreator == eyCreator && ex.Index() >= ey.Index()
}

//true if x sees y
func (h *Hashgraph) See(x, y string) bool {
	return h.Ancestor(x, y)
	//it is not necessary to detect forks because we assume that with our
	//implementations, no two events can be added by the same creator at the
	//same height (cf InsertEvent)
}

//oldest self-ancestor of x to see y
func (h *Hashgraph) OldestSelfAncestorToSee(x, y string) string {
	if c, ok := h.oldestSelfAncestorCache.Get(Key{x, y}); ok {
		return c.(string)
	}
	res := h.oldestSelfAncestorToSee(x, y)
	h.oldestSelfAncestorCache.Add(Key{x, y}, res)
	return res
}

func (h *Hashgraph) oldestSelfAncestorToSee(x, y string) string {
	ex, err := h.Store.GetEvent(x)
	if err != nil {
		return ""
	}
	ey, err := h.Store.GetEvent(y)
	if err != nil {
		return ""
	}

	a := ey.firstDescendants[h.Participants[ex.Creator()]]

	if a.index <= ex.Index() {
		return a.hash
	}

	return ""
}

//true if x strongly sees y
func (h *Hashgraph) StronglySee(x, y string) bool {
	if c, ok := h.stronglySeeCache.Get(Key{x, y}); ok {
		return c.(bool)
	}
	ss := h.stronglySee(x, y)
	h.stronglySeeCache.Add(Key{x, y}, ss)
	return ss
}

func (h *Hashgraph) stronglySee(x, y string) bool {

	ex, err := h.Store.GetEvent(x)
	if err != nil {
		return false
	}

	ey, err := h.Store.GetEvent(y)
	if err != nil {
		return false
	}

	c := 0
	for i := 0; i < len(ex.lastAncestors); i++ {
		if ex.lastAncestors[i].index >= ey.firstDescendants[i].index {
			c++
		}
	}
    return c >= superMajority;
}

//PRI.round: max of parent rounds
//PRI.isRoot: true if round is taken from a Root
func (h *Hashgraph) ParentRound(x string) ParentRoundInfo {
	if c, ok := h.parentRoundCache.Get(x); ok {
		return c.(ParentRoundInfo)
	}
	pr := h.parentRound(x)
	h.parentRoundCache.Add(x, pr)
	return pr
}

func (h *Hashgraph) parentRound(x string) ParentRoundInfo {
	res := NewBaseParentRoundInfo()

	ex, err := h.Store.GetEvent(x)
	if err != nil {
		return res
	}

	//We are going to need the Root later
	root, err := h.Store.GetRoot(ex.Creator())
	if err != nil {
		return res
	}

	spRound := -1
	spRoot := false
	//If it is the creator's first Event, use the corresponding Root
	if ex.SelfParent() == root.X {
		spRound = root.Round
		spRoot = true
	} else {
		spRound = h.Round(ex.SelfParent())
		spRoot = false
	}

	opRound := -1
	opRoot := false
	if _, err := h.Store.GetEvent(ex.OtherParent()); err == nil {
		//if we known the other-parent, fetch its Round directly
		opRound = h.Round(ex.OtherParent())
	} else if ex.OtherParent() == root.Y {
		//we do not know the other-parent but it is referenced in Root.Y
		opRound = root.Round
		opRoot = true
	} else if other, ok := root.Others[x]; ok && other == ex.OtherParent() {
		//we do not know the other-parent but it is referenced  in Root.Others
		//we use the Root's Round
		//in reality the OtherParent Round is not necessarily the same as the
		//Root's but it is necessarily smaller. Since We are intererest in the
		//max between self-parent and other-parent rounds, this shortcut is
		//acceptable.
		opRound = root.Round
	}

	res.round = spRound
	res.isRoot = spRoot
	if spRound < opRound {
		res.round = opRound
		res.isRoot = opRoot
	}
	return res
}

//true if x is a witness (first event of a round for the owner)
func (h *Hashgraph) Witness(x string) bool {
	ex, err := h.Store.GetEvent(x)
	if err != nil {
		return false
	}

	root, err := h.Store.GetRoot(ex.Creator())
	if err != nil {
		return false
	}

	//If it is the creator's first Event, return true
	if ex.SelfParent() == root.X && ex.OtherParent() == root.Y {
		return true
	}

	return h.Round(x) > h.Round(ex.SelfParent())
}

//true if round of x should be incremented
func (h *Hashgraph) RoundInc(x string) bool {

	parentRound := h.ParentRound(x)

	//If parent-round was obtained from a Root, then x is the Event that sits
	//right on top of the Root. RoundInc is true.
	if parentRound.isRoot {
		return true
	}

	//If parent-round was obtained from a regulare Event, then we need to check
	//if x strongly-sees a strong majority of withnesses from parent-round.
	c := 0
	for _, w := range h.Store.RoundWitnesses(parentRound.round) {
		if h.StronglySee(x, w) {
			c++
		}
	}

	return c >= h.SuperMajority()
}

func (h *Hashgraph) RoundReceived(x string) int {

	ex, err := h.Store.GetEvent(x)
	if err != nil {
		return -1
	}
	if ex.roundReceived == nil {
		return -1
	}

	return *ex.roundReceived
}

func (h *Hashgraph) Round(x string) int {
	if c, ok := h.roundCache.Get(x); ok {
		return c.(int)
	}
	r := h.round(x)
	h.roundCache.Add(x, r)
	return r
}

func (h *Hashgraph) round(x string) int {

	round := h.ParentRound(x).round

	inc := h.RoundInc(x)

	if inc {
		round++
	}
	return round
}

//round(x) - round(y)
func (h *Hashgraph) RoundDiff(x, y string) (int, error) {

	xRound := h.Round(x)
	if xRound < 0 {
		return math.MinInt32, fmt.Errorf("event %s has negative round", x)
	}
	yRound := h.Round(y)
	if yRound < 0 {
		return math.MinInt32, fmt.Errorf("event %s has negative round", y)
	}

	return xRound - yRound, nil
}

func (h *Hashgraph) InsertEvent(event Event, setWireInfo bool) error {
	//verify signature
	if ok, err := event.Verify(); !ok {
		if err != nil {
			return err
		}
		return fmt.Errorf("Invalid signature")
	}

	if err := h.CheckSelfParent(event); err != nil {
		return fmt.Errorf("CheckSelfParent: %s", err)
	}

	if err := h.CheckOtherParent(event); err != nil {
		return fmt.Errorf("CheckOtherParent: %s", err)
	}

	event.topologicalIndex = h.topologicalIndex
	h.topologicalIndex++

	if setWireInfo {
		if err := h.SetWireInfo(&event); err != nil {
			return fmt.Errorf("SetWireInfo: %s", err)
		}
	}

	if err := h.InitEventCoordinates(&event); err != nil {
		return fmt.Errorf("InitEventCoordinates: %s", err)
	}

	if err := h.Store.SetEvent(event); err != nil {
		return fmt.Errorf("SetEvent: %s", err)
	}

	if err := h.UpdateAncestorFirstDescendant(event); err != nil {
		return fmt.Errorf("UpdateAncestorFirstDescendant: %s", err)
	}

	h.UndeterminedEvents = append(h.UndeterminedEvents, event.Hex())

	if event.IsLoaded() {
		h.PendingLoadedEvents++
	}

	return nil
}

//Check the SelfParent is the Creator's last known Event
func (h *Hashgraph) CheckSelfParent(event Event) error {
	selfParent := event.SelfParent()
	creator := event.Creator()

	creatorLastKnown, _, err := h.Store.LastFrom(creator)
	if err != nil {
		return err
	}

	selfParentLegit := selfParent == creatorLastKnown

	if !selfParentLegit {
		return fmt.Errorf("Self-parent not last known event by creator")
	}

	return nil
}

//Check if we know the OtherParent
func (h *Hashgraph) CheckOtherParent(event Event) error {
	otherParent := event.OtherParent()
	if otherParent != "" {
		//Check if we have it
		_, err := h.Store.GetEvent(otherParent)
		if err != nil {
			//it might still be in the Root
			root, err := h.Store.GetRoot(event.Creator())
			if err != nil {
				return err
			}
			if root.X == event.SelfParent() && root.Y == otherParent {
				return nil
			}
			other, ok := root.Others[event.Hex()]
			if ok && other == event.OtherParent() {
				return nil
			}
			return fmt.Errorf("Other-parent not known")
		}
	}
	return nil
}

//initialize arrays of last ancestors and first descendants
func (h *Hashgraph) InitEventCoordinates(event *Event) error {
	members := len(h.Participants)

	event.firstDescendants = make([]EventCoordinates, members)
	for fakeID := 0; fakeID < members; fakeID++ {
		event.firstDescendants[fakeID] = EventCoordinates{
			index: math.MaxInt32,
		}
	}

	event.lastAncestors = make([]EventCoordinates, members)

	selfParent, selfParentError := h.Store.GetEvent(event.SelfParent())
	otherParent, otherParentError := h.Store.GetEvent(event.OtherParent())

	if selfParentError != nil && otherParentError != nil {
		for fakeID := 0; fakeID < members; fakeID++ {
			event.lastAncestors[fakeID] = EventCoordinates{
				index: -1,
			}
		}
	} else if selfParentError != nil {
		copy(event.lastAncestors[:members], otherParent.lastAncestors)
	} else if otherParentError != nil {
		copy(event.lastAncestors[:members], selfParent.lastAncestors)
	} else {
		selfParentLastAncestors := selfParent.lastAncestors
		otherParentLastAncestors := otherParent.lastAncestors

		copy(event.lastAncestors[:members], selfParentLastAncestors)
		for i := 0; i < members; i++ {
			if event.lastAncestors[i].index < otherParentLastAncestors[i].index {
				event.lastAncestors[i].index = otherParentLastAncestors[i].index
				event.lastAncestors[i].hash = otherParentLastAncestors[i].hash
			}
		}
	}

	index := event.Index()

	creator := event.Creator()
	fakeCreatorID, ok := h.Participants[creator]
	if !ok {
		return fmt.Errorf("Could not find fake creator id")
	}
	hash := event.Hex()

	event.firstDescendants[fakeCreatorID] = EventCoordinates{index: index, hash: hash}
	event.lastAncestors[fakeCreatorID] = EventCoordinates{index: index, hash: hash}

	return nil
}

//update first decendant of each last ancestor to point to event
func (h *Hashgraph) UpdateAncestorFirstDescendant(event Event) error {
	fakeCreatorID, ok := h.Participants[event.Creator()]
	if !ok {
		return fmt.Errorf("Could not find creator fake id (%s)", event.Creator())
	}
	index := event.Index()
	hash := event.Hex()

	for i := 0; i < len(event.lastAncestors); i++ {
		ah := event.lastAncestors[i].hash
		for ah != "" {
			a, err := h.Store.GetEvent(ah)
			if err != nil {
				break
			}
			if a.firstDescendants[fakeCreatorID].index == math.MaxInt32 {
				a.firstDescendants[fakeCreatorID] = EventCoordinates{index: index, hash: hash}
				if err := h.Store.SetEvent(a); err != nil {
					return err
				}
				ah = a.SelfParent()
			} else {
				break
			}
		}
	}

	return nil
}

func (h *Hashgraph) SetWireInfo(event *Event) error {
	selfParentIndex := -1
	otherParentCreatorID := -1
	otherParentIndex := -1

	//could be the first Event inserted for this creator. In this case, use Root
	if lf, isRoot, _ := h.Store.LastFrom(event.Creator()); isRoot && lf == event.SelfParent() {
		root, err := h.Store.GetRoot(event.Creator())
		if err != nil {
			return err
		}
		selfParentIndex = root.Index
	} else {
		selfParent, err := h.Store.GetEvent(event.SelfParent())
		if err != nil {
			return err
		}
		selfParentIndex = selfParent.Index()
	}

	if event.OtherParent() != "" {
		otherParent, err := h.Store.GetEvent(event.OtherParent())
		if err != nil {
			return err
		}
		otherParentCreatorID = h.Participants[otherParent.Creator()]
		otherParentIndex = otherParent.Index()
	}

	event.SetWireInfo(selfParentIndex,
		otherParentCreatorID,
		otherParentIndex,
		h.Participants[event.Creator()])

	return nil
}

func (h *Hashgraph) ReadWireInfo(wevent WireEvent) (*Event, error) {
	selfParent := ""
	otherParent := ""
	var err error

	creator := h.ReverseParticipants[wevent.Body.CreatorID]
	creatorBytes, err := hex.DecodeString(creator[2:])
	if err != nil {
		return nil, err
	}

	if wevent.Body.SelfParentIndex >= 0 {
		selfParent, err = h.Store.ParticipantEvent(creator, wevent.Body.SelfParentIndex)
		if err != nil {
			return nil, err
		}
	}
	if wevent.Body.OtherParentIndex >= 0 {
		otherParentCreator := h.ReverseParticipants[wevent.Body.OtherParentCreatorID]
		otherParent, err = h.Store.ParticipantEvent(otherParentCreator, wevent.Body.OtherParentIndex)
		if err != nil {
			return nil, err
		}
	}

	body := EventBody{
		Transactions: wevent.Body.Transactions,
		Parents:      []string{selfParent, otherParent},
		Creator:      creatorBytes,

		Timestamp:            wevent.Body.Timestamp,
		Index:                wevent.Body.Index,
		selfParentIndex:      wevent.Body.SelfParentIndex,
		otherParentCreatorID: wevent.Body.OtherParentCreatorID,
		otherParentIndex:     wevent.Body.OtherParentIndex,
		creatorID:            wevent.Body.CreatorID,
	}

	event := &Event{
		Body: body,
		R:    wevent.R,
		S:    wevent.S,
	}

	return event, nil
}

func (h *Hashgraph) DivideRounds() error {
	for _, hash := range h.UndeterminedEvents {
		roundNumber := h.Round(hash)
		witness := h.Witness(hash)
		roundInfo, err := h.Store.GetRound(roundNumber)

		//If the RoundInfo is not found in the Store's Cache, then the Hashgraph
		//is not aware of it yet. We need to add the roundNumber to the queue of
		//undecided rounds so that it will be processed in the other consensus
		//methods
		if err != nil && !common.Is(err, common.KeyNotFound) {
			return err
		}
		//If the RoundInfo is actually taken from the Store's DB, then it still
		//has not been processed by the Hashgraph consensus methods (The 'queued'
		//field is not exported and therefore not persisted in the DB).
		//RoundInfos taken from the DB directly will always have this field set
		//to false
		if !roundInfo.queued {
			h.UndecidedRounds = append(h.UndecidedRounds, roundNumber)
			roundInfo.queued = true
		}

		roundInfo.AddEvent(hash, witness)
		err = h.Store.SetRound(roundNumber, roundInfo)
		if err != nil {
			return err
		}
	}
	return nil
}

//decide if witnesses are famous
func (h *Hashgraph) DecideFame() error {
	votes := make(map[string](map[string]bool)) //[x][y]=>vote(x,y)

	decidedRounds := map[int]int{} // [round number] => index in h.UndecidedRounds
	defer h.updateUndecidedRounds(decidedRounds)

	for pos, i := range h.UndecidedRounds {
		roundInfo, err := h.Store.GetRound(i)
		if err != nil {
			return err
		}
		for _, x := range roundInfo.Witnesses() {
			if roundInfo.IsDecided(x) {
				continue
			}
		X:
			for j := i + 1; j <= h.Store.LastRound(); j++ {
				for _, y := range h.Store.RoundWitnesses(j) {
					diff := j - i
					if diff == 1 {
						setVote(votes, y, x, h.See(y, x))
					} else {
						//count votes
						ssWitnesses := []string{}
						for _, w := range h.Store.RoundWitnesses(j - 1) {
							if h.StronglySee(y, w) {
								ssWitnesses = append(ssWitnesses, w)
							}
						}
						yays := 0
						nays := 0
						for _, w := range ssWitnesses {
							if votes[w][x] {
								yays++
							} else {
								nays++
							}
						}
						v := false
						t := nays
						if yays >= nays {
							v = true
							t = yays
						}

						//normal round
						if math.Mod(float64(diff), float64(len(h.Participants))) > 0 {
							if t >= h.SuperMajority() {
								roundInfo.SetFame(x, v)
								setVote(votes, y, x, v)
								break X //break out of j loop
							} else {
								setVote(votes, y, x, v)
							}
						} else { //coin round
							if t >= h.SuperMajority() {
								setVote(votes, y, x, v)
							} else {
								setVote(votes, y, x, middleBit(y)) //middle bit of y's hash
							}
						}
					}
				}
			}
		}

		//Update decidedRounds and LastConsensusRound if all witnesses have been decided
		if roundInfo.WitnessesDecided() {
			decidedRounds[i] = pos

			if h.LastConsensusRound == nil || i > *h.LastConsensusRound {
				h.setLastConsensusRound(i)
			}
		}

		err = h.Store.SetRound(i, roundInfo)
		if err != nil {
			return err
		}
	}
	return nil
}

//remove items from UndecidedRounds
func (h *Hashgraph) updateUndecidedRounds(decidedRounds map[int]int) {
	newUndecidedRounds := []int{}
	for _, ur := range h.UndecidedRounds {
		if _, ok := decidedRounds[ur]; !ok {
			newUndecidedRounds = append(newUndecidedRounds, ur)
		}
	}
	h.UndecidedRounds = newUndecidedRounds
}

func (h *Hashgraph) setLastConsensusRound(i int) {
	if h.LastConsensusRound == nil {
		h.LastConsensusRound = new(int)
	}
	*h.LastConsensusRound = i

	h.LastCommitedRoundEvents = h.Store.RoundEvents(i - 1)
}

//assign round received and timestamp to all events
func (h *Hashgraph) DecideRoundReceived() error {
	for _, x := range h.UndeterminedEvents {
		r := h.Round(x)
		for i := r + 1; i <= h.Store.LastRound(); i++ {
			tr, err := h.Store.GetRound(i)
			if err != nil && !common.Is(err, common.KeyNotFound) {
				return err
			}

			//skip if some witnesses are left undecided
			if !(tr.WitnessesDecided() && h.UndecidedRounds[0] > i) {
				continue
			}

			fws := tr.FamousWitnesses()
			//set of famous witnesses that see x
			s := []string{}
			for _, w := range fws {
				if h.See(w, x) {
					s = append(s, w)
				}
			}
			if len(s) > len(fws)/2 {
				ex, err := h.Store.GetEvent(x)
				if err != nil {
					return err
				}
				ex.SetRoundReceived(i)

				t := []string{}
				for _, a := range s {
					t = append(t, h.OldestSelfAncestorToSee(a, x))
				}

				ex.consensusTimestamp = h.MedianTimestamp(t)

				err = h.Store.SetEvent(ex)
				if err != nil {
					return err
				}

				break
			}
		}
	}
	return nil
}

func (h *Hashgraph) FindOrder() error {
	err := h.DecideRoundReceived()
	if err != nil {
		return err
	}

	newConsensusEvents := []Event{}
	newUndeterminedEvents := []string{}
	for _, x := range h.UndeterminedEvents {
		ex, err := h.Store.GetEvent(x)
		if err != nil {
			return err
		}
		if ex.roundReceived != nil {
			newConsensusEvents = append(newConsensusEvents, ex)
		} else {
			newUndeterminedEvents = append(newUndeterminedEvents, x)
		}
	}
	h.UndeterminedEvents = newUndeterminedEvents

	sorter := NewConsensusSorter(newConsensusEvents)
	sort.Sort(sorter)

	for _, e := range newConsensusEvents {
		err := h.Store.AddConsensusEvent(e.Hex())
		if err != nil {
			return err
		}
		h.ConsensusTransactions += len(e.Transactions())
		if e.IsLoaded() {
			h.PendingLoadedEvents--
		}
	}

	if h.commitCh != nil && len(newConsensusEvents) > 0 {
		h.commitCh <- newConsensusEvents
	}

	return nil
}

func (h *Hashgraph) MedianTimestamp(eventHashes []string) time.Time {
	events := []Event{}
	for _, x := range eventHashes {
		ex, _ := h.Store.GetEvent(x)
		events = append(events, ex)
	}
	sort.Sort(ByTimestamp(events))
	return events[len(events)/2].Body.Timestamp
}

func (h *Hashgraph) ConsensusEvents() []string {
	return h.Store.ConsensusEvents()
}

//number of events per participants
func (h *Hashgraph) Known() map[int]int {
	return h.Store.Known()
}

func (h *Hashgraph) Reset(roots map[string]Root) error {
	if err := h.Store.Reset(roots); err != nil {
		return err
	}

	h.UndeterminedEvents = []string{}
	h.UndecidedRounds = []int{}
	h.PendingLoadedEvents = 0
	h.topologicalIndex = 0

	cacheSize := h.Store.CacheSize()
	h.ancestorCache = common.NewLRU(cacheSize, nil)
	h.selfAncestorCache = common.NewLRU(cacheSize, nil)
	h.oldestSelfAncestorCache = common.NewLRU(cacheSize, nil)
	h.stronglySeeCache = common.NewLRU(cacheSize, nil)
	h.parentRoundCache = common.NewLRU(cacheSize, nil)
	h.roundCache = common.NewLRU(cacheSize, nil)

	return nil
}

func (h *Hashgraph) GetFrame() (Frame, error) {
	lastConsensusRoundIndex := 0
	if lcr := h.LastConsensusRound; lcr != nil {
		lastConsensusRoundIndex = *lcr
	}

	lastConsensusRound, err := h.Store.GetRound(lastConsensusRoundIndex)
	if err != nil {
		return Frame{}, err
	}

	witnessHashes := lastConsensusRound.Witnesses()

	events := []Event{}
	roots := make(map[string]Root)
	for _, wh := range witnessHashes {
		w, err := h.Store.GetEvent(wh)
		if err != nil {
			return Frame{}, err
		}
		events = append(events, w)
		roots[w.Creator()] = Root{
			X:      w.SelfParent(),
			Y:      w.OtherParent(),
			Index:  w.Index() - 1,
			Round:  h.Round(w.SelfParent()),
			Others: map[string]string{},
		}

		participantEvents, err := h.Store.ParticipantEvents(w.Creator(), w.Index())
		if err != nil {
			return Frame{}, err
		}
		for _, e := range participantEvents {
			ev, err := h.Store.GetEvent(e)
			if err != nil {
				return Frame{}, err
			}
			events = append(events, ev)
		}
	}

	//Not every participant necessarily has a witness in LastConsensusRound.
	//Hence, there could be participants with no Root at this point.
	//For these partcipants, use their last known Event.
	for p := range h.Participants {
		if _, ok := roots[p]; !ok {
			var root Root
			last, isRoot, err := h.Store.LastFrom(p)
			if err != nil {
				return Frame{}, err
			}
			if isRoot {
				root, err = h.Store.GetRoot(p)
				if err != nil {
					return Frame{}, err
				}
			} else {
				ev, err := h.Store.GetEvent(last)
				if err != nil {
					return Frame{}, err
				}
				events = append(events, ev)
				root = Root{
					X:      ev.SelfParent(),
					Y:      ev.OtherParent(),
					Index:  ev.Index() - 1,
					Round:  h.Round(ev.SelfParent()),
					Others: map[string]string{},
				}
			}
			roots[p] = root
		}
	}

	sort.Sort(ByTopologicalOrder(events))

	//Some Events in the Frame might have other-parents that are outside of the
	//Frame (cf root.go ex 2)
	//When inserting these Events in a newly reset hashgraph, the CheckOtherParent
	//method would return an error because the other-parent would not be found.
	//So we make it possible to also look for other-parents in the creator's Root.
	treated := map[string]bool{}
	for _, ev := range events {
		treated[ev.Hex()] = true
		otherParent := ev.OtherParent()
		if otherParent != "" {
			opt, ok := treated[otherParent]
			if !opt || !ok {
				if ev.SelfParent() != roots[ev.Creator()].X {
					roots[ev.Creator()].Others[ev.Hex()] = otherParent
				}
			}
		}
	}

	frame := Frame{
		Roots:  roots,
		Events: events,
	}

	return frame, nil
}

//Bootstrap loads all Events from the Store's DB (if there is one) and feeds
//them to the Hashgraph (in topological order) for consensus ordering. After this
//method call, the Hashgraph should be in a state coeherent with the 'tip' of the
//Hashgraph
func (h *Hashgraph) Bootstrap() error {
	if badgerStore, ok := h.Store.(*BadgerStore); ok {
		//Retreive the Events from the underlying DB. They come out in topological
		//order
		topologicalEvents, err := badgerStore.dbTopologicalEvents()
		if err != nil {
			return err
		}

		//Insert the Events in the Hashgraph
		for _, e := range topologicalEvents {
			if err := h.InsertEvent(e, true); err != nil {
				return err
			}
		}

		//Compute the consensus order of Events
		if err := h.DivideRounds(); err != nil {
			return err
		}
		if err := h.DecideFame(); err != nil {
			return err
		}
		if err := h.FindOrder(); err != nil {
			return err
		}
	}

	return nil
}

func middleBit(ehex string) bool {
	hash, err := hex.DecodeString(ehex[2:])
	if err != nil {
		fmt.Printf("ERROR decoding hex string: %s\n", err)
	}
	if len(hash) > 0 && hash[len(hash)/2] == 0 {
		return false
	}
	return true
}

func setVote(votes map[string]map[string]bool, x, y string, vote bool) {
	if votes[x] == nil {
		votes[x] = make(map[string]bool)
	}
	votes[x][y] = vote

+/
}
