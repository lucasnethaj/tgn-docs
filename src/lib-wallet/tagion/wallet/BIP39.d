module tagion.wallet.BIP39;

import tagion.basic.Version : ver;
import tagion.basic.Debug;
import tagion.utils.Miscellaneous : toHexString;
import tagion.crypto.random.random;
import tagion.crypto.SecureNet : scramble;
import std.string : representation;

static assert(ver.LittleEndian, "At the moment bip39 only supports Little Endian");

//ubyte[] bip39(in WordList wordlist, const(ushort[]) mnemonics) {
//}
//version(none)
@trusted
ubyte[] bip39(const(ushort[]) mnemonics) nothrow {
    pragma(msg, "fixme(cbr): Fake BIP39 must be fixed later");
    import std.digest.sha : SHA256;
    import std.digest;

    enum MAX_WORDS = 24; /// Max number of mnemonic word in a string
    enum MNEMONIC_BITS = 11; /// Bit size of the word number 2^11=2048
    enum MAX_BITS = MAX_WORDS * MNEMONIC_BITS; /// Total number of bits
    enum WORK_BITS = 8 * uint.sizeof;
    enum SIZE_OF_WORK_BUFFER = (MAX_BITS / WORK_BITS) + ((MAX_BITS % WORK_BITS) ? 1 : 0);
    const total_bits = mnemonics.length * MNEMONIC_BITS;
    uint[SIZE_OF_WORK_BUFFER] work_buffer;
    ulong* work_slide = cast(ulong*)&work_buffer[0];
    uint mnemonic_pos;
    size_t work_pos;
    foreach (mnemonic; mnemonics) {
        *work_slide |= ulong(mnemonic) << mnemonic_pos;
        mnemonic_pos += MNEMONIC_BITS;
        if (mnemonic_pos >= WORK_BITS) {
            work_pos++;
            mnemonic_pos -= WORK_BITS;
            work_slide = cast(ulong*)&work_buffer[work_pos];
        }
    }

    const result_buffer = (cast(ubyte*)&work_buffer[0])[0 .. SIZE_OF_WORK_BUFFER * uint.sizeof];

    pragma(msg, "fixme(cbr): PBKDF2 hmac function should be used");

    version (HASH_SECP256K1) {
        import tagion.crypto.secp256k1.NativeSecp256k1;

        return NativeSecp256k1.calcHash(result_buffer);
    }
    else {
        return digest!SHA256(cast(ubyte[]) result_buffer).dup;

    }

}

/*
https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki
10001111110100110100110001011001100010111110011101010000101001000000110000011001101010001100001000011101110011000100000111111100
0111

more omit biology blind insect faith corn crush search unveil away wedding

1010010001011010010011001111111000111100011110010110110111110111011110101101101010000000010001010111111001100010011010101000110000110100110011100000010001010001010100110111101110001010011010100000101011000001101000110000010110001001100011100001110011010010
01001011


picture sponsor display jump nothing wing twin exotic earth vessel one blur erupt acquire earn hunt media expect race ecology flat shove infant enact

1137e53d16d7ce04339914da41bdeb24b246f0878494f066a145f8a7f43c8264e177873c54830fa9b0cafdf5846258521b208f6d7fcd0de78ac22bf51040efde
*/

import std.range;
import std.algorithm;
import std.typecons;
import tagion.hibon.HiBONRecord;

@safe
struct WordList {
    import tagion.pbkdf2.pbkdf2;
    import std.digest.sha : SHA512;

    alias pbkdf2_sha512 = pbkdf2!SHA512;
    const(ushort[string]) table;
    const(string[]) words;
    enum presalt = "mnemonic";
    this(const(string[]) list) pure nothrow
    in (list.length == 2048)
    do {
        words = list;
        table = list
            .enumerate!ushort
            .map!(w => tuple!("index", "value")(w.value, w.index))
            .assocArray;

    }

    void gen(ref scope ushort[] words) const {
        foreach (ref word; words) {
            word = getRandom!ushort & 0x800;
        }
    }

    ushort[] numbers(const(string[]) mnemonics) const pure {

        return mnemonics
            .map!(m => cast(ushort) table.get(m, ushort.max))
            .array;
    }

    ubyte[] opCall(scope const(ushort[]) mnemonic_codes, scope const(char[]) passphrase) const nothrow {
        scope word_list = mnemonic_codes[]
            .map!(mnemonic_code => words[mnemonic_code]);
        return opCall(word_list, passphrase);
    }

    enum count = 2048;
    enum dk_length = 64;
    ubyte[] opCall(R)(scope R mnemonics, scope const(char[]) passphrase) const nothrow if (isInputRange!R) {
        scope char[] salt = presalt ~ passphrase;
        const password_size = mnemonics.map!(m => m.length).sum + mnemonics.length - 1;
        scope password = new char[password_size];
        scope (exit) {
            scramble(password);
            scramble(salt);
        }
        password[] = ' ';
        uint index;
        foreach (mnemonic; mnemonics) {
            password[index .. index + mnemonic.length] = mnemonic;
            index += mnemonic.length + char.sizeof;
        }
        return pbkdf2_sha512(password.representation, salt.representation, count, dk_length);
    }

    enum MAX_WORDS = 24; /// Max number of mnemonic word in a string
    enum MNEMONIC_BITS = 11; /// Bit size of the word number 2^11=2048
    enum MAX_BITS = MAX_WORDS * MNEMONIC_BITS; /// Total number of bits

    @trusted
    ubyte[] entropy(const(ushort[]) mnemonic_codes) const {
        import std.bitmanip : nativeToBigEndian, nativeToLittleEndian;
        import std.stdio;

        const total_bits = mnemonic_codes.length * MNEMONIC_BITS;
        const total_bytes = total_bits / 8 + ((total_bits & 7) != 0);
        ubyte[] result = new ubyte[total_bytes];

        foreach (i, mnemonic; mnemonic_codes) {
            const bit_pos = i * MNEMONIC_BITS;
            const byte_pos = bit_pos / 8;
            const shift_pos = 32 - (11 + (bit_pos & 7));
            const mnemonic_bytes = (uint(mnemonic) << shift_pos).nativeToBigEndian;
            result[byte_pos] |= mnemonic_bytes[0];
            result[byte_pos + 1] = mnemonic_bytes[1];
            if (mnemonic_bytes[2]) {
                result[byte_pos + 2] = mnemonic_bytes[2];

            }
        }
        return result;
    }

}

/*
https://learnmeabitcoin.com/technical/mnemonic
later echo alcohol essence charge eight feel sweet nephew apple aerobic device
01111101010010001011110000011000001001101010001001101000100011011101010100110110110111011001010001000001010101000001000010011110
0101
*/

@safe
unittest {
    import std.stdio;
    import tagion.wallet.bip39_english;
    import std.format;
    import std.string : representation;

    const wordlist = WordList(words);
    {
        const mnemonic = [
            "punch", "shock", "entire", "north", "file",
            "identify" /*    
        "echo",
            "alcohol",

            "essence",
            "charge",
            "eight",
            "feel",
            "sweet",
            "nephew",
            "apple",
            "aerobic",
            "device"
        */
        ];
        const(ushort[]) expected_mnemonic_codes = [1390, 1586, 604, 1202, 689, 900];
        immutable expected_entropy = "101011011101100011001001001011100100101100100101011000101110000100";
        const mnemonic_codes = wordlist.numbers(mnemonic);
        assert(expected_mnemonic_codes == mnemonic_codes);
        writefln("%(%d %)", mnemonic_codes);
        writefln("mnemonic_codes   %(%011b%)", mnemonic_codes);
        writefln("expected_entropy %s", expected_entropy);
        string mnemonic_codes_bits = format("%(%011b%)", mnemonic_codes);
        assert(expected_entropy == mnemonic_codes_bits);
        const entropy = wordlist.entropy(mnemonic_codes);
        string entropy_bits = format("%(%08b%)", entropy)[0 .. 11 * expected_mnemonic_codes.length];
        writefln("expected_bits    %s", entropy_bits);
        assert(expected_entropy == entropy_bits);
    }
    {
        const mnemonic = [
            "later",
            "echo",
            "alcohol",

            "essence",
            "charge",
            "eight",
            "feel",
            "sweet",
            "nephew",
            "apple",
            "aerobic",
            "device"
        ];
        //        const(ushort[]) mnemonic_code =[1390, 1586, 604, 1202, 689, 900];
        immutable expected_entropy = "011111010100100010111100000110000010011010100010011010001000110111010101001101101101110110010100010000010101010000010000100111100101";
        //assert(wordlist.numbers(mnemonic) == mnemonic_code);
        const mnemonic_codes = wordlist.numbers(mnemonic);
        writefln("%(%d %)", mnemonic_codes);
        writefln("mnemonic_codes   %(%011b%)", mnemonic_codes);
        writefln("expected_entropy %s", expected_entropy);
        writefln("%(%011b%)", wordlist.numbers(mnemonic));
        writefln("%s", expected_entropy);
        string entropy_bits = format("%(%011b%)", wordlist.numbers(mnemonic));
        writefln("expected_bits    %s", entropy_bits);
        assert(expected_entropy == entropy_bits);

    }
    { /// PBKDF2 BIP39
        const mnemonic = [
            "basket",
            "actual"//            "resist", "lounge",
            //            "switch",
        ];

        writefln("%(%d %)", wordlist.numbers(mnemonic));
        import tagion.pbkdf2.pbkdf2;
        import std.digest.sha : SHA512;
        import std.bitmanip : nativeToBigEndian;

        const mnemonic_codes = wordlist.numbers(mnemonic);

        const entropy = wordlist.entropy(mnemonic_codes);
        string mnemonic_codes_bits = format("%(%011b%)", mnemonic_codes);
        string entropy_bits = format("%(%08b%)", entropy); //[0 .. 12 * mnemonic_codes.length];
        writefln("%s", mnemonic_codes_bits);
        writefln("%s", entropy_bits);
        //  writefln("%(%02x %)", entropy);
        // writefln("%s", mnemonic_codes[0].nativeToBigEndian);
        writefln("mnemonic byte length=%s", mnemonic_codes.length * 11 / 8);
        writefln("entropy byte length =%s", entropy.length);
        alias pbkdf2_sha512 = pbkdf2!SHA512;
        string salt = "mnemonic"; //.representation;
        const entropy1 = "basket actual".representation;
        const result1 = pbkdf2_sha512(entropy1, salt.representation, 2048, 64);
        writefln("%(%02x%)", result1);
        //5cf2d4a8b0355e90295bdfc565a022a409af063d5365bb57bf74d9528f494bfa4400f53d8349b80fdae44082d7f9541e1dba2b003bcfec9d0d53781ca676651f
        //    https://learnmeabitcoin.com/technical/mnemonic 
    }

}
