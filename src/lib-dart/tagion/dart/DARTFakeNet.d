module tagion.dart.DARTFakeNet;

import std.typecons : Typedef;

//import tagion.gossip.InterfaceNet : SecureNet, HashNet;
import tagion.crypto.SecureNet : StdSecureNet;
import tagion.crypto.Types : Fingerprint, BufferType;
import tagion.basic.Types : Buffer, Control;
import tagion.dart.DART;
import tagion.dart.DARTFile : DARTFile;
import tagion.dart.Recorder : RecordFactory;
import tagion.hibon.Document : Document;
import tagion.hibon.HiBONRecord : HiBONPrefix;
import tagion.hibon.HiBON : HiBON;

/**
* This is the raw-hash value of a message and is used when message is signed.
*/
alias DARTIndex = Typedef!(Buffer, null, BufferType.HASHPOINTER.stringof);

@safe
class DARTFakeNet : StdSecureNet {
    enum FAKE = "$fake#";
    this(string passphrase) {
        this();
        generateKeyPair(passphrase);
    }

    this() {
        import tagion.crypto.secp256k1.NativeSecp256k1ECDSA;

        this._crypt = new NativeSecp256k1ECDSA;

    }

    override Fingerprint calcHash(scope const(ubyte[]) h) const {
        if (h.length is ulong.sizeof) {
            scope ubyte[] fake_h;
            fake_h.length = hashSize;
            fake_h[0 .. ulong.sizeof] = h;
            return Fingerprint(fake_h.idup);
        }
        return Fingerprint(super.rawCalcHash(h));
    }

    @trusted
    override Fingerprint calcHash(const(Document) doc) const {
        import tagion.hibon.HiBONBase : Type;
        import std.exception : assumeUnique;

        if (doc.hasMember(FAKE) && (doc[FAKE].type is Type.UINT64)) {
            const x = doc[FAKE].get!ulong;
            import std.bitmanip : nativeToBigEndian;

            ubyte[] fingerprint;
            fingerprint.length = hashSize;
            fingerprint[0 .. ulong.sizeof] = nativeToBigEndian(x);
            return Fingerprint(assumeUnique(fingerprint));
        }
        return super.calcHash(doc);
        //return rawCalcHash(doc.serialize);
    }

    static const(Document) fake_doc(const ulong x) {
        auto hibon = new HiBON;
        hibon[FAKE] = x;
        return Document(hibon);
    }

    enum hashname = "fake256";
    override string multihash() const pure nothrow @nogc {
        return hashname;
    }
}
