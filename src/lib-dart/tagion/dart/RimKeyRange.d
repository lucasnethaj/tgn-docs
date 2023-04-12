module tagion.dart.RimKeyRange;

import std.stdio;
import std.algorithm;
import std.range;
import std.traits;
import std.container.dlist;
import tagion.dart.Recorder;
import tagion.basic.Types : isBufferType;
import tagion.utils.Miscellaneous : hex;
import tagion.basic.Debug;

/++
 + Gets the rim key from a buffer
 +
 + Returns;
 +     fingerprint[rim]
 +/
@safe
ubyte rim_key(F)(F rim_keys, const uint rim) pure if (isBufferType!F) {
    if (rim >= rim_keys.length) {
        debug __write("%s rim=%d", rim_keys.hex, rim);
    }
    return rim_keys[rim];
}

@safe
RimKeyRange!Range rimKeyRange(Range)(Range range, const uint rim, const GetType get_type = Neutral)
        if (isInputRange!Range && isImplicitlyConvertible!(ElementType!Range, Archive)) {
    return RimKeyRange!Range(range, rim, get_type);
}

@safe
auto rimKeyRange(Rec)(Rec rec, const GetType get_type = Neutral)
        if (isImplicitlyConvertible!(Rec, const(RecordFactory.Recorder))) {
    return rimKeyRange(rec[], 0, get_type);
}

// Range over a Range with the same key in the a specific rim
@safe
struct RimKeyRange(Range) if (isInputRange!Range && isImplicitlyConvertible!(ElementType!Range, Archive)) {

    //alias Archives=RecordFactory.Recorder.Archives;
    protected DList!Archive added_archives;
    protected Range range;
    const ubyte rim_key;
    const uint rim;
    const GetType get_type;
    @disable this();
    version (none) protected this(Archive[] current) pure nothrow @nogc {
        this.current = current;
    }

    version (none) this(ref RimKeyRange range, const uint rim) {
        this.rim = rim;
        if (!range.empty) {
            rim_key = range.front.fingerprint.rim_key(rim);
            auto reuse_current = range.current;
            void build(ref RimKeyRange range, const uint no = 0) @safe {
                if (!range.empty && (range.front.fingerprint.rim_key(rim) is rim_key)) {
                    range.popFront;
                    build(range, no + 1);
                }
                else {
                    // Reuse the parent current
                    current = reuse_current[0 .. no];
                }
            }

            build(range);
        }
    }

    void add(Archive archive)
    in (rim_key == archive.fingerprint.rim_key(rim))
    do {
        added_archives.insertBack(archive);
    }

    private this(RimKeyRange rhs) {
        added_archives = rhs.added_archives.dup;
        range = rhs.range;
        rim_key = rhs.rim_key;
        rim = rhs.rim;
        get_type = rhs.get_type;
    }

    this(Range)(Range _range, const uint rim, const GetType get_type) {
        this.get_type = get_type;
        this.rim = rim;
        range = _range;
        if (!range.empty) {
            rim_key = range.front.fingerprint.rim_key(rim);
        }
    }

    /**
     * Checks if all the archives in the range are of the type REMOVE
     * Params:
     *   get_type = archive type get function
     * Returns: true if all the archives are removes
     */
    version (none) bool onlyRemove(const GetType get_type) const pure {
        return current
            .all!(a => get_type(a) is Archive.Type.REMOVE);
    }

    pure nothrow {
        /** 
             * Checks if the range only contains one archive 
             * Returns: true range if single
             */
        version (none) bool oneLeft() const @nogc {
            return length == 1;
        }

        /**
             * Checks if the range is empty
             * Returns: true if empty
             */
        bool empty() const @nogc {
            return range.empty && added_archives.empty;
        }

        alias archive_less = RecordFactory.Recorder.archive_sorted;
        /**
             *  Progress one archive
             */
        void popFront() {
            if (!added_archives.empty && !range.empty) {
                if (archive_less(added_archives.front, range.front)) {
                    added_archives.removeFront;
                }
                else {
                    range.popFront;
                }
            }
            else if (!range.empty) {
                range.popFront;
            }
            else if (!added_archives.empty) {
                added_archives.removeFront;
            }
        }

        /**
             * Gets the current archive in the range
             * Returns: current archive and return null if the range is empty
             */
        const(Archive) front() @nogc {
            if (!added_archives.empty && !range.empty) {
                if (archive_less(added_archives.front, range.front)) {
                    return added_archives.front;
                }
                return range.front;
            }
            if (!range.empty) {
                return range.front;
            }
            else if (!added_archives.empty) {
                return added_archives.front;
            }
            return Archive.init;
        }

        /**
             * Force the range to be empty
             */
        version (none) void force_empty() {
            current = null;
        }

        /**
             * Number of archive left in the range
             * Returns: size of the range
             */
        version (none) size_t length() const {
            return range.length + added_archives.length;
        }
    }
    /**
         *  Creates new range at the current position
         * Returns: copy of this range
         */
    RimKeyRange save() pure nothrow {

        return RimKeyRange(this);
    }

    static assert(isInputRange!RimKeyRange);
    static assert(isForwardRange!RimKeyRange);

}

@safe
unittest {
    import std.stdio;
    import tagion.dart.DARTFakeNet;

    const net = new DARTFakeNet;
    auto factory = RecordFactory(net);

    const table = [

        0xABCD_1334_5678_9ABCUL,
        0xABCD_1335_5678_9ABCUL,
        0xABCD_1336_5678_9ABCUL,

        // Archives which add added in to the RimKeyRange
        0xABCD_1334_AAAA_AAAAUL,
        0xABCD_1335_5678_AAAAUL,

    ];
    const documents = table
        .map!(t => DARTFakeNet.fake_doc(t))
        .array;

    { // Test with ADD's only
        writefln("--- RimKeyRange");
        // Create a recorder from the first 9 documents 
        auto rec = factory.recorder(documents.take(3), Archive.Type.ADD);
        { // Check the the rim-key range is the same as the recorder
            auto rim_key_range = rimKeyRange(rec);
            rec.dump;
            writeln("-- --- ");
            rim_key_range.each!q{a.dump};
            writeln("-- --- ");
            rim_key_range.each!q{a.dump};

            assert(equal(rec[].map!q{a.fingerprint}, rim_key_range.map!q{a.fingerprint}));
        }
        { // Add one to the rim_key range and check if it is range is ordered correctly
            auto rim_key_range = rimKeyRange(rec);
            auto rec_copy = rec.dup;
            rec_copy.insert(documents[3], Archive.Type.ADD);
            writefln("Recorder add 10");
            rec_copy.dump;
            rim_key_range.add(rec.archive(documents[3], Archive.Type.ADD));

            writefln("Recorder add 10");
            rim_key_range.save.each!q{a.dump};
            assert(equal(rec_copy[].map!q{a.fingerprint}, rim_key_range.map!q{a.fingerprint}));

        }

        { //  Add two to the rim_key range and check if it is range is ordered correctly
            auto rim_key_range = rimKeyRange(rec);
            auto rec_copy = rec.dup;

            rec_copy.insert(documents[3 .. 5], Archive.Type.ADD);
            writefln("Recorder add 11");
            rec_copy.dump;
            rim_key_range.add(rec.archive(documents[3], Archive.Type.ADD));
            rim_key_range.add(rec.archive(documents[4], Archive.Type.ADD));

            writefln("Recorder add 11");
            rim_key_range.save.each!q{a.dump};
            assert(equal(rec_copy[].map!q{a.fingerprint}, rim_key_range.map!q{a.fingerprint}));

        }
    }
}