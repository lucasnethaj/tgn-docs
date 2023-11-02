module tagion.crypto.SecureNet;

import std.typecons : TypedefType;

import tagion.crypto.SecureInterfaceNet;
import tagion.crypto.aes.AESCrypto;
import tagion.basic.Types : Buffer;
import tagion.crypto.Types : Signature, Fingerprint;
import tagion.hibon.Document : Document;
import tagion.basic.ConsensusExceptions;
import std.range;
import tagion.crypto.random.random;

void scramble(T, B = T[])(scope ref T[] data, scope const(B) xor = null) @safe if (T.sizeof is ubyte.sizeof)
in (xor.empty || data.length == xor.length) {

    scope buf = cast(ubyte[]) data;
    getRandom(buf);
    if (!xor.empty) {
        data[] ^= xor[];
    }
}

void scramble(T)(scope ref T[] data) @trusted if (T.sizeof > ubyte.sizeof) {
    scope ubyte_data = cast(ubyte[]) data;
    scramble(ubyte_data);
}

package alias check = Check!SecurityConsensusException;

@safe
class StdHashNet : HashNet {
    import std.format;

    enum HASH_SIZE = 32;
    @nogc final uint hashSize() const pure nothrow scope {
        return HASH_SIZE;
    }

    immutable(Buffer) rawCalcHash(scope const(ubyte[]) data) const scope {
        import std.digest.sha : SHA256;
        import std.digest;

        return digest!SHA256(data).idup;
    }

    Fingerprint calcHash(scope const(ubyte[]) data) const {
        return Fingerprint(rawCalcHash(data));
    }

    @trusted
    final immutable(Buffer) HMAC(scope const(ubyte[]) data) const pure {
        import std.exception : assumeUnique;
        import std.digest.sha : SHA256;
        import std.digest.hmac : digestHMAC = HMAC;

        scope hmac = digestHMAC!SHA256(data);
        auto result = hmac.finish.dup;
        return assumeUnique(result);
    }

    Fingerprint calcHash(const(Document) doc) const {
        return Fingerprint(rawCalcHash(doc.serialize));
    }

    enum hashname = "sha256";
    string multihash() const pure nothrow @nogc {
        return hashname;
    }
}

alias StdSecureNet = StdSecureNetT!false;
@safe
class StdSecureNetT(bool Schnorr) : StdHashNet, SecureNet {
    import tagion.crypto.secp256k1.NativeSecp256k1;
    import tagion.crypto.Types : Pubkey;
    import tagion.crypto.aes.AESCrypto;

    import tagion.basic.ConsensusExceptions;

    import std.format;
    import std.string : representation;

    private Pubkey _pubkey;
    /**
       This function
       returns
       If method is SIGN the signed message or
       If method is DERIVE it returns the derived privat key
    */
    @safe
    interface SecretMethods {
        immutable(ubyte[]) sign(const(ubyte[]) message) const;
        void tweakMul(const(ubyte[]) tweek_code, ref ubyte[] tweak_privkey) const;
        void tweakAdd(const(ubyte[]) tweek_code, ref ubyte[] tweak_privkey);
        immutable(ubyte[]) ECDHSecret(scope const(Pubkey) pubkey) const;
        void clone(StdSecureNet net) const;
    }

    protected SecretMethods _secret;

    @nogc final Pubkey pubkey() pure const nothrow {
        return _pubkey;
    }

    final Buffer hmacPubkey() const {
        return HMAC(cast(Buffer) _pubkey);
    }

    final Pubkey derivePubkey(string tweak_word) const {
        const tweak_code = HMAC(tweak_word.representation);
        return derivePubkey(tweak_code);
    }

    final Pubkey derivePubkey(const(ubyte[]) tweak_code) const {
        Pubkey result;
        const pkey = cast(const(ubyte[])) _pubkey;
        result = _crypt.pubKeyTweakMul(pkey, tweak_code);
        return result;
    }

    protected NativeSecp256k1 _crypt;

    bool verify(const Fingerprint message, const Signature signature, const Pubkey pubkey) const {
        consensusCheck!(SecurityConsensusException)(signature.length != 0 && signature.length <= 520,
                ConsensusFailCode.SECURITY_SIGNATURE_SIZE_FAULT);
        return _crypt.verify(cast(Buffer) message, cast(Buffer) signature, cast(Buffer) pubkey);
    }

    Signature sign(const Fingerprint message) const
    in {
        assert(_secret !is null,
                format("Signature function has not been intialized. Use the %s function", basename!generatePrivKey));
        assert(message.length == 32);
    }
    do {
        import std.traits;

        assert(_secret !is null, format("Signature function has not been intialized. Use the %s function", fullyQualifiedName!generateKeyPair));

        return Signature(_secret.sign(cast(Buffer) message));
    }

    final void derive(string tweak_word, ref ubyte[] tweak_privkey) {
        const data = HMAC(tweak_word.representation);
        derive(data, tweak_privkey);
    }

    final void derive(const(ubyte[]) tweak_code, ref ubyte[] tweak_privkey)
    in {
        assert(tweak_privkey.length >= 32);
    }
    do {
        _secret.tweakMul(tweak_code, tweak_privkey);
    }

    void derive(string tweak_word, shared(SecureNet) secure_net) {
        const tweak_code = HMAC(tweak_word.representation);
        derive(tweak_code, secure_net);

    }

    @trusted
    void derive(const(ubyte[]) tweak_code, shared(SecureNet) secure_net)
    in {
        assert(_secret);
    }
    do {
        synchronized (secure_net) {
            ubyte[] tweak_privkey = tweak_code.dup;
            auto unshared_secure_net = cast(SecureNet) secure_net;
            unshared_secure_net.derive(tweak_code, tweak_privkey);
            createKeyPair(tweak_privkey);
        }
    }

    const(SecureNet) derive(const(ubyte[]) tweak_code) const {
        ubyte[] tweak_privkey;
        _secret.tweakMul(tweak_code, tweak_privkey);
        auto result = new StdSecureNet;
        result.createKeyPair(tweak_privkey);
        return result;
    }

    final bool secKeyVerify(scope const(ubyte[]) privkey) const {
        return _crypt.secKeyVerify(privkey);
    }

    final void createKeyPair(ref ubyte[] privkey)
    in {
        assert(_secret is null);
    }
    do {
        scope (exit) {
            getRandom(privkey);
        }
        import std.string : representation;

        check(secKeyVerify(privkey), ConsensusFailCode.SECURITY_PRIVATE_KEY_INVALID);

        alias AES = AESCrypto!256;
        _pubkey = _crypt.getPubkey(privkey);
        auto aes_key_iv = new ubyte[AES.KEY_SIZE + AES.BLOCK_SIZE];
        getRandom(aes_key_iv);
        auto aes_key = aes_key_iv[0 .. AES.KEY_SIZE];
        auto aes_iv = aes_key_iv[AES.KEY_SIZE .. $];
        // Encrypt private key
        auto encrypted_privkey = new ubyte[privkey.length];
        AES.encrypt(aes_key, aes_iv, privkey, encrypted_privkey);
        @safe
        void do_secret_stuff(scope void delegate(const(ubyte[]) privkey) @safe dg) {
            // CBR:
            // Yes I know it is security by obscurity
            // But just don't want to have the private in clear text in memory
            // for long period of time
            auto tmp_privkey = new ubyte[encrypted_privkey.length];
            scope (exit) {
                getRandom(aes_key_iv);
                AES.encrypt(aes_key, aes_iv, tmp_privkey, encrypted_privkey);
                AES.encrypt(rawCalcHash(encrypted_privkey ~ aes_key_iv), aes_iv, encrypted_privkey, tmp_privkey);
            }
            AES.decrypt(aes_key, aes_iv, encrypted_privkey, tmp_privkey);
            dg(tmp_privkey);
        }

        @safe class LocalSecret : SecretMethods {
            immutable(ubyte[]) sign(const(ubyte[]) message) const {
                immutable(ubyte)[] result;
                do_secret_stuff((const(ubyte[]) privkey) { result = _crypt.sign(message, privkey); });
                return result;
            }

            void tweakMul(const(ubyte[]) tweak_code, ref ubyte[] tweak_privkey) const {
                do_secret_stuff((const(ubyte[]) privkey) @safe {
                    _crypt.privKeyTweakMul(privkey, tweak_code, tweak_privkey);
                });
            }

            void tweakAdd(const(ubyte[]) tweak_code, ref ubyte[] tweak_privkey) {
                do_secret_stuff((const(ubyte[]) privkey) @safe {
                    _crypt.privKeyTweakAdd(privkey, tweak_code, tweak_privkey);
                });
            }

            immutable(ubyte[]) ECDHSecret(scope const(Pubkey) pubkey) const {
                Buffer result;
                do_secret_stuff((const(ubyte[]) privkey) @safe {
                    result = _crypt.createECDHSecret(privkey, cast(Buffer) pubkey);
                });
                return result;
            }

            version (none) Buffer mask(const(ubyte[]) _mask) const {
                import std.algorithm.iteration : sum;

                check(sum(_mask) != 0, ConsensusFailCode.SECURITY_MASK_VECTOR_IS_ZERO);
                Buffer result;
                do_secret_stuff((const(ubyte[]) privkey) @safe {
                    import tagion.utils.Miscellaneous : xor;

                    auto data = xor(privkey, _mask);
                    result = rawCalcHash(rawCalcHash(data));
                });
                return result;
            }

            void clone(StdSecureNet net) const {
                do_secret_stuff((const(ubyte[]) privkey) @safe {
                    auto _privkey = privkey.dup;
                    net.createKeyPair(_privkey); // Not createKeyPair scrambles the privkey
                });
            }
        }

        _secret = new LocalSecret;
    }

    /**
    Params:
    passphrase = Passphrase is compatible with bip39
    salt = In bip39 the salt should be "mnemonic"~word 
*/
    void generateKeyPair(
            scope const(char[]) passphrase,
    scope const(char[]) salt = null,
    void delegate(scope const(ubyte[]) data) @safe dg = null)
    in {
        assert(_secret is null);
    }
    do {
        import tagion.pbkdf2.pbkdf2;
        import std.digest.sha : SHA512;

        enum count = 2048;
        enum dk_length = 64;

        alias pbkdf2_sha512 = pbkdf2!SHA512;
        auto data = pbkdf2_sha512(passphrase.representation, salt.representation, count, dk_length);
        scope (exit) {
            scramble(data);
        }
        auto _priv_key = data[0 .. 32];

        if (dg !is null) {
            dg(_priv_key);
        }
        createKeyPair(_priv_key);
    }

    immutable(ubyte[]) ECDHSecret(
            scope const(ubyte[]) seckey,
    scope const(Pubkey) pubkey) const {
        return _crypt.createECDHSecret(seckey, cast(Buffer) pubkey);
    }

    immutable(ubyte[]) ECDHSecret(scope const(Pubkey) pubkey) const {
        return _secret.ECDHSecret(pubkey);
    }

    Pubkey getPubkey(scope const(ubyte[]) seckey) const {
        return Pubkey(_crypt.getPubkey(seckey));
    }

    alias NativeSecp256k1 = NativeSecp256k1T!Schnorr;
    this() nothrow {
        _crypt = new NativeSecp256k1;
    }

    this(shared(StdSecureNet) other_net) @trusted {
        _crypt = new NativeSecp256k1;
        synchronized (other_net) {
            auto unshared_secure_net = cast(StdSecureNet) other_net;
            unshared_secure_net._secret.clone(this);
        }
    }

    unittest {
        auto other_net = new StdSecureNet;
        other_net.generateKeyPair("Secret password to be copied");
        auto shared_net = (() @trusted => cast(shared) other_net)();
        SecureNet copy_net = new StdSecureNet(shared_net);
        assert(other_net.pubkey == copy_net.pubkey);

    }

    void eraseKey() pure nothrow {
        _crypt = null;
    }

    unittest { // StdSecureNet rawSign
        const some_data = "some message";
        SecureNet net = new StdSecureNet;
        net.generateKeyPair("Secret password");
        SecureNet bad_net = new StdSecureNet;
        bad_net.generateKeyPair("Wrong Secret password");

        const message = net.calcHash(some_data.representation);

        Signature signature = net.sign(message);

        assert(!net.verify(message, signature, bad_net.pubkey));
        assert(net.verify(message, signature, net.pubkey));

    }

    unittest { // StdSecureNet document
        import tagion.hibon.HiBONJSON;

        import tagion.hibon.HiBON;
        import std.exception : assertThrown;
        import tagion.basic.ConsensusExceptions : SecurityConsensusException;

        SecureNet net = new StdSecureNet;
        net.generateKeyPair("Secret password");

        Document doc;
        {
            auto h = new HiBON;
            h["message"] = "Some message";
            doc = Document(h);
        }

        const doc_signed = net.sign(doc);

        assert(net.rawCalcHash(doc.serialize) == net.calcHash(doc.serialize), "should produce same hash");

        assert(doc_signed.message == net.rawCalcHash(doc.serialize));
        assert(net.verify(doc, doc_signed.signature, net.pubkey));

        SecureNet bad_net = new StdSecureNet;
        bad_net.generateKeyPair("Wrong Secret password");
        assert(!net.verify(doc, doc_signed.signature, bad_net.pubkey));

        { // Hash key
            auto h = new HiBON;
            h["#message"] = "Some message";
            doc = Document(h);
        }

        // A document containing a hash-key can not be signed or verified
        assertThrown!SecurityConsensusException(net.sign(doc));
        assertThrown!SecurityConsensusException(net.verify(doc, doc_signed.signature, net.pubkey));

    }

    unittest {
        import tagion.hibon.HiBONRecord;
        import std.format;

        SecureNet net = new StdSecureNet;
        net.generateKeyPair("Secret password");

        static struct RandomRecord {
            string x;

            mixin HiBONRecord;
        }

        foreach (i; 0 .. 1000) {
            RandomRecord data;
            data.x = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX20%s".format(i);

            auto fingerprint = net.calcHash(data);
            auto second_fingerprint = net.calcHash(data.toDoc.serialize);
            assert(fingerprint == second_fingerprint);

            auto sig = net.sign(data).signature;
            auto second_sig = net.sign(data.toDoc).signature;
            assert(sig == second_sig);

            assert(net.verify(fingerprint, sig, net.pubkey));
        }

    }
}

@safe
class BadSecureNet : StdSecureNet {
    this(string passphrase) {
        super();
        generateKeyPair(passphrase);
    }

    override Signature sign(const Fingerprint message) const {
        const false_message = super.calcHash(message ~ message);
        return super.sign(false_message);
    }
}
