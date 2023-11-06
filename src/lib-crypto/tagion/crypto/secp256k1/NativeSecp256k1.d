module tagion.crypto.secp256k1.NativeSecp256k1;

/++
 + Copyright 2013 Google Inc.
 + Copyright 2014-2016 the libsecp256k1 contributors
 +
 + Licensed under the Apache License, Version 2.0 (the "License");
 + you may not use this file except in compliance with the License.
 + You may obtain a copy of the License at
 +
 +    http://www.apache.org/licenses/LICENSE-2.0
 +
 + Unless required by applicable law or agreed to in writing, software
 + distributed under the License is distributed on an "AS IS" BASIS,
 + WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 + See the License for the specific language governing permissions and
 + limitations under the License.
 +/
@safe:
private import tagion.crypto.secp256k1.c.secp256k1;
private import tagion.crypto.secp256k1.c.secp256k1_ecdh;
private import tagion.crypto.secp256k1.c.secp256k1_hash;
private import tagion.crypto.secp256k1.c.secp256k1_schnorrsig;
private import tagion.crypto.secp256k1.c.secp256k1_extrakeys;

import std.exception : assumeUnique;
import tagion.basic.ConsensusExceptions;

import tagion.utils.Miscellaneous : toHexString;
import std.algorithm;
import std.array;

enum SECP256K1 : uint {
    FLAGS_TYPE_MASK = SECP256K1_FLAGS_TYPE_MASK,
    FLAGS_TYPE_CONTEXT = SECP256K1_FLAGS_TYPE_CONTEXT,
    FLAGS_TYPE_COMPRESSION = SECP256K1_FLAGS_TYPE_COMPRESSION,
    /** The higher bits contain the actual data. Do not use directly. */
    FLAGS_BIT_CONTEXT_VERIFY = SECP256K1_FLAGS_BIT_CONTEXT_VERIFY,
    FLAGS_BIT_CONTEXT_SIGN = SECP256K1_FLAGS_BIT_CONTEXT_SIGN,
    FLAGS_BIT_COMPRESSION = FLAGS_BIT_CONTEXT_SIGN,

    /** Flags to pass to secp256k1_context_create. */
    CONTEXT_VERIFY = SECP256K1_CONTEXT_VERIFY,
    CONTEXT_SIGN = SECP256K1_CONTEXT_SIGN,
    CONTEXT_NONE = SECP256K1_CONTEXT_NONE,

    /** Flag to pass to secp256k1_ec_pubkey_serialize and secp256k1_ec_privkey_export. */
    EC_COMPRESSED = SECP256K1_EC_COMPRESSED,
    EC_UNCOMPRESSED = SECP256K1_EC_UNCOMPRESSED,

    /** Prefix byte used to tag various encoded curvepoints for specific purposes */
    TAG_PUBKEY_EVEN = SECP256K1_TAG_PUBKEY_EVEN,
    TAG_PUBKEY_ODD = SECP256K1_TAG_PUBKEY_ODD,
    TAG_PUBKEY_UNCOMPRESSED = SECP256K1_TAG_PUBKEY_UNCOMPRESSED,
    TAG_PUBKEY_HYBRID_EVEN = SECP256K1_TAG_PUBKEY_HYBRID_EVEN,
    TAG_PUBKEY_HYBRID_ODD = SECP256K1_TAG_PUBKEY_HYBRID_ODD
}

alias NativeSecp256k1EDCSA = NativeSecp256k1T!false;
alias NativeSecp256k1Schnorr = NativeSecp256k1T!true;
/++
 + <p>This class holds native methods to handle ECDSA verification.</p>
 +
 + <p>You can find an example library that can be used for this at https://github.com/bitcoin/secp256k1</p>
 +
 + <p>To build secp256k1 for use with bitcoinj, run
 + `./configure --enable-jni --enable-experimental --enable-module-ecdh`
 + and `make` then copy `.libs/libsecp256k1.so` to your system library path
 + or point the JVM to the folder containing it with -Djava.library.path
 + </p>
 +/
class NativeSecp256k1T(bool Schnorr) {
    static void check(bool flag, ConsensusFailCode code, string file = __FILE__, size_t line = __LINE__) pure {
        if (!flag) {
            throw new SecurityConsensusException(code, file, line);
        }
    }

    enum TWEAK_SIZE = 32;
    enum SIGNATURE_SIZE = 64;
    enum SECKEY_SIZE = 32;
    enum XONLY_PUBKEY_SIZE = 32;
    enum MESSAGE_SIZE = 32;
    enum KEYPAIR_SIZE = secp256k1_keypair.data.length;

    protected secp256k1_context* _ctx;

    @trusted
    this(const SECP256K1 flag = SECP256K1.CONTEXT_SIGN | SECP256K1.CONTEXT_VERIFY) nothrow {
        _ctx = secp256k1_context_create(flag);
        scope (exit) {
            randomizeContext;
        }
    }

    /++
     + Verifies the given secp256k1 signature in native code.
     + Calling when enabled == false is undefined (probably library not loaded)

     + Params:
     +       msg            = The message which was signed, must be exactly 32 bytes
     +       signature      = The signature
     +       pub            =  The public key which did the signing
     +/
    @trusted
    static if (!Schnorr)
        final bool verify(const(ubyte[]) msg, const(ubyte[]) signature, const(ubyte[]) pub) const
    in (msg.length == MESSAGE_SIZE)
    in (signature.length == SIGNATURE_SIZE)
    in (pub.length <= 520)
    do {
        secp256k1_ecdsa_signature sig;
        secp256k1_pubkey pubkey;
        {
            const ret = secp256k1_ecdsa_signature_parse_compact(_ctx, &sig, &signature[0]);
            check(ret != 0, ConsensusFailCode.SECURITY_SIGNATURE_SIZE_FAULT);
        }
        {
            const ret = secp256k1_ec_pubkey_parse(_ctx, &pubkey, &pub[0], pub.length);
            check(ret == 1, ConsensusFailCode.SECURITY_PUBLIC_KEY_PARSE_FAULT);
        }
        const ret = secp256k1_ecdsa_verify(_ctx, &sig, &msg[0], &pubkey);
        return ret == 1;
    }

    /++
     + libsecp256k1 Create an ECDSA signature.
     +
     + @param msg Message hash, 32 bytes
     + @param key Secret key, 32 bytes
     +
     + Return values
     + @param sig byte array of signature
     +/
    @trusted
    static if (!Schnorr)
        immutable(ubyte[]) sign(const(ubyte[]) msg, const(ubyte[]) seckey) const
    in (msg.length == MESSAGE_SIZE)
    in (seckey.length == SECKEY_SIZE)
    do {
        secp256k1_ecdsa_signature sig;
        scope (exit) {
            randomizeContext;

        }

        {
            const ret = secp256k1_ecdsa_sign(_ctx, &sig, &msg[0], &seckey[0], null, null);
            check(ret == 1, ConsensusFailCode.SECURITY_SIGN_FAULT);
        }
        ubyte[SIGNATURE_SIZE] output_ser;
        {
            const ret = secp256k1_ecdsa_signature_serialize_compact(_ctx, &output_ser[0], &sig);
            check(ret == 1, ConsensusFailCode.SECURITY_SIGN_FAULT);
        }
        return output_ser.idup;
    }

    /++
     + libsecp256k1 Seckey Verify - returns true if valid, false if invalid
     +
     + @param seckey ECDSA Secret key, 32 bytes
     +/
    @trusted
    static if (!Schnorr)
        final bool secKeyVerify(scope const(ubyte[]) seckey) const nothrow @nogc
    in (seckey.length == SECKEY_SIZE)
    do {
        return secp256k1_ec_seckey_verify(_ctx, &seckey[0]) == 1;
    }

    /++
     + libsecp256k1 Compute Pubkey - computes public key from secret key
     +
     + @param seckey ECDSA Secret key, 32 bytes
     +
     + Return values
     + @param pubkey ECDSA Public key, 33 or 65 bytes
     +/
    enum COMPRESSED_PUBKEY_SIZE = 33;
    @trusted
    static if (!Schnorr)
        immutable(ubyte[]) getPubkey(scope const(ubyte[]) seckey) const
    in (seckey.length == SECKEY_SIZE)
    do {
        secp256k1_pubkey pubkey;

        {
            const ret = secp256k1_ec_pubkey_create(_ctx, &pubkey, &seckey[0]);
            check(ret == 1, ConsensusFailCode.SECURITY_PUBLIC_KEY_CREATE_FAULT);
        }
        ubyte[COMPRESSED_PUBKEY_SIZE] output_ser;
        enum flag = SECP256K1.EC_COMPRESSED;
        size_t outputLen = output_ser.length;
        {
            const ret = secp256k1_ec_pubkey_serialize(_ctx, &output_ser[0], &outputLen, &pubkey, flag);
            check(ret == 1, ConsensusFailCode.SECURITY_PUBLIC_KEY_CREATE_FAULT);
        }
        return output_ser.idup;
    }

    /++
     + libsecp256k1 Cleanup - This destroys the secp256k1 context object
     + This should be called at the end of the program for proper cleanup of the context.
     +/
    @trusted ~this() {
        secp256k1_context_destroy(_ctx);
    }

    @trusted
    secp256k1_context* cloneContext() {
        return secp256k1_context_clone(_ctx);
    }

    /++
     + libsecp256k1 PrivKey Tweak-Mul - Tweak privkey by multiplying to it
     +
     + @param tweak some bytes to tweak with
     + @param seckey 32-byte seckey
     +/
    @trusted
    static if (!Schnorr)
        final void privKeyTweakMul(
                const(ubyte[]) privkey,
    const(ubyte[]) tweak,
    ref ubyte[] tweak_privkey) const
    in {
        assert(privkey.length == 32);
    }
    do {
        pragma(msg, "fixme(cbr): privkey must be scrambled");
        tweak_privkey = privkey.dup;
        ubyte* _privkey = tweak_privkey.ptr;
        const(ubyte)* _tweak = tweak.ptr;

        int ret = secp256k1_ec_seckey_tweak_mul(_ctx, _privkey, _tweak);
        check(ret == 1, ConsensusFailCode.SECURITY_PRIVATE_KEY_TWEAK_MULT_FAULT);

    }

    /++
     + libsecp256k1 PrivKey Tweak-Add - Tweak privkey by adding to it
     +
     + @param tweak some bytes to tweak with
     + @param seckey 32-byte seckey
     +/
    @trusted
    static if (!Schnorr)
        final void privKeyTweakAdd(
                const(ubyte[]) privkey,
    const(ubyte[]) tweak,
    ref ubyte[] tweak_privkey) const
    in (privkey.length == 32)
    do {
        pragma(msg, "fixme(cbr): privkey must be scrambled");
        tweak_privkey = privkey.dup;
        ubyte* _privkey = tweak_privkey.ptr;
        const(ubyte)* _tweak = tweak.ptr;

        int ret = secp256k1_ec_seckey_tweak_add(_ctx, _privkey, _tweak);
        check(ret == 1, ConsensusFailCode.SECURITY_PRIVATE_KEY_TWEAK_ADD_FAULT);
    }

    /++
     + libsecp256k1 PubKey Tweak-Add - Tweak pubkey by adding to it
     +
     + @param tweak some bytes to tweak with
     + @param pubkey 32-byte seckey
     +/
    @trusted
    static if (!Schnorr)
        final immutable(ubyte[]) pubKeyTweakAdd(
            const(ubyte[]) pubkey,
    const(ubyte[]) tweak) const
    in (pubkey.length == COMPRESSED_PUBKEY_SIZE)
    in (tweak.length == TWEAK_SIZE)
    do {
        secp256k1_pubkey pubkey_result;
        {
            const ret = secp256k1_ec_pubkey_parse(_ctx, &pubkey_result, &pubkey[0], pubkey.length);
            check(ret == 1, ConsensusFailCode.SECURITY_PUBLIC_KEY_PARSE_FAULT);
        }
        {
            const ret = secp256k1_ec_pubkey_tweak_add(_ctx, &pubkey_result, &tweak[0]);
            check(ret == 1, ConsensusFailCode.SECURITY_PUBLIC_KEY_TWEAK_ADD_FAULT);
        }
        ubyte[COMPRESSED_PUBKEY_SIZE] output_ser;
        enum flag = SECP256K1.EC_COMPRESSED;
        size_t outputLen = output_ser.length;
        {
            const ret = secp256k1_ec_pubkey_serialize(_ctx, &output_ser[0], &outputLen, &pubkey_result, flag);
            assert(outputLen == COMPRESSED_PUBKEY_SIZE);
            check(ret == 1, ConsensusFailCode.SECURITY_PUBLIC_KEY_SERIALIZE);
        }
        return output_ser.idup;
    }

    /++
     + libsecp256k1 PubKey Tweak-Mul - Tweak pubkey by multiplying to it
     +
     + @param tweak some bytes to tweak with
     + @param pubkey 32-byte seckey
     +/
    @trusted
    static if (!Schnorr)
        final immutable(ubyte[]) pubKeyTweakMul(const(ubyte[]) pubkey, const(ubyte[]) tweak) const
    in (pubkey.length == COMPRESSED_PUBKEY_SIZE)
    in (tweak.length == TWEAK_SIZE)
    do {
        secp256k1_pubkey pubkey_result;
        {
            const ret = secp256k1_ec_pubkey_parse(_ctx, &pubkey_result, &pubkey[0], pubkey.length);
            check(ret == 1, ConsensusFailCode.SECURITY_PUBLIC_KEY_PARSE_FAULT);
        }
        {
            const ret = secp256k1_ec_pubkey_tweak_mul(_ctx, &pubkey_result, &tweak[0]);
            check(ret == 1, ConsensusFailCode.SECURITY_PUBLIC_KEY_TWEAK_MULT_FAULT);
        }
        ubyte[COMPRESSED_PUBKEY_SIZE] output_ser;
        enum flag = SECP256K1.EC_COMPRESSED;
        size_t outputLen = output_ser.length;

        {
            const ret = secp256k1_ec_pubkey_serialize(_ctx, &output_ser[0], &outputLen, &pubkey_result, flag);

            assert(outputLen == COMPRESSED_PUBKEY_SIZE);
            check(ret == 1, ConsensusFailCode.SECURITY_PUBLIC_KEY_SERIALIZE);
        }
        return output_ser.idup;
    }

    static if (!Schnorr)
        alias pubKeyTweak = pubKeyTweakMul;

    @trusted
    static if (Schnorr)
        final immutable(ubyte[]) pubKeyTweak(scope const(ubyte[]) pubkey, scope const(ubyte[]) tweak) const
    in (pubkey.length == XONLY_PUBKEY_SIZE)
    in (tweak.length == TWEAK_SIZE)
    do {
        secp256k1_xonly_pubkey xonly_pubkey;
        {
            const ret = secp256k1_xonly_pubkey_parse(_ctx, &xonly_pubkey, &pubkey[0]);
            check(ret == 1, ConsensusFailCode.SECURITY_PUBLIC_KEY_SERIALIZE);
        }
        secp256k1_pubkey output_pubkey;
        {
            const ret = secp256k1_xonly_pubkey_tweak_add(_ctx, &output_pubkey, &xonly_pubkey, &tweak[0]);
            check(ret == 1, ConsensusFailCode.SECURITY_PUBLIC_KEY_TWEAK_MULT_FAULT);

        }
        {
            const ret = secp256k1_xonly_pubkey_from_pubkey(_ctx, &xonly_pubkey, null, &output_pubkey);
            check(ret == 1, ConsensusFailCode.SECURITY_PUBLIC_KEY_PARSE_FAULT);
        }
        ubyte[XONLY_PUBKEY_SIZE] pubkey_result;

        {
            const ret = secp256k1_xonly_pubkey_serialize(_ctx, &pubkey_result[0], &xonly_pubkey);
            check(ret == 1, ConsensusFailCode.SECURITY_PUBLIC_KEY_PARSE_FAULT);

        }
        return pubkey_result.idup;
    }
    /++
     + libsecp256k1 create ECDH secret - constant time ECDH calculation
     +
     + @param seckey byte array of secret key used in exponentiaion
     + @param pubkey byte array of public key used in exponentiaion
     +/
    @trusted
    static if (!Schnorr)
        final immutable(ubyte[]) createECDHSecret(
            scope const(ubyte[]) seckey,
    const(ubyte[]) pubkey) const
    in (seckey.length == SECKEY_SIZE)
    in (pubkey.length == COMPRESSED_PUBKEY_SIZE)

    do {
        scope (exit) {
            randomizeContext;
        }
        secp256k1_pubkey pubkey_result;
        ubyte[32] result;
        {
            const ret = secp256k1_ec_pubkey_parse(_ctx, &pubkey_result, &pubkey[0], pubkey.length);
            check(ret == 1, ConsensusFailCode.SECURITY_PUBLIC_KEY_PARSE_FAULT);
        }
        {
            const ret = secp256k1_ecdh(_ctx, &result[0], &pubkey_result, &seckey[0], null, null);
            check(ret == 1, ConsensusFailCode.SECURITY_EDCH_FAULT);
        }
        return result.idup;
    }

    /++
     + libsecp256k1 randomize - updates the context randomization
     +
     + @param seed 32-byte random seed
     +/
    @trusted
    bool randomizeContext() nothrow const {
        import tagion.crypto.random.random;

        ubyte[] ctx_randomize;
        ctx_randomize.length = 32;
        getRandom(ctx_randomize);
        auto __ctx = cast(secp256k1_context*) _ctx;
        return secp256k1_context_randomize(__ctx, &ctx_randomize[0]) == 1;
    }

    @trusted
    static if (Schnorr)
        final void createKeyPair(
                const(ubyte[]) seckey,
    ref secp256k1_keypair keypair) const
    in (seckey.length == SECKEY_SIZE)

    do {
        scope (exit) {
            randomizeContext;
        }
        const rt = secp256k1_keypair_create(_ctx, &keypair, &seckey[0]);
        check(rt == 1, ConsensusFailCode.SECURITY_FAILD_TO_CREATE_KEYPAIR);

    }

    @trusted
    static if (Schnorr)
        final void getSecretKey(
                ref scope const(ubyte[]) keypair,
    out ubyte[] seckey) nothrow
    in (keypair.length == secp256k1_keypair.data.length)

    do {
        seckey.length = SECKEY_SIZE;
        const _keypair = cast(secp256k1_keypair*)&keypair[0];
        const ret = secp256k1_keypair_sec(_ctx, &seckey[0], _keypair);
        assert(ret is 1);
    }

    @trusted
    static if (Schnorr)
        final void getPubkey(
                ref scope const(secp256k1_keypair) keypair,
                ref scope secp256k1_pubkey pubkey) const nothrow {
            secp256k1_keypair_pub(_ctx, &pubkey, &keypair);
        }

    @trusted
    static if (Schnorr)
        final immutable(ubyte[]) sign(
            const(ubyte[]) msg,
    ref scope const(secp256k1_keypair) keypair,
    const(ubyte[]) aux_random) const
    in (msg.length == MESSAGE_SIZE)
    in (aux_random.length == MESSAGE_SIZE || aux_random.length == 0)

    do {
        scope (exit) {
            randomizeContext;
        }
        ubyte[SIGNATURE_SIZE] signature;
        const rt = secp256k1_schnorrsig_sign32(_ctx, &signature[0], &msg[0], &keypair, &aux_random[0]);
        check(rt == 1, ConsensusFailCode.SECURITY_FAILD_TO_SIGN_MESSAGE);
        return signature.idup;
    }

    @trusted
    static if (Schnorr)
        final bool verify(
                const(ubyte[]) signature,
    const(ubyte[]) msg,
    const(ubyte[]) pubkey) const nothrow
    in (pubkey.length == XONLY_PUBKEY_SIZE)

    do {
        secp256k1_xonly_pubkey xonly_pubkey;
        secp256k1_xonly_pubkey_parse(_ctx, &xonly_pubkey, &pubkey[0]);
        return verify(signature, msg, xonly_pubkey);
    }

    @trusted
    static if (Schnorr)
        final bool verify(
                const(ubyte[]) signature,
    const(ubyte[]) msg,
    ref scope const(secp256k1_xonly_pubkey) xonly_pubkey) const nothrow
    in (signature.length == SIGNATURE_SIZE)
    in (msg.length == MESSAGE_SIZE)

    do {
        const ret = secp256k1_schnorrsig_verify(_ctx, &signature[0], &msg[0], MESSAGE_SIZE, &xonly_pubkey);
        return ret != 0;

    }

    @trusted
    static if (Schnorr)
        final immutable(ubyte[]) getPubkey(scope const(ubyte[]) keypair) const
    in (keypair.length == secp256k1_keypair.data.length)

    do {
        static assert(secp256k1_keypair.data.offsetof == 0);
        const _keypair = cast(secp256k1_keypair*)(&keypair[0]);
        return getPubkey(*_keypair);
    }

    @trusted
    static if (Schnorr)
        final immutable(ubyte[]) getPubkey(ref scope const(secp256k1_keypair) keypair) const {
        secp256k1_xonly_pubkey xonly_pubkey;
        {
            const rt = secp256k1_keypair_xonly_pub(_ctx, &xonly_pubkey, null, &keypair);
            check(rt == 1, ConsensusFailCode.SECURITY_FAILD_PUBKEY_FROM_KEYPAIR);
        }
        ubyte[XONLY_PUBKEY_SIZE] pubkey;
        {
            const rt = secp256k1_xonly_pubkey_serialize(_ctx, &pubkey[0], &xonly_pubkey);
            check(rt == 1, ConsensusFailCode.SECURITY_FAILD_PUBKEY_FROM_KEYPAIR);
        }
        return pubkey.idup;

    }

    @trusted
    static if (Schnorr)
        final bool xonlyPubkey(
                ref scope const(secp256k1_pubkey) pubkey,
                ref secp256k1_xonly_pubkey xonly_pubkey) const nothrow @nogc {
            const ret = secp256k1_xonly_pubkey_from_pubkey(_ctx, &xonly_pubkey, null, &pubkey);
            return ret != 0;
        }
}

version (unittest) {
    import tagion.utils.Miscellaneous : toHexString, decode;

    const(ubyte[]) sha256(scope const(ubyte[]) data) {
        import std.digest.sha : SHA256;
        import std.digest;

        return digest!SHA256(data).dup;
    }
}

unittest { /// Test of ECDSA
    import std.traits;
    import std.stdio;

    /++
 + This tests secret key verify() for a valid secretkey
 +/{
        auto sec = "67E56582298859DDAE725F972992A07C6C4FB9F62A8FFF58CE3CA926A1063530".decode;
        try {
            auto crypt = new NativeSecp256k1EDCSA;
            auto result = crypt.secKeyVerify(sec);
            assert(result);
        }
        catch (ConsensusException e) {
            assert(0, e.msg);
        }
    }

    /++
 + This tests secret key verify() for an invalid secretkey
 +/
    {
        auto sec = "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF".decode;
        try {
            auto crypt = new NativeSecp256k1EDCSA;
            auto result = crypt.secKeyVerify(sec);
            assert(!result);
        }
        catch (ConsensusException e) {
            assert(0, e.msg);
        }
    }

    /++
 + This tests public key create() for a invalid secretkey
 +/
    {
        auto sec = "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF".decode;
        try {
            auto crypt = new NativeSecp256k1EDCSA;
            auto result = crypt.getPubkey(sec);
            assert(0, "This test should throw an ConsensusException");
        }
        catch (ConsensusException e) {
            assert(e.code == ConsensusFailCode.SECURITY_PUBLIC_KEY_CREATE_FAULT); // auto pubkeyString = resultArr.toHexString!true;
            // assert( pubkeyString == "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000");
        }

    }

    /++
 + This tests sign() for a valid secretkey
 +/
    {
        const data = "CF80CD8AED482D5D1527D7DC72FCEFF84E6326592848447D2DC0B0E87DFC9A90".decode; //sha256hash of "testing"
        const sec = "67E56582298859DDAE725F972992A07C6C4FB9F62A8FFF58CE3CA926A1063530".decode;
        try {
            const crypt = new NativeSecp256k1EDCSA;
            const result = crypt.sign(data, sec);
            assert(result == "182A108E1448DC8F1FB467D06A0F3BB8EA0533584CB954EF8DA112F1D60E39A21C66F36DA211C087F3AF88B50EDF4F9BDAA6CF5FD6817E74DCA34DB12390C6E9"
                    .decode);
        }
        catch (ConsensusException e) {
            assert(0, e.msg);
        }
    }

    /++
 + This tests sign() for a invalid secretkey
 +/
    {
        const data = "CF80CD8AED482D5D1527D7DC72FCEFF84E6326592848447D2DC0B0E87DFC9A90".decode; //sha256hash of "testing"
        const sec = "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF".decode;
        try {
            const crypt = new NativeSecp256k1EDCSA;
            const result = crypt.sign(data, sec);
            assert(0, "This test should throw an ConsensusException");
        }
        catch (ConsensusException e) {
            assert(e.code == ConsensusFailCode.SECURITY_SIGN_FAULT);
        }
    }

    /++
 + This tests private key tweak-add
 +/
    {
        const sec = "67E56582298859DDAE725F972992A07C6C4FB9F62A8FFF58CE3CA926A1063530".decode;
        const data = "3982F19BEF1615BCCFBB05E321C10E1D4CBA3DF0E841C2E41EEB6016347653C3".decode; //sha256hash of "tweak"
        try {
            const crypt = new NativeSecp256k1EDCSA;
            ubyte[] result;
            crypt.privKeyTweakAdd(sec, data, result);
            assert(result == "A168571E189E6F9A7E2D657A4B53AE99B909F7E712D1C23CED28093CD57C88F3".decode);
        }
        catch (ConsensusException e) {
            assert(0, e.msg);
        }
    }

    /++
 + This tests private key tweak-mul
 +/
    {
        const sec = "67E56582298859DDAE725F972992A07C6C4FB9F62A8FFF58CE3CA926A1063530".decode;
        const data = "3982F19BEF1615BCCFBB05E321C10E1D4CBA3DF0E841C2E41EEB6016347653C3".decode; //sha256hash of "tweak"
        try {
            const crypt = new NativeSecp256k1EDCSA;
            ubyte[] result;
            crypt.privKeyTweakMul(sec, data, result);
            assert(result == "97F8184235F101550F3C71C927507651BD3F1CDB4A5A33B8986ACF0DEE20FFFC".decode);
        }
        catch (ConsensusException e) {
            assert(0, e.msg);
        }
    }

    /++
 + This tests private key tweak-add uncompressed
 +/
    {
        const pubkey = "033b691036600deb3e04eb666760352989a734c0d24d93630688f1e45ca1b0deb1".decode;
        const tweak = "3982F19BEF1615BCCFBB05E321C10E1D4CBA3DF0E841C2E41EEB6016347653C3".decode; //sha256hash of "tweak"
        try {
            const crypt = new NativeSecp256k1EDCSA;
            const result = crypt.pubKeyTweakAdd(pubkey, tweak);
            assert(result != pubkey);
            assert(result == "0357f2926dd1107f86a3353bc023425c64b5294c70672bd89564a92d79ae128300".decode);
        }
        catch (ConsensusException e) {
            assert(0, e.msg);
        }
    }

    /++
 + This tests private key tweak-mul uncompressed
 +/
    {
        const pubkey = "033b691036600deb3e04eb666760352989a734c0d24d93630688f1e45ca1b0deb1".decode;
        const tweak = "3982F19BEF1615BCCFBB05E321C10E1D4CBA3DF0E841C2E41EEB6016347653C3".decode; //sha256hash of "tweak"
        try {
            const crypt = new NativeSecp256k1EDCSA;
            const result = crypt.pubKeyTweakMul(pubkey, tweak);
            assert(result != pubkey);
            assert(result == "02a80ffb5f6598b3c223e1917c0b3b93a7e7a39bea126c30d3253240b83ed18b57".decode);
        }
        catch (ConsensusException e) {
            assert(0, e.msg);
        }
    }

    /++
 + This tests seed randomization
 +/
    {
        try {
            auto crypt = new NativeSecp256k1EDCSA;
            auto result = crypt.randomizeContext;
            assert(result);
        }
        catch (ConsensusException e) {
            assert(0, e.msg);
        }
    }

    {
        auto message = "CF80CD8AED482D5D1527D7DC72FCEFF84E6326592848447D2DC0B0E87DFC9A90".decode;
        auto seed = "A441B15FE9A3CF5661190A0B93B9DEC7D04127288CC87250967CF3B52894D110".decode; //sha256hash of "random"
        import tagion.utils.Miscellaneous : toHexString;
        import std.digest.sha;

        try {
            auto crypt = new NativeSecp256k1EDCSA;
            auto data = seed.dup;
            do {
                data = sha256Of(data).dup;
            }
            while (!crypt.secKeyVerify(data));
            immutable privkey = data.idup;
            immutable pubkey = crypt.getPubkey(privkey);
            writefln("pubkey = %(%02x%)", pubkey);
            immutable signature = crypt.sign(message, privkey);
            assert(crypt.verify(message, signature, pubkey));
        }
        catch (ConsensusException e) {
            assert(0, e.msg);
        }

    }

    { //
        const crypt = new NativeSecp256k1EDCSA;
        const sec = "67E56582298859DDAE725F972992A07C6C4FB9F62A8FFF58CE3CA926A1063530".decode;
        immutable privkey = sec.idup;
        //        auto privkey = crypt.secKeyVerify( sec );
        assert(crypt.secKeyVerify(privkey));
        immutable pubkey = crypt.getPubkey(privkey);

        // Message
        const message = "CF80CD8AED482D5D1527D7DC72FCEFF84E6326592848447D2DC0B0E87DFC9A90".decode;
        const signature = crypt.sign(message, privkey);
        assert(crypt.verify(message, signature, pubkey));

        // Drived key a
        const drive = sha256("ABCDEF".decode);
        ubyte[] privkey_a_drived;
        crypt.privKeyTweakMul(privkey, drive, privkey_a_drived);
        assert(privkey != privkey_a_drived);
        const pubkey_a_drived = crypt.pubKeyTweakMul(pubkey, drive);
        assert(pubkey != pubkey_a_drived);
        const signature_a_drived = crypt.sign(message, privkey_a_drived);
        assert(crypt.verify(message, signature_a_drived, pubkey_a_drived));

        // Drive key b from key a
        ubyte[] privkey_b_drived;
        crypt.privKeyTweakMul(privkey_a_drived, drive, privkey_b_drived);
        assert(privkey_b_drived != privkey_a_drived);
        const pubkey_b_drived = crypt.pubKeyTweakMul(pubkey_a_drived, drive);
        assert(pubkey_b_drived != pubkey_a_drived);
        const signature_b_drived = crypt.sign(message, privkey_b_drived);
        assert(crypt.verify(message, signature_b_drived, pubkey_b_drived));

    }

    {
        const crypt = new NativeSecp256k1EDCSA;
        const sec = "67E56582298859DDAE725F972992A07C6C4FB9F62A8FFF58CE3CA926A1063530".decode;
        immutable privkey = sec.idup;
        //        auto privkey = crypt.secKeyVerify( sec );
        assert(crypt.secKeyVerify(privkey));
        immutable pubkey = crypt.getPubkey(privkey);

        // Message
        const message = "CF80CD8AED482D5D1527D7DC72FCEFF84E6326592848447D2DC0B0E87DFC9A90".decode;
        const signature = crypt.sign(message, privkey);
        assert(crypt.verify(message, signature, pubkey));

    }

    {
        const crypt = new NativeSecp256k1EDCSA;
        const sec = "67E56582298859DDAE725F972992A07C6C4FB9F62A8FFF58CE3CA926A1063530".decode;
        immutable privkey = sec.idup;
        assert(crypt.secKeyVerify(privkey));
        immutable pubkey = crypt.getPubkey(privkey);

        // Message
        const message = "CF80CD8AED482D5D1527D7DC72FCEFF84E6326592848447D2DC0B0E87DFC9A90".decode;
        const signature = crypt.sign(message, privkey);
        assert(crypt.verify(message, signature, pubkey));

    }

    {
        const crypt = new NativeSecp256k1EDCSA;
        const sec = "67E56582298859DDAE725F972992A07C6C4FB9F62A8FFF58CE3CA926A1063530".decode;
        immutable privkey = sec.idup;
        //        auto privkey = crypt.secKeyVerify( sec );
        assert(crypt.secKeyVerify(privkey));
        immutable pubkey = crypt.getPubkey(privkey);

        // Message
        const message = "CF80CD8AED482D5D1527D7DC72FCEFF84E6326592848447D2DC0B0E87DFC9A90".decode;
        const signature = crypt.sign(message, privkey);
        assert(crypt.verify(message, signature, pubkey));

    }

    {
        const crypt = new NativeSecp256k1EDCSA;
        const sec = "67E56582298859DDAE725F972992A07C6C4FB9F62A8FFF58CE3CA926A1063530".decode;
        immutable privkey = sec.idup;
        //        auto privkey = crypt.secKeyVerify( sec );
        assert(crypt.secKeyVerify(privkey));
        immutable pubkey = crypt.getPubkey(privkey);

        // Message
        const message = "CF80CD8AED482D5D1527D7DC72FCEFF84E6326592848447D2DC0B0E87DFC9A90".decode;
        const signature = crypt.sign(message, privkey);
        assert(crypt.verify(message, signature, pubkey));

    }

    {
        const crypt = new NativeSecp256k1EDCSA;
        const sec = "67E56582298859DDAE725F972992A07C6C4FB9F62A8FFF58CE3CA926A1063530".decode;
        immutable privkey = sec.idup;
        //        auto privkey = crypt.secKeyVerify( sec );
        assert(crypt.secKeyVerify(privkey));
        immutable pubkey = crypt.getPubkey(privkey);

        // Message
        const message = "CF80CD8AED482D5D1527D7DC72FCEFF84E6326592848447D2DC0B0E87DFC9A90".decode;
        const signature = crypt.sign(message, privkey);

        assert(crypt.verify(message, signature, pubkey));

    }

    //Test ECDH
    {
        import std.stdio;

        const crypt = new NativeSecp256k1EDCSA;

        const aliceSecretKey = "37cf9a0f624a21b0821f4ab3f711ac3a86ac3ae8e4d25bdbd8cdcad7b6cf92d4".decode;
        const alicePublicKey = crypt.getPubkey(aliceSecretKey);

        const bobSecretKey = "2f402cd0753d3afca00bd3f7661ca2f882176ae4135b415efae0e9c616b4a63e".decode;
        const bobPublicKey = crypt.getPubkey(bobSecretKey);

        assert(alicePublicKey == "0251958fb5c78264dc67edec62ad7cb0722ca7468e9781c1aebc0c05c5e8be05da".decode);
        assert(bobPublicKey == "0289685350631b9fee83158aa55980af0969305f698ebe3b9475a36340d0b19967".decode);

        const aliceResult = crypt.createECDHSecret(aliceSecretKey, bobPublicKey);
        const bobResult = crypt.createECDHSecret(bobSecretKey, alicePublicKey);

        assert(aliceResult == bobResult);
    }

}

unittest { /// Schnorr test generated from the secp256k1/examples/schnorr.c 
    const aux_random = "b0d8d9a460ddcea7ae5dc37a1b5511eb2ab829abe9f2999e490beba20ff3509a".decode;
    const msg_hash = "1bd69c075dd7b78c4f20a698b22a3fb9d7461525c39827d6aaf7a1628be0a283".decode;
    const secret_key = "e46b4b2b99674889342c851f890862264a872d4ac53a039fbdab91fd68ed4e71".decode;
    const expected_pubkey = "ecd21d66cf97843d467c9d02c5781ec1ec2b369620605fd847bd23472afc7e74".decode;
    const expected_signature = "021e9a32a12ead3144bb230a81794913a856296ed369159d01b8f57d6d7e7d3630e34f84d49ec054d5251ff6539f24b21097a9c39329eaab2e9429147d6d82f8"
        .decode;
    const expected_keypair = decode("e46b4b2b99674889342c851f890862264a872d4ac53a039fbdab91fd68ed4e71747efc2a4723bd47d85f602096362becc11e78c5029d7c463d8497cf661dd2eca89c1820ccc2dd9b0e0e5ab13b1454eb3c37c31308ae20dd8d2aca2199ff4e6b");
    auto crypt = new NativeSecp256k1Schnorr;
    secp256k1_keypair keypair;
    crypt.createKeyPair(secret_key, keypair);
    //writefln("keypair %(%02x%)", keypair);
    assert(keypair.data == expected_keypair);
    const signature = crypt.sign(msg_hash, keypair, aux_random);
    assert(signature == expected_signature);
    //writefln("expected_pubkey %(%02x%)", expected_pubkey);
    const pubkey = crypt.getPubkey(keypair); //writefln("         pubkey %(%02x%)", pubkey);
    assert(pubkey == expected_pubkey);
    const signature_ok = crypt.verify(signature, msg_hash, pubkey);
    assert(signature_ok, "Schnorr signing failded");
}
