module tagion.wallet.BIP39;

import std.string : representation;
import tagion.basic.Debug;
import tagion.basic.Version : ver;
import tagion.crypto.random.random;

static assert(ver.LittleEndian, "At the moment bip39 only supports Little Endian");

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

import std.algorithm;
import std.range;
import std.typecons;
import tagion.hibon.HiBONRecord;

@safe
struct WordList {
    import tagion.crypto.pbkdf2;
    import std.digest.sha : SHA512;

    alias pbkdf2_sha512 = pbkdf2!SHA512;
    const(ushort[string]) table;
    const(string[]) words;
    enum presalt = "mnemonic";
    this(const(string[]) list) pure nothrow
    in (list.length == TOTAL_WORDS)
    do {
        words = list;
        table = list
            .enumerate!ushort
            .map!(w => tuple!("index", "value")(w.value, w.index))
            .assocArray;

    }

    void gen(ref scope ushort[] words) const nothrow {
        foreach (ref word; words) {
            word = getRandom!ushort & (TOTAL_WORDS - 1);
        }
    }

    const(ushort[]) mnemonicNumbers(const(string[]) mnemonics) const pure {
        return mnemonics
            .map!(m => table.get(m, ushort.max))
            .array;
    }

    bool checkMnemoicNumbers(scope const(ushort[]) mnemonic_codes) const pure nothrow @nogc {
        return mnemonic_codes.all!(m => m < TOTAL_WORDS);
    }

    ubyte[] opCall(scope const(ushort[]) mnemonic_codes, scope const(char[]) passphrase) const nothrow {
        scope word_list = mnemonic_codes[]
            .map!(mnemonic_code => words[mnemonic_code]);
        return opCall(word_list, passphrase);
    }

    char[] passphrase(const uint number_of_words) const nothrow {
        scope ushort[] mnemonic_codes;
        mnemonic_codes.length = number_of_words;
        scope (exit) {
            mnemonic_codes[] = 0;
        }
        gen(mnemonic_codes);
        const password_size = mnemonic_codes
            .map!(code => words[code])
            .map!(m => m.length)
            .sum + mnemonic_codes.length - 1;
        auto result = new char[password_size];
        result[] = ' ';
        uint index;
        foreach (code; mnemonic_codes) {
            result[index .. index + words[code].length] = words[code];
            index += words[code].length + char.sizeof;
        }
        return result;
    }

    enum count = 2048;
    enum dk_length = 64;
    ubyte[] opCall(R)(scope R mnemonics, scope const(char[]) passphrase) const nothrow if (isInputRange!R) {
        scope char[] salt = presalt ~ passphrase;
        const password_size = mnemonics.map!(m => m.length).sum + mnemonics.length - 1;
        scope password = new char[password_size];
        scope (exit) {
            password[] = 0;
            salt[] = 0;
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
    enum TOTAL_WORDS = 1 << MNEMONIC_BITS;
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
    //    import std.stdio;
    import tagion.wallet.bip39_english;
    import std.format;
    import std.string : representation;

    const wordlist = WordList(words);
    {
        const mnemonic = [
            "punch",
            "shock",
            "entire",
            "north",
            "file",
            "identify"
        ];
        const(ushort[]) expected_mnemonic_codes = [1390, 1586, 604, 1202, 689, 900];
        immutable expected_entropy = "101011011101100011001001001011100100101100100101011000101110000100";
        const mnemonic_codes = wordlist.mnemonicNumbers(mnemonic);
        assert(expected_mnemonic_codes == mnemonic_codes);
        string mnemonic_codes_bits = format("%(%011b%)", mnemonic_codes);
        assert(expected_entropy == mnemonic_codes_bits);
        const entropy = wordlist.entropy(mnemonic_codes);
        string entropy_bits = format("%(%08b%)", entropy)[0 .. 11 * expected_mnemonic_codes.length];
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
        const mnemonic_codes = wordlist.mnemonicNumbers(mnemonic);
        string entropy_bits = format("%(%011b%)", wordlist.mnemonicNumbers(mnemonic));
        assert(expected_entropy == entropy_bits);

    }
    { /// PBKDF2 BIP39
        const mnemonic = [
            "basket",
            "actual"
        ];

        import tagion.crypto.pbkdf2;
        import std.bitmanip : nativeToBigEndian;
        import std.digest.sha : SHA512;

        const mnemonic_codes = wordlist.mnemonicNumbers(mnemonic);

        const entropy = wordlist.entropy(mnemonic_codes);
        string mnemonic_codes_bits = format("%(%011b%)", mnemonic_codes);
        string entropy_bits = format("%(%08b%)", entropy); //[0 .. 12 * mnemonic_codes.length];
        alias pbkdf2_sha512 = pbkdf2!SHA512;
        string salt = "mnemonic"; //.representation;
        const entropy1 = "basket actual".representation;
        const result1 = pbkdf2_sha512(entropy1, salt.representation, 2048, 64);
    }
}
