/// Block files system (file system support for DART)
module tagion.dart.BlockFile;

import console = std.stdio;

import std.path : setExtension;
import std.bitmanip : binwrite = write, binread = read;
import std.stdio;
import std.file : remove, rename;
import std.typecons;
import std.algorithm.sorting : sort;
import std.algorithm.searching : until;
import std.algorithm.mutation : SwapStrategy;
import std.algorithm.iteration : filter, each, map;

import std.array : array, join;
import std.datetime;
import std.format;
import std.conv : to;
import std.traits;
import std.exception : assumeUnique, assumeWontThrow;
import std.container.rbtree : RedBlackTree, redBlackTree;

import tagion.basic.Types : Buffer, FileExtension;
import tagion.basic.Basic : basename, log2, assumeTrusted;
import tagion.basic.TagionExceptions : Check;

import tagion.hibon.HiBON : HiBON;
import tagion.hibon.Document : Document;
import tagion.hibon.HiBONRecord;
import tagion.logger.Statistic;
import tagion.dart.DARTException : BlockFileException;
import tagion.dart.Recycler : Recycler;
import tagion.dart.BlockSegment;

//import tagion.dart.BlockSegmentAllocator;

import std.math : rint;

alias Index = Typedef!(ulong, ulong.init, "BlockIndex");
enum INDEX_NULL = Index.init;
enum BLOCK_SIZE = 0x80;

version (unittest) {
    import Basic = tagion.basic.Basic;

    enum random = false;

    const(Basic.FileNames) fileId(T = BlockFile)(string prefix = null) @safe {
        return Basic.fileId!T(FileExtension.dart, prefix);
    }
}
else {
    enum random = true;
}

version (none) {
    /// Dummy code Should be removed when the in the new recycler
    @safe
    RecycleIndices.Segments update_segments(ref Recycler recycler, bool segments_needs_saving = false) {
        // Find continues segments of blocks
        return new RecycleIndices.Segments;
    }

    @safe
    void trim_last_block_index(ref Recycler recycler, ref scope BlockFile.Block[Index] blocks) {
        ///void trim_last_block_index);
    }
}

extern (C) {
    int ftruncate(int fd, long length);
}

// File object does not support yet truncate so the generic C function is used
@trusted
void truncate(ref File file, long length) {
    ftruncate(file.fileno, length);
}

alias check = Check!BlockFileException;

/// Block file operation
@safe
class BlockFile {
    enum FILE_LABEL = "DART:0.0";
    enum DEFAULT_BLOCK_SIZE = 0x40;
    immutable uint BLOCK_SIZE;
    //immutable uint DATA_SIZE;
    alias BlockFileStatistic = Statistic!(uint, Yes.histogram);
    static bool do_not_write;
    package {
        File file;
        Index _last_block_index;
    }
    protected {
        Recycler recycler;
        MasterBlock masterblock;
        HeaderBlock headerblock;
        bool hasheader;
        BlockFileStatistic _statistic;
    }

    Index last_block_index() const pure nothrow @nogc {
        return _last_block_index;
    }

    const(BlockFileStatistic) statistic() const pure nothrow @nogc {
        return _statistic;
    }

    bool isRecyclable(const Index index) const pure nothrow {
        return recycler.isRecyclable(index);
    }

    void recycleDump() {
        recycler.dump;
    }

    protected this(
            string filename,
            immutable uint SIZE,
            const bool read_only = false) {
        File _file;

        if (read_only) {
            _file.open(filename, "r");
        }
        else {
            _file.open(filename, "r+");
        }
        this(_file, SIZE);
    }

    protected this(
            File file,
            immutable uint SIZE) {
        this.BLOCK_SIZE = SIZE;
        //   DATA_SIZE = BLOCK_SIZE - Block.HEADER_SIZE;
        this.file = file;
        recycler = Recycler(this);
        readInitial;
    }

    /**
       Used by the Inspect
    */
    protected this(immutable uint SIZE) pure nothrow {
        this.BLOCK_SIZE = SIZE;
        //  DATA_SIZE = BLOCK_SIZE - Block.HEADER_SIZE;
        recycler = Recycler(this);
    }

    static BlockFile Inspect(
            string filename,
            void delegate(string msg) @safe report,
            const uint max_iteration = uint.max) {
        BlockFile result;
        void try_it(void delegate() @safe dg) {
            try {
                dg();
            }
            catch (BlockFileException e) {
                report(e.msg);
            }
        }

        try_it({
            File _file;
            _file.open(filename, "r");
            BlockFile.HeaderBlock _headerblock;
            _file.seek(0);
            _headerblock.read(_file, DEFAULT_BLOCK_SIZE);
            result = new BlockFile(_headerblock.block_size);
            result.file = _file;
        });
        if (result.file.size == 0) {
            report(format("BlockFile %s size is 0", filename));
        }
        if (result) {
            try_it(&result.readHeaderBlock);
            result._last_block_index--;
            try_it(&result.readMasterBlock);
            try_it(&result.readStatistic);
            result.recycler = Recycler(result);
            //result.recycle_indices.max_iteration = max_iteration;
            //try_it(&result.recycle_indices.read);
        }
        return result;
    }
    /++
     Creates and empty BlockFile

     Params:
     $(LREF finename)    = File name of the BlockFile.
     If file exists with the same name this file will be overwritten
     $(LREF description) = This text will be written into the header
     $(LREF BLOCK_SIZE)  = Set the block size of the underlining BlockFile

     +/
    static void create(string filename, string description, immutable uint BLOCK_SIZE) {
        auto _file = File(filename, "w+");
        auto blockfile = new BlockFile(_file, BLOCK_SIZE);
        scope (exit) {
            blockfile.close;
        }
        blockfile.createHeader(description);
        blockfile.writeMasterBlock;
    }

    static BlockFile reset(string filename) {
        immutable old_filename = filename.setExtension("old");
        filename.rename(old_filename);
        auto old_blockfile = BlockFile(old_filename);
        old_blockfile.readStatistic;

        auto _file = File(filename, "w+");
        auto blockfile = new BlockFile(_file, old_blockfile.headerblock.block_size);
        blockfile.headerblock = old_blockfile.headerblock;
        blockfile._statistic = old_blockfile._statistic;
        blockfile.headerblock.write(_file);
        blockfile._last_block_index = 1;
        blockfile.masterblock.write(_file, blockfile.BLOCK_SIZE);
        blockfile.hasheader = true;
        blockfile.store;
        return blockfile;
    }
    /++
     + Opens an existing file which previously was created by BlockFile.create
     +
     + Params:
     +     filename  = Name of the blockfile
     +     read_only = If `true` the file is opened as read-only
     +/
    static BlockFile opCall(string filename, const bool read_only = false) {
        auto temp_file = new BlockFile(filename, DEFAULT_BLOCK_SIZE, read_only);
        immutable SIZE = temp_file.headerblock.block_size;
        temp_file.close;
        return new BlockFile(filename, SIZE, read_only);
    }

    /++
     +/
    void close() {
        file.close;
    }

    ~this() {
        file.close;
    }

    protected void createHeader(string name) {
        check(!hasheader, "Header is already created");
        check(file.size == 0, "Header can not be created the file is not empty");
        check(name.length < headerblock.id.length, format("Id is limited to a length of %d but is %d", headerblock
                .id.length, name.length));
        headerblock.label[0 .. FILE_LABEL.length] = FILE_LABEL;
        headerblock.block_size = BLOCK_SIZE;
        headerblock.id[0 .. name.length] = name;
        headerblock.create_time = Clock.currTime.toUnixTime!long;
        headerblock.write(file);
        _last_block_index = 1;
        masterblock.write(file, BLOCK_SIZE);
        hasheader = true;
    }

    /++
     + Returns:
     +     `true` of the file blockfile has a header
     +/
    bool hasHeader() const pure nothrow {
        return hasheader;
    }

    protected void readInitial() {
        if (file.size > 0) {
            readHeaderBlock;
            _last_block_index--;
            readMasterBlock;
            readStatistic;
            recycler.read(masterblock.recycle_header_index);
        }
    }

    pragma(msg, "fixme(cbr): The Statistic here should use tagion.utils.Statistic");
    enum Limits : double {
        MEAN = 10,
        SUM = 100
    }

    protected bool check_statistic(const uint total_blocks, const uint blocks) pure const {
        if (blocks > total_blocks) {
            return false;
        }
        else if (_statistic.contains(blocks) || (total_blocks >= 2 * blocks)) {
            return true;
        }
        else {
            auto r = _statistic.result;
            if (r.mean > Limits.MEAN) {
                immutable limit = (r.mean - r.sigma);
                if (blocks > limit) {
                    immutable remain_blocks = total_blocks - blocks;
                    if (_statistic.contains(remain_blocks) || (remain_blocks > r.mean)) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    /++
     + The HeaderBlock is the first block in the BlockFile
     +/
    @safe
    struct HeaderBlock {
        enum ID_SIZE = 32;
        enum LABEL_SIZE = 16;
        char[LABEL_SIZE] label; /// Label to set the BlockFile type
        uint block_size; /// Size of the block's
        long create_time; /// Time of creation
        char[ID_SIZE] id; /// Short description string

        void write(ref File file) const @trusted
        in {
            assert(block_size >= HeaderBlock.sizeof);
        }
        do {
            auto buffer = new ubyte[block_size];
            size_t pos;
            foreach (i, m; this.tupleof) {
                alias type = typeof(m);
                static if (isStaticArray!type) {
                    buffer[pos .. pos + type.sizeof] = (cast(ubyte*) id.ptr)[0 .. type.sizeof];
                    pos += type.sizeof;
                }
                else {
                    buffer.binwrite(m, &pos);
                }
            }
            assert(!BlockFile.do_not_write, "Should not write here");
            file.rawWrite(buffer);
        }

        void read(ref File file, immutable uint BLOCK_SIZE) @trusted
        in {
            assert(BLOCK_SIZE >= HeaderBlock.sizeof);
        }
        do {

            auto buffer = new ubyte[BLOCK_SIZE];
            auto buf = file.rawRead(buffer);
            foreach (i, ref m; this.tupleof) {
                alias type = typeof(m);
                static if (isStaticArray!type && is(type : U[], U)) {
                    m = (cast(U*) buf.ptr)[0 .. m.sizeof];
                    buf = buf[m.sizeof .. $];
                }
                else {
                    m = buf.binread!type;
                }
            }
        }

        string toString() const {
            return [
                "Header Block",
                format("Label      : %s", label[].until(char(ubyte.max))),
                format("ID         : %s", id[].until(char.max)),
                format("Block size : %d", block_size),
                format("Created    : %s", SysTime.fromUnixTime(create_time).toSimpleString),
            ].join("\n");
        }

    }

    final Index lastBlockIndex() const pure nothrow {
        return _last_block_index;
    }

    final package void seek(const Index index) {
        file.seek(index_to_seek(index));
    }

    /++
     + The MasterBlock is the last block in the BlockFile
     + This block maintains the indices to of other block
     +/

    @safe
    static struct MasterBlock {
        Index recycle_header_index; /// Points to the root of recycle block list
        //Index first_index; /// Points to the first block of data
        Index root_index; /// Point the root of the database
        Index statistic_index; /// Points to the statistic data
        final void write(
                ref File file,
                immutable uint BLOCK_SIZE) const @trusted {
            auto buffer = new ubyte[BLOCK_SIZE];
            size_t pos;
            foreach (i, m; this.tupleof) {
                alias type = TypedefType!(typeof(m));
                buffer.binwrite(cast(type) m, &pos);
            }
            buffer[$ - FILE_LABEL.length .. $] = cast(ubyte[]) FILE_LABEL;
            assert(!BlockFile.do_not_write, "Should not write here");
            file.rawWrite(buffer);
            // Truncate the file after the master block
            file.truncate(file.size);
            file.sync;
        }

        final void read(ref File file, immutable uint BLOCK_SIZE) {
            auto buffer = new ubyte[BLOCK_SIZE];
            auto buf = file.rawRead(buffer);
            foreach (i, ref m; this.tupleof) {
                alias type = TypedefType!(typeof(m));
                m = buf.binread!type;
            }
        }

        string toString() const pure nothrow {
            return assumeWontThrow([
                "Master Block",
                format("Root       @ %d", root_index),
                //       format("First      @ %d", first_index),
                format("Recycle    @ %d", recycle_header_index),
                format("Statistic  @ %d", statistic_index),
            ].join("\n"));

        }
    }

    /++
     + Sets the database root index
     +
     + Params:
     +     index = Root of the database
     +/
    void root_index(const Index index)
    in {
        assert(index > 0 && index < _last_block_index);
    }
    do {
        masterblock.root_index = Index(index);
    }

    Index root_index() const pure nothrow {
        return masterblock.root_index;
    }

    /++
     + Params:
     +     size = size of data bytes
     +
     + Returns:
     +     The number of blocks used to allocate size bytes
     +/
    uint number_of_blocks(const size_t size) const pure nothrow {
        return cast(uint)((size / BLOCK_SIZE) + ((size % BLOCK_SIZE == 0) ? 0 : 1));
    }

    /++
     + Params:
     +      index = Block index pointer
     +
     + Returns:
     +      the file pointer in byte counts
     +/
    ulong index_to_seek(const Index index) const pure nothrow {
        return BLOCK_SIZE * cast(ulong) index;
    }

    protected void writeStatistic() {
        // Allocate block for statistical data
        immutable old_statistic_index = masterblock.statistic_index;

        auto statistical_allocate = save(_statistic.toDoc, random);
        masterblock.statistic_index = Index(statistical_allocate.index);
        if (old_statistic_index !is INDEX_NULL) {
            // The old statistic block is erased
            erase(old_statistic_index);
        }
    }

    ref const(MasterBlock) masterBlock() pure const nothrow {
        return masterblock;
    }

    ref const(HeaderBlock) headerBlock() pure const nothrow {
        return headerblock;
    }

    // Write the master block to the filesystem and truncate the file
    protected void writeMasterBlock() {
        seek(_last_block_index);
        masterblock.write(file, BLOCK_SIZE);
    }

    private void readHeaderBlock() {
        check(file.size % BLOCK_SIZE == 0,
                format("BlockFile should be sized in equal number of blocks of the size of %d but the size is %d", BLOCK_SIZE, file
                .size));
        _last_block_index = cast(Index)(file.size / BLOCK_SIZE);
        check(_last_block_index > 1, format("The BlockFile should at least have a size of two block of %d but is %d", BLOCK_SIZE, file
                .size));
        // The headerblock is locate in the start of the file
        seek(INDEX_NULL);
        headerblock.read(file, BLOCK_SIZE);
        hasheader = true;
    }

    private void readMasterBlock() {
        // The masterblock is locate as the lastblock in the file
        seek(_last_block_index);
        masterblock.read(file, BLOCK_SIZE);
    }

    private void readStatistic() @safe {
        if (masterblock.statistic_index !is INDEX_NULL) {
            immutable buffer = load(masterblock.statistic_index);
            _statistic = BlockFileStatistic(Document(buffer));
        }
    }

    /++
     + Loads a chain of blocks from the filesystem starting from index
     + This function will not load data in BlockSegment list
     + The allocated chain list has to be stored first
     +
     + Params:
     +     index = Points to an start block in the chain of blocks
     +
     + Returns:
     +     Buffer of all data in the chain of blocks
     +
     + Throws:
     +     BlockFileException if this not first block in a chain or
     +     some because of some other failures in the blockfile system
     +/
    const(Document) load(const Index index, const bool check_format = true) {
        //auto first_block = read(index);
        // Check if this is the first block is the start of a block sequency
        version (none)
            check(check_format || first_block.head, format(
                    "Block @ %d is not the head of block sequency", index));
        version (none) Buffer build_sequency(Block block) @safe {
            scope buffer = new ubyte[first_block.size];
            auto cache = buffer;
            Index current_index = Index(index + 1);
            while (block.size > DATA_SIZE) {
                cache[0 .. DATA_SIZE] = block.data;
                auto next_block = read(current_index);
                check(next_block !is null, format("Fatal error in the blockfile @ %s", current_index));
                version (none)
                    check(check_format || !next_block.head, format(
                            "Block @ %d is marked as head of block sequency but it should not be", index));
                block = next_block;
                cache = cache[DATA_SIZE .. $];
                current_index++;
            }

            {
                check(check_format || block.size !is 0, format("Block @ %d has the size zero", index));
                cache[0 .. block.size] = block.data[0 .. block.size];
            }
            return buffer.idup;
        }

        //return Document(build_sequency(first_block));
        return BlockSegment(this, index).doc;
    }

    T load(T)(const Index index) if (isHiBONRecord!T) {
        const doc = load(index);
        check(isRecord!T(doc), format("The loaded document is not a %s record", T.stringof));
        return T(doc);
    }

    Document cacheLoad(const Index index) nothrow {
        if (index == 0) {
            return Document.init;
        }
        auto allocated_range = allocated_chains.filter!(a => a.index == index);
        if (!allocated_range.empty) {
            return allocated_range.front.doc;
        }

        return assumeWontThrow(load(index));
    }

    T cacheLoad(T)(const T rec, const Index index) if (isHiBONRecord!T) {
        const doc = cacheLoad(index);
        check(isRecord!T(doc), format("The loaded document is not a %s record", T.stringof));
        return T(doc);
    }
    /++
     + Marks a chain for blocks as erased
     + This function does actually erease the block before the store method is called
     + The list of recyclable block also be update after the store method has been called
     +
     + This prevents it from danaging the BlockFile until a sequency of operations has been performed
     +
     + Params:
     +     index = Points to an start block in the chain of blocks
     +
     + Returns:
     +     Begin to the next block sequency in the
     + Throws:
     +     BlockFileException
     +
     +/
    Index erase(const Index index) {
        // Should be implement with new recycler
        return INDEX_NULL;
    }

    version (none) Index end_index(const Index index) {
        @safe Index search(const Index index) {
            if (index !is INDEX_NULL) {
                const block = read(index);
                check(block.size > 0,
                        format("Bad data block @ %d the size is zero", index));
                if (block.size > DATA_SIZE) {
                    return search(block.next);
                }
                else {
                    return block.next;
                }
            }
            return INDEX_NULL;
        }

        return search(index);
    }

    protected Index reserve(const size_t size) nothrow {
        const nblocks = number_of_blocks(size);
        _statistic(nblocks);
        return Index(recycler.reserve_segment(nblocks));
    }

    protected const(BlockSegment)*[] allocated_chains;

    /++
     + Allocates new data block
     + Does not acctually update the BlockFile just reserves new block's
     +
     + Params:
     +     data = Data buffer to be reserved and allocated
     +/
    const(BlockSegment*) save(const(Document) doc, bool random_block = random) {
        auto result = new const(BlockSegment)(doc, reserve(doc.full_size));

        allocated_chains ~= result;
        return result;

    }
    /// Dito
    const(BlockSegment*) save(T)(const T rec) if (isHiBONRecord!T) {
        return save(rec.toDoc);
    }
    /++
     +
     + This function will erase, write, update the BlockFile and update the recyle bin
     + Stores the list of BlockSegment to the disk
     + If this function throws an Exception the Blockfile has not been updated
     +
     +/
    void store() {
       writeStatistic;
        scope (success) {
            allocated_chains = null;
            version (none)
                recycler.write;
            writeMasterBlock;
        }

        foreach (block_segment; sort!(q{a.index < b.index}, 
            SwapStrategy.unstable)(allocated_chains)) {
            block_segment.write(this);
        }
    }

    /++
     + Fail type for the inspect function
     +/
    enum Fail {
        NON = 0, /// No error detected in this Block
        RECURSIVE, /// Block links is recursive
        INCREASING, /// The next pointer should be greater than the block index
        SEQUENCY, /**
                     Block size in a sequency should be decreased by Block.DATA_SIZE
                     between the current and the next block in a sequency
                  */
        LINK, /// Blocks should be double linked
        ZERO_SIZE, /// The size of Recycled block should be zero
        BAD_SIZE, /** Bad size means that a block is not allowed to have a size larger than DATA_SIZE
                       if the next block is a head block
                   */
        RECYCLE_HEADER, /// Recycle block should not contain a header mask
        RECYCLE_NON_ZERO, /// The size of an recycle block should be zero

    }

    /++
     + Check the BlockFile
     +
     + Params:
     +     fail  = is callback delegate which will be call when a Fail is detected
     +     index  = Point to the block in the BlockFile
     +     f      = is the Fail code
     +     block  = is the failed block
     +     data_flag = Set to `false` if block is a resycled block and `true` if it a data block
     +/
    bool inspect(bool delegate(
            const Index index,
            const Fail f,
            const bool recycle_chain) @safe trace) {
        scope bool[Index] visited;
        scope bool end;
        bool failed;
        version (none) @safe
        void check_data(bool check_recycle_mode)(ref BlockRange r) {
            Block previous;
            while (!r.empty && !end) {
                auto current = r.front;
                if ((r.index in visited) && (r.index !is INDEX_NULL)) {
                    failed = true;
                    end |= trace(r.index, Fail.RECURSIVE, current, check_recycle_mode);
                }
                visited[r.index] = true;
                static if (!check_recycle_mode) {
                    if (current.size == 0) {
                        failed = true;
                        end |= trace(r.index, Fail.ZERO_SIZE, current, check_recycle_mode);
                    }
                }
                version (none)
                    if (previous) {
                        if (current.previous >= r.index) {
                            failed = true;
                            end |= trace(r.index, Fail.INCREASING, current, check_recycle_mode);
                        }
                        static if (check_recycle_mode) {
                            version (none)
                                if (current.head) {
                                    failed = true;
                                    end |= trace(r.index, Fail.RECYCLE_HEADER, current, check_recycle_mode);
                                }
                            if (current.size != 0) {
                                failed = true;
                                end |= trace(r.index, Fail.RECYCLE_NON_ZERO, current, check_recycle_mode);
                            }
                        }
                        else {
                            if (!current.head) {
                                if (previous.size != current.size + DATA_SIZE) {
                                    failed = true;
                                    end |= trace(r.index, Fail.SEQUENCY, current, check_recycle_mode);
                                }
                            }
                            else if (previous.size > DATA_SIZE) {
                                end |= trace(current.previous, Fail.BAD_SIZE, previous, check_recycle_mode);
                            }
                        }
                        if (r.index != previous.next) {
                            failed = true;
                            end |= trace(r.index, Fail.LINK, current, check_recycle_mode);
                        }

                    }
                if (!failed) {
                    end |= trace(r.index, Fail.NON, current, check_recycle_mode);
                }
                previous = r.front;
                r.popFront;
            }
        }

        version (none) {
            BlockRange r = blockRange;
            check_data!false(r);
        }
        return failed;
    }

   enum BlockSymbol {
        file_header = 'H',
        header = 'h',
        empty = '_',
        recycle = 'X',
        data = '#',
        none_existing = 'Z',

    }

   /++
     + Used for debuging only to dump the Block's
     +/
    void dump(const uint block_per_line = 16) {
        auto line = new char[block_per_line];
        version (none)
            foreach (index; 0 .. ((_last_block_index / block_per_line) + (
                    (_last_block_index % block_per_line == 0) ? 0 : 1)) * block_per_line) {
                immutable pos = index % block_per_line;
                if ((index % block_per_line) == 0) {
                    line[] = 0;
                }

                scope block = read(Index(index));
                line[pos] = getSymbol(block, Index(index));

                if (pos + 1 == block_per_line) {
                    writefln("%04X] %s", index - pos, line);
                }
            }
    }

    // Block index 0 is means null
    // The first block is use as BlockFile header
    unittest {
        enum SMALL_BLOCK_SIZE = 0x40;
        import std.format;

        /// Test of BlockFile.create and BlockFile.opCall
        {
            immutable filename = fileId("create").fullpath;
            BlockFile.create(filename, "create.unittest", SMALL_BLOCK_SIZE);
            auto blockfile_load = BlockFile(filename);
            scope (exit) {
                blockfile_load.close;
            }
        }

        alias B = Tuple!(string, "label", uint, "blocks");
        version (none) Document generate_block(const BlockFile blockfile, const B b) {
            enum filler = " !---- ;-) -----! ";
            string text = b.label;
            while ((text.length / blockfile.DATA_SIZE) < b.blocks) {
                text ~= filler;
            }
            return cast(Buffer) text;
        }

        /// Create BlockFile
        {
            // Delete test blockfile
            // Create new blockfile
            File file = File(fileId.fullpath, "w");
            auto blockfile = new BlockFile(file, SMALL_BLOCK_SIZE);
            assert(!blockfile.hasHeader);
            blockfile.createHeader("This is a Blockfile unittest");
            assert(blockfile.hasHeader);
            file.close;
        }

        {
            // Check the header exists
            auto blockfile = new BlockFile(fileId.fullpath, SMALL_BLOCK_SIZE);
            assert(blockfile.hasHeader);
            blockfile.close;
        }

        version (none) bool failsafe(const Index index, const Fail f, const Block block, const bool recycle_block) @safe {
            assert(f == Fail.NON, format("Data check fails on block @ %d: Fail:%s in %s",
                    index, f, recycle_block ? "recycle block" : "data block"));
            return false;
        }

        {
            version (none) {
                auto blockfile = new BlockFile(fileId.fullpath, SMALL_BLOCK_SIZE);
                blockfile.inspect(&failsafe);

                B[] allocators = [
                    B("++++Block 0", 5), // 0

                    B("++++Block 1", 2), // 1

                    B("++++Block 2", 1), // 2
                    B("++++Block 3", 3), // 3

                    B("++++Block 4", 2), // 4
                    B("++++Block 5", 1), // 5
                    B("++++Block 6", 2), // 6
                    B("++++Block 7", 4), // 7
                    B("++++Block 8", 4), // 8
                    B("++++Block 9", 9), // 9

                    B("++++Block 10", 8), // 10
                    B("++++Block 11", 4), // 11
                    B("++++Block 12", 1), // 12
                    B("++++Block 13", 3), // 13
                    B("++++Block 14", 2), // 14
                    B("++++Block 15", 3), // 15
                    B("++++Block 16", 5) // 16 Last data block

                ];

                foreach (b; allocators) {
                    blockfile.save(generate_block(blockfile, b));
                }

                // Note the state block is written after the last block
                blockfile.store;

                blockfile.close;
            }

            version (none) { /// Check the blockfile
                auto blockfile = new BlockFile(fileId.fullpath, SMALL_BLOCK_SIZE);
                blockfile.inspect(&failsafe);
                blockfile.close;
            }

        }

        version (none) void erase(BlockFile blockfile, immutable(Index[]) erase_list) {
            void local_erase(const Index index, immutable(Index[]) erase_list, immutable uint no = 0) {
                if ((index !is INDEX_NULL) && (erase_list.length > 0)) {
                    if (no == erase_list[0]) {
                        immutable end_index = blockfile.erase(index);
                        local_erase(end_index, erase_list[1 .. $], no + 1);
                    }
                else {
                        immutable end_index = blockfile.end_index(index);
                        local_erase(end_index, erase_list, no + 1);
                    }
                }

            }

            local_erase(blockfile.masterblock.first_index, erase_list);
        }

        version (none) /// Removed becase next index has been removed from Block
        { // Remove block
            auto blockfile = new BlockFile(fileId.fullpath, SMALL_BLOCK_SIZE);
            blockfile.inspect(&failsafe);
            // Erase chain of block
            erase(blockfile, [0, 2, 6, 13, 16].map!(index => Index(index)).array.idup);
            blockfile.store;

            blockfile.close;
        }

        version (none) { // Check the recycle list
            auto blockfile = new BlockFile(fileId.fullpath, SMALL_BLOCK_SIZE);

            assert(equal(blockfile.recycle_indices[], [
                1, 2, 3, 4, 5, 6,
                10, 11,
                21, 22, 23,
                60, 61, 62,
                69, 70, 71, 72, 73, 74, 75, 76, 77
            ]));
            blockfile.close;
        }

        {
            auto blockfile = new BlockFile(fileId.fullpath, SMALL_BLOCK_SIZE);

            blockfile.erase(blockfile.masterblock.statistic_index);

            blockfile.close;
        }

        version (none) { // Write block again
            auto blockfile = new BlockFile(fileId.fullpath, SMALL_BLOCK_SIZE);
            // The statistic block is erased before writing
            B[] allocators = [
                B("++++Block 17", 9), // 17
                B("++++Block 18", 4), // 18
                B("++++Block 19", 2), // 19
                B("++++Block 20", 1), // 20
                B("++++Block 21", 3), // 21
                B("++++Block 22", 3), // 22
                B("++++Block 23", 4) // 23
            ];

            foreach (b; allocators) {
                blockfile.save(generate_block(blockfile, b));
            }

            blockfile.store;

            blockfile.close;

        }

        version (none) { // Check that all block are written
            auto blockfile = new BlockFile(fileId.fullpath, SMALL_BLOCK_SIZE);

            blockfile.inspect(&failsafe);

            blockfile.close;
        }

        version (none) // Removed because previous index has been removed from block
        {
            import std.math.operations : isClose;
            import std.stdio;

            auto blockfile = new BlockFile(fileId.fullpath, SMALL_BLOCK_SIZE);
            immutable uint[uint] size_stats =
                [6: 2, 2: 4, 3: 5, 10: 2, 5: 5, 4: 5, 9: 1];
            foreach (size, count; blockfile.statistic.histogram) {
                assert(size in size_stats);
                assert(count is size_stats[size]);
            }

            immutable result = blockfile.statistic.result;
            assert(isClose(result.mean, 4.54167f));
            assert(isClose(result.sigma, 2.32153f));
            assert(result.N == 24);
            blockfile.close;
        }
    }
}
