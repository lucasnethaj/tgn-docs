
/// HashGraph Event
module tagion.hashgraph.Round;

//import std.stdio;

import std.datetime; // Date, DateTime
import std.exception : assumeWontThrow;
import std.conv;
import std.range;
import std.format;
import std.typecons;
import std.traits : Unqual, ReturnType;
import std.array : array;

import std.algorithm.sorting : sort;
import std.algorithm.iteration : map, each, filter, cache, fold, joiner, reduce;
import std.algorithm.searching : count, any, all, until, canFind;
import std.range.primitives : walkLength, isInputRange, isForwardRange, isBidirectionalRange;
import std.range : enumerate, tee;

import tagion.hibon.HiBON : HiBON;
import tagion.hibon.Document : Document;
import tagion.hibon.HiBONRecord;

import tagion.utils.Miscellaneous;
import tagion.utils.StdTime;

import tagion.basic.Types : Buffer;
import tagion.basic.basic : this_dot, basename, EnumText, buf_idup;
import tagion.crypto.Types : Pubkey;
import tagion.Keywords : Keywords;
import tagion.basic.Debug;

import tagion.logger.Logger;
import tagion.hashgraph.HashGraphBasic : isMajority, isAllVotes, higher, EventBody, EventPackage, EvaPayload, Tides;
import tagion.hashgraph.HashGraph : HashGraph;
import tagion.hashgraph.Event;
import tagion.hashgraphview.EventMonitorCallbacks;
import tagion.utils.BitMask : BitMask;

import std.typecons : No;

import std.traits;

import std.stdio;


/// Handles the round information for the events in the Hashgraph
@safe
class Round {
    //    bool erased;
    enum uint total_limit = 3;
    enum int coin_round_limit = 10;
    pragma(msg, "fixme(bbh) should be protected");
    protected {
        Round _previous;
        Round _next;
        bool _decided;
    }
    immutable int number;

    package Event[] _events;
    public BitMask famous_mask;

    /**
 * Compare the round number 
 * Params:
 *   rhs = round to be checked
 * Returns: true if equal or less than
 */
    @nogc bool lessOrEqual(const Round rhs) pure const nothrow {
        return (number - rhs.number) <= 0;
    }

    /**
     * Number of events in a round should be the same 
     * as the number of nodes in the hashgraph
     * Returns: number of nodes in the round 
     */
    @nogc const(uint) node_size() pure const nothrow {
        return cast(uint) _events.length;
    }

    /**
     * Construct a round from the previous round
     * Params:
     *   previous = previous round
     *   node_size = size of events in a round
     */
    private this(Round previous, const size_t node_size) pure nothrow {
        if (previous) {
            number = previous.number + 1;
            previous._next = this;
            _previous = previous;
        }
        else {
            number = -1;
        }
        _events = new Event[node_size];
    }

    /**
     * All the events in the first ooccurrences of this round
     * Returns: all events in a round
     */
    @nogc
    const(Event[]) events() const pure nothrow {
        return _events;
    }

    /**
     * Adds the even to round
     * Params:
     *   event = the event to be added
     */
    package void add(Event event) pure nothrow
    in {
        assert(_events[event.node_id] is null, "Event at node_id " ~ event.node_id.to!string ~ " should only be added once");
    }
    do {
        _events[event.node_id] = event;
        event._round = this;
    }

    /**
     * Check of the round has no events
     * Returns: true of the round is empty
     */
    @nogc
    bool empty() const pure nothrow {
        return !_events.any!((e) => e !is null);
    }

    /**
     * Counts the number of events which has been set in this round
     * Returns: number of events set
     */
    @nogc
    size_t event_count() const pure nothrow {
        return _events.count!((e) => e !is null);
    }

    /**
     * Remove the event from the round 
     * Params:
     *   event = event to be removed
     */
    @nogc
    package void remove(const(Event) event) nothrow
    in {
        assert(event.isEva || _events[event.node_id] is event,
        "This event does not exist in round at the current node so it can not be remove from this round");
        assert(event.isEva || !empty, "No events exists in this round");
    }
    do {
        if (!event.isEva && _events[event.node_id]) {
            _events[event.node_id] = null;
        }
    }

    /**
     * Scrap all rounds and events from this round and downwards 
     * Params:
     *   hashgraph = the hashgraph owning the events/rounds
     */
    @trusted
    private void scrap(HashGraph hashgraph)
    in {
        assert(!_previous, "Round can not be scrapped due that a previous round still exists");
    }
    do {
        uint count;
        void scrap_events(Event e) {
            if (e !is null) {
                count++;
                if (Event.callbacks) {
                    Event.callbacks.remove(e);
                }
                scrap_events(e._mother);
                e.disconnect(hashgraph);
                e.destroy;
            }
        }

        foreach (node_id, e; _events) {
            scrap_events(e);
        }
        if (_next) {
            _next._previous = null;
            _next = null;
        }
    }

    /**
     * Check if the round has been decided
     * Returns: true if the round has been decided
     */
    @nogc bool decided() const pure nothrow {
        return _decided;
    }

    const(Round) next() const pure nothrow {
        return _next;
    }

    /**
     * Get the event a the node_id 
     * Params:
     *   node_id = node id number
     * Returns: 
     *   Event at the node_id
     */
    @nogc
    inout(Event) event(const size_t node_id) pure inout {
        return _events[node_id];
    }

    /**
     * Previous round from this round
     * Returns: previous round
     */
    @nogc
    package Round previous() pure nothrow {
        return _previous;
    }

    @nogc
    const(Round) previous() const pure nothrow {
        return _previous;
    }

    /**
 * Range from this round and down
 * Returns: range of rounds 
 */
    @nogc
    package Rounder.Range!false opSlice() pure nothrow {
        return Rounder.Range!false(this);
    }

    /// Ditto
    @nogc
    Rounder.Range!true opSlice() const pure nothrow {
        return Rounder.Range!true(this);
    }

    invariant {
        assert(!_previous || (_previous.number + 1 is number));
        assert(!_next || (_next.number - 1 is number));
    }

    /**
     * The rounder takes care of cleaning up old round 
     * and keeps track of if an round has been decided or can be decided
     */
    struct Rounder {
        Round last_round;
        Round last_decided_round;
        HashGraph hashgraph;
        Round[] voting_round_per_node;
        Event[] consensus_tide;

        @disable this();

        this(HashGraph hashgraph) pure nothrow {
            this.hashgraph = hashgraph;
            consensus_tide = new Event[hashgraph.node_size];
            last_round = new Round(null, hashgraph.node_size);
            voting_round_per_node = last_round.repeat(hashgraph.node_size).array;
        }

        package void erase() {
            void local_erase(Round r) @trusted {
                if (r !is null) {
                    local_erase(r._previous);
                    r.scrap(hashgraph);
                    r.destroy;
                }
            }

            Event.scrapping = true;
            scope (exit) {
                Event.scrapping = false;
            }
            last_decided_round = null;
            local_erase(last_round);
        }

        //Cleans up old round and events if they are no-longer needed

        package
        void dustman() {
            void local_dustman(Round r) {
                if (r !is null) {
                    local_dustman(r._previous);
                    r.scrap(hashgraph);
                }
            }

            Event.scrapping = true;
            scope (exit) {
                Event.scrapping = false;
            }
            if (hashgraph.scrap_depth != 0) {
                int depth = hashgraph.scrap_depth;
                for (Round r = last_decided_round; r !is null; r = r._previous) {
                    depth--;
                    if (depth < 0) {
                        local_dustman(r);
                        break;
                    }
                }
            }
        }

        /**
  * Number of round epoch in the rounder queue
  * Returns: size of the queue
   */
        @nogc
        size_t length() const pure nothrow {
            return this[].walkLength;
        }

        /**
     * Number of the same as hashgraph
     * Returns: number of nodes
     */
        uint node_size() const pure nothrow
        in {
            assert(last_round, "Last round must be initialized before this function is called");
        }
        do {
            return cast(uint)(last_round._events.length);

        }

        /**
     * Sets the round for an event and creates an new round if needed
     * Params:
     *   e = event
     */
        void next_round(Event e) nothrow
        in {
            assert(last_round, "Base round must be created");
            assert(last_decided_round, "Last decided round must exist");
            assert(e, "Event must create before a round can be added");
        }
        out {
            assert(e._round !is null);
        }
        do {
            scope (exit) {
                e._round.add(e);
            }
            if (e._round && e._round._next) {
                e._round = e._round._next;
            }
            else {
                e._round = new Round(last_round, hashgraph.node_size);
                last_round = e._round;
                // if (Event.callbacks) {
                //     Event.callbacks.round_seen(e);
                // }
            }
        }

        bool isEventInLastDecidedRound(const(Event) event) const pure nothrow @nogc {
            if (!last_decided_round) {
                return false;
            }

            return last_decided_round.events
                .filter!((e) => e !is null)
                .map!(e => e.event_package.fingerprint)
                .canFind(event.event_package.fingerprint);
        }

        /**
     * Check of a round has been decided
     * Params:
     *   test_round = round to be tested
     * Returns: 
     */
        @nogc
        bool decided(const Round test_round) pure const nothrow {
            bool _decided(const Round r) pure nothrow {
                if (r) {
                    if (test_round is r) {
                        return true;
                    }
                    return _decided(r._next);
                }
                return false;
            }

            return _decided(last_decided_round);
        }

        /**
     * Calculates the number of rounds since the last decided round
     * Returns: number of undecided roundes 
     */
        @nogc
        int coin_round_distance() pure const nothrow {
            return last_round.number - last_decided_round.number;
        }

        /**
     * Number of decided round in cached in memory
     * Returns: Number of cached dicided rounds
     */
        @nogc
        uint cached_decided_count() pure const nothrow {
            uint _cached_decided_count(const Round r, const uint i = 0) pure nothrow {
                if (r) {
                    return _cached_decided_count(r._previous, i + 1);
                }
                return i;
            }

            return _cached_decided_count(last_round);
        }

        /**
     * Check the coin round limit
     * Returns: true if the coin round has beed exceeded 
     */
        @nogc
        bool check_decided_round_limit() pure const nothrow {
            return cached_decided_count > total_limit;
        }

        void check_decide_round() {
            auto round_to_be_decided = last_decided_round._next;
            if (!voting_round_per_node.all!(r => r.number > round_to_be_decided.number)) {
                return;
            }
            collect_received_round(round_to_be_decided, hashgraph);
            round_to_be_decided._decided = true;
            last_decided_round = round_to_be_decided;
            // if (hashgraph._rounds.voting_round_per_node.all!(r => r.number > round_to_be_decided.number)
            // {
            //     check_decided_round(hashgraph);        
            // } 
        }

        /**
     * Call to collect and order the epoch
     * Params:
     *   r = decided round to collect events to produce the epoch
     *   hashgraph = hashgraph which ownes this rounds
     */
        version(none)
        package void collect_received_round(Round r, HashGraph hashgraph) {
            scope Event[] new_consensus_tide = r._events.dup();
            foreach(famous_event; r._events.filter!(e => e.witness.famous_mask[e.node_id])) {
                famous_event._youngest_ancestors
                    .filter!(e => e !is null)
                    .filter!(e => higher(new_consensus_tide[e.node_id].received_order, e.received_order))
                    .each!(e => new_consensus_tide[e.node_id] = e);
            }

                        
            scope (success) {
                with (hashgraph) {
                    mark_received_statistic(mark_received_iteration_count);
                    mixin Log!(mark_received_statistic);
                    order_compare_statistic(order_compare_iteration_count);
                    mixin Log!(order_compare_statistic);
                    epoch_events_statistic(epoch_events_count);
                    mixin Log!(epoch_events_statistic);
                }
            }
            
             
        }
        
        // version(none)
        package void collect_received_round(Round r, HashGraph hashgraph) {
            Event[] new_consensus_tide = r._events.dup();
            foreach(famous_event; r._events.filter!(e => e !is null && r.famous_mask[e.node_id]))
            {
                famous_event._youngest_ancestors
                    .filter!(e => e !is null)
                    .filter!(e => new_consensus_tide[e.node_id] is null || higher(new_consensus_tide[e.node_id].received_order, e.received_order))
                    .each!(e => new_consensus_tide[e.node_id] = e);
            }

            foreach(i;0 .. hashgraph.node_size) {
                if (new_consensus_tide[i] is null) { continue; }
                while(!new_consensus_tide[i]._son)
                {
                    new_consensus_tide[i] = new_consensus_tide[i]._daughter;
                }
            }
            if (hashgraph.__debug_print) {
                __write("round: %s, consensus_tide %s", r.number, new_consensus_tide.filter!(e => e !is null).map!(e => e.id));
            }
            auto event_collection = new_consensus_tide.map!(e => e[]
                    .until!(e => e._round_received !is null))
                .joiner.array;

            foreach(event; event_collection) {
                event._round_received = r;
            }

            consensus_tide = new_consensus_tide;
            
            // if (hashgraph.__debug_print) {
            //     __write("testingd: %s", new_consensus_tide.filter!(e => e !is null).map!(e => e.id));
            // }
            // uint mark_received_iteration_count;
            // uint order_compare_iteration_count;
            // uint rare_order_compare_count;
            // uint epoch_events_count;
            // // uint count;
            // scope (success) {
            //     with (hashgraph) {
            //         mark_received_statistic(mark_received_iteration_count);
            //         mixin Log!(mark_received_statistic);
            //         order_compare_statistic(order_compare_iteration_count);
            //         mixin Log!(order_compare_statistic);
            //         epoch_events_statistic(epoch_events_count);
            //         mixin Log!(epoch_events_statistic);
            //     }
            // }
            // r._events
            //     .filter!((e) => (e !is null))
            //     .each!((e) => e[]
            //     .until!((e) => (e._round_received !is null))
            //     .each!((ref e) => e._round_received_mask.clear));

            // void mark_received_events(const size_t voting_node_id, Event e) {
            //     mark_received_iteration_count++;
            //     if ((e) && (!e._round_received) && !e._round_received_mask[voting_node_id]) { // && !marker_mask[e.node_id] ) {
            //         e._round_received_mask[voting_node_id] = true;
            //         mark_received_events(voting_node_id, e._father);
            //         mark_received_events(voting_node_id, e._mother);
            //     }
            // }
            // // Marks all the event below round r
            // r._events
            //     .filter!((e) => (e !is null))
            //     .each!((ref e) => mark_received_events(e.node_id, e));

            // // writefln("r._events=%s", r._events.count!((e) => e !is null && e.isFamous));
            // auto event_collection = r._events
            //     .filter!((e) => (e !is null))
            //     .filter!((e) => !hashgraph.excluded_nodes_mask[e.node_id])
            //     .map!((ref e) => e[]
            //     .until!((e) => (e._round_received !is null))
            //     .filter!((e) => (e._round_received_mask.isMajority(hashgraph))))
            //     .joiner
            //     .tee!((e) => e._round_received = r)
            //     .array;

            // // writefln("event_collection=%s", event_collection.count!((e) => e !is null && e.isFamous));
            hashgraph.epoch(event_collection, r);
        }

        package void vote(HashGraph hashgraph, size_t vote_node_id) {
            voting_round_per_node[vote_node_id] = voting_round_per_node[vote_node_id]._next;
            Round current_round = voting_round_per_node[vote_node_id];
            if (voting_round_per_node.all!(r => !higher(current_round.number, r.number))) {
                check_decide_round();
            }

            while (current_round._next !is null) {
                current_round = current_round._next;
                foreach (e; current_round._events.filter!(e => e !is null)) {
                    e.calc_vote(hashgraph, vote_node_id);
                }
            }
        }

        /**
     * Range from this round and down
     * Returns: range of rounds 
     */
        @nogc
        package Range!false opSlice() pure nothrow {
            return Range!false(last_round);
        }

        /// Ditto
        @nogc
        Range!true opSlice() const pure nothrow {
            return Range!true(last_round);
        }

        /**
     * Range of rounds 
     */
        @nogc
        struct Range(bool CONST = true) {
            private Round round;
            @trusted
            this(const Round round) pure nothrow {
                this.round = cast(Round) round;
            }

            pure nothrow {
                static if (CONST) {
                    const(Round) front() const {
                        return round;
                    }
                }
                else {
                    Round front() {
                        return round;
                    }
                }

                alias back = front;

                bool empty() const {
                    return round is null;
                }

                void popBack() {
                    round = round._next;
                }

                void popFront() {
                    round = round._previous;
                }

                Range save() {
                    return Range(round);
                }

            }

        }

        static assert(isInputRange!(Range!true));
        static assert(isForwardRange!(Range!true));
        static assert(isBidirectionalRange!(Range!true));
    }

}
