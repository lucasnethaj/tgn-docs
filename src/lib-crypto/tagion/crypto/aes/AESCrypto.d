module tagion.crypto.aes.AESCrypto;

private import std.format;

alias AES128 = AESCrypto!128;
//alias AES196=AESCrypto!196; // AES196 results in a segment fault for unknown reason
alias AES256 = AESCrypto!256;
//import std.stdio;

struct AESCrypto(int KEY_LENGTH) {
    static assert((KEY_LENGTH is 128) || (KEY_LENGTH is 192) || (KEY_LENGTH is 256),
            format("The KEYLENGTH of the %s must be 128, 196 or 256 not %d", AESCrypto.stringof, KEY_LENGTH));

    @disable this();

    static size_t enclength(const size_t inputlength) {
        return ((inputlength / BLOCK_SIZE) + ((inputlength % BLOCK_SIZE == 0) ? 0 : 1)) * BLOCK_SIZE;
    }

    version (TINY_AES) {
        import tagion.crypto.aes.tiny_aes.tiny_aes;

        alias AES = Tiny_AES!(KEY_LENGTH, Mode.CBC);
        enum BLOCK_SIZE = AES.BLOCK_SIZE;
        enum KEY_SIZE = AES.KEY_SIZE;
        //        alias enclength=enclengthT!BLOCK_SIZE;
        //        enum BLOCK_SIZE=16;
        static void crypt_parse(bool ENCRYPT = true)(const(ubyte[]) key, ubyte[BLOCK_SIZE] iv, ref ubyte[] data)
        in {
            assert(data);
            assert(data.length % BLOCK_SIZE == 0, format("Data must be an equal number of %d bytes but is %d", BLOCK_SIZE, data
                    .length));
            assert(key.length is KEY_SIZE, format("The key size must be %d bytes not %d", KEY_SIZE, key
                    .length));
        }
        do {
            scope aes = AES(key[0 .. KEY_SIZE], iv);
            static if (ENCRYPT) {
                aes.encrypt(data);
            }
            else {
                aes.decrypt(data);
            }
        }

        static void crypt(bool ENCRYPT = true)(const(ubyte[]) key, const(ubyte[]) iv, const(ubyte[]) indata, ref ubyte[] outdata) pure nothrow
        in {
            if (outdata !is null) {
                assert(enclength(indata.length) == outdata.length, format(
                        "Output data must be an equal number of %d bytes", BLOCK_SIZE));
                assert(iv.length is BLOCK_SIZE, format("The iv size must be %d bytes not %d", BLOCK_SIZE, iv
                        .length));

            }
        }
        do {
            if (outdata is null) {
                outdata = indata.dup;
            }
            else {
                outdata[0 .. $] = indata[0 .. $];
            }
            size_t old_length;
            if (outdata.length % BLOCK_SIZE !is 0) {
                old_length = outdata.length;
                outdata.length = enclength(outdata.length);
            }
            scope (exit) {
                if (old_length) {
                    outdata.length = old_length;
                }
            }
            ubyte[BLOCK_SIZE] temp_iv = iv[0 .. BLOCK_SIZE];
            crypt_parse!ENCRYPT(key, temp_iv, outdata);
        }

        alias encrypt = crypt!true;
        alias decrypt = crypt!false;
    }
    else {
        import tagion.crypto.aes.openssl_aes.aes;

        enum KEY_SIZE = KEY_LENGTH / 8;
        enum BLOCK_SIZE = AES_BLOCK_SIZE;
        static void crypt(bool ENCRYPT = true)(const(ubyte[]) key, const(ubyte[]) iv, const(ubyte[]) indata, ref ubyte[] outdata) @trusted
        in {
            assert(indata);
            if (outdata !is null) {
                assert(enclength(indata.length) == outdata.length,
                        format("Output data must be an equal number of %d bytes", BLOCK_SIZE));
            }
            assert(key.length is KEY_SIZE, format("The key size must be %d bytes not %d", KEY_SIZE, key
                    .length));
            assert(iv.length is BLOCK_SIZE, format("The iv size must be %d bytes not %d", BLOCK_SIZE, iv
                    .length));
        }
        do {
            auto aes_key = key.ptr;
            ubyte[BLOCK_SIZE] mem_iv = iv[0 .. BLOCK_SIZE];
            AES_KEY crypt_key;
            if (outdata is null) {
                outdata = new ubyte[enclength(indata.length)];
            }

            static if (ENCRYPT) {
                auto aes_input = indata.ptr;
                auto enc_output = outdata.ptr;
                AES_set_encrypt_key(aes_key, KEY_LENGTH, &crypt_key);
                //writefln("crypt_key=%s", crypt_key.hex);
                AES_cbc_encrypt(aes_input, enc_output, indata.length, &crypt_key, mem_iv.ptr, AES_ENCRYPT);
            }
            else {
                auto enc_input = indata.ptr;
                auto dec_output = outdata.ptr;
                AES_set_decrypt_key(aes_key, KEY_LENGTH, &crypt_key);
                AES_cbc_encrypt(enc_input, dec_output, enclength(indata.length), &crypt_key, mem_iv.ptr, AES_DECRYPT);

            }
        }

        alias encrypt = crypt!true;
        alias decrypt = crypt!false;

    }

    unittest {
        import tagion.utils.Random;
        import std.range: iota;
        import std.algorithm.iteration: map;
        import std.array: array;

        { // Encrypt
            immutable(ubyte[]) indata = [
                0x6b, 0xc1, 0xbe, 0xe2, 0x2e, 0x40, 0x9f, 0x96, 0xe9, 0x3d, 0x7e, 0x11, 0x73, 0x93, 0x17, 0x2a,
                0xae, 0x2d, 0x8a, 0x57, 0x1e, 0x03, 0xac, 0x9c, 0x9e, 0xb7, 0x6f, 0xac, 0x45, 0xaf, 0x8e, 0x51,
                0x30, 0xc8, 0x1c, 0x46, 0xa3, 0x5c, 0xe4, 0x11, 0xe5, 0xfb, 0xc1, 0x19, 0x1a, 0x0a, 0x52, 0xef,
                0xf6, 0x9f, 0x24, 0x45, 0xdf, 0x4f, 0x9b, 0x17, 0xad, 0x2b, 0x41, 0x7b, 0xe6, 0x6c, 0x37, 0x10
            ];
            static if (KEY_LENGTH is 256) {
                immutable(ubyte[KEY_SIZE]) key = [
                    0x60, 0x3d, 0xeb, 0x10, 0x15, 0xca, 0x71, 0xbe, 0x2b, 0x73, 0xae, 0xf0, 0x85, 0x7d, 0x77, 0x81,
                    0x1f, 0x35, 0x2c, 0x07, 0x3b, 0x61, 0x08, 0xd7, 0x2d, 0x98, 0x10, 0xa3, 0x09, 0x14, 0xdf, 0xf4
                ];
                immutable(ubyte[64]) outdata = [
                    0xf5, 0x8c, 0x4c, 0x04, 0xd6, 0xe5, 0xf1, 0xba, 0x77, 0x9e, 0xab, 0xfb, 0x5f, 0x7b, 0xfb, 0xd6,
                    0x9c, 0xfc, 0x4e, 0x96, 0x7e, 0xdb, 0x80, 0x8d, 0x67, 0x9f, 0x77, 0x7b, 0xc6, 0x70, 0x2c, 0x7d,
                    0x39, 0xf2, 0x33, 0x69, 0xa9, 0xd9, 0xba, 0xcf, 0xa5, 0x30, 0xe2, 0x63, 0x04, 0x23, 0x14, 0x61,
                    0xb2, 0xeb, 0x05, 0xe2, 0xc3, 0x9b, 0xe9, 0xfc, 0xda, 0x6c, 0x19, 0x07, 0x8c, 0x6a, 0x9d, 0x1b
                ];
            }
            else static if (KEY_LENGTH is 192) {
                immutable(ubyte[KEY_SIZE]) key = [
                    0x8e, 0x73, 0xb0, 0xf7, 0xda, 0x0e, 0x64, 0x52, 0xc8, 0x10, 0xf3, 0x2b, 0x80, 0x90, 0x79, 0xe5,
                    0x62, 0xf8, 0xea, 0xd2, 0x52, 0x2c, 0x6b, 0x7b
                ];
                immutable(ubyte[64]) outdata = [
                    0x4f, 0x02, 0x1d, 0xb2, 0x43, 0xbc, 0x63, 0x3d, 0x71, 0x78, 0x18, 0x3a, 0x9f, 0xa0, 0x71, 0xe8,
                    0xb4, 0xd9, 0xad, 0xa9, 0xad, 0x7d, 0xed, 0xf4, 0xe5, 0xe7, 0x38, 0x76, 0x3f, 0x69, 0x14, 0x5a,
                    0x57, 0x1b, 0x24, 0x20, 0x12, 0xfb, 0x7a, 0xe0, 0x7f, 0xa9, 0xba, 0xac, 0x3d, 0xf1, 0x02, 0xe0,
                    0x08, 0xb0, 0xe2, 0x79, 0x88, 0x59, 0x88, 0x81, 0xd9, 0x20, 0xa9, 0xe6, 0x4f, 0x56, 0x15, 0xcd
                ];
            }
            else static if (KEY_LENGTH is 128) {
                immutable(ubyte[KEY_SIZE]) key = [
                    0x2b, 0x7e, 0x15, 0x16, 0x28, 0xae, 0xd2, 0xa6, 0xab, 0xf7, 0x15, 0x88, 0x09, 0xcf, 0x4f, 0x3c
                ];
                immutable(ubyte[64]) outdata = [
                    0x76, 0x49, 0xab, 0xac, 0x81, 0x19, 0xb2, 0x46, 0xce, 0xe9, 0x8e, 0x9b, 0x12, 0xe9, 0x19, 0x7d,
                    0x50, 0x86, 0xcb, 0x9b, 0x50, 0x72, 0x19, 0xee, 0x95, 0xdb, 0x11, 0x3a, 0x91, 0x76, 0x78, 0xb2,
                    0x73, 0xbe, 0xd6, 0xb8, 0xe3, 0xc1, 0x74, 0x3b, 0x71, 0x16, 0xe6, 0x9e, 0x22, 0x22, 0x95, 0x16,
                    0x3f, 0xf1, 0xca, 0xa1, 0x68, 0x1f, 0xac, 0x09, 0x12, 0x0e, 0xca, 0x30, 0x75, 0x86, 0xe1, 0xa7
                ];
            }
            ubyte[BLOCK_SIZE] iv = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f];

            ubyte[] enc_output;
            AESCrypto.encrypt(key, iv, indata, enc_output);
            // writefln("outdata   =%s", outdata);
            // writefln("enc_output=%s", enc_output);
            // assert(enc_output == outdata);
            // writeln();
        }

        { // Decrypt
            static if (KEY_LENGTH is 256) {
                immutable(ubyte[KEY_SIZE]) key = [
                    0x60, 0x3d, 0xeb, 0x10, 0x15, 0xca, 0x71, 0xbe, 0x2b, 0x73, 0xae, 0xf0, 0x85, 0x7d, 0x77, 0x81,
                    0x1f, 0x35, 0x2c, 0x07, 0x3b, 0x61, 0x08, 0xd7, 0x2d, 0x98, 0x10, 0xa3, 0x09, 0x14, 0xdf, 0xf4
                ];
                immutable(ubyte[64]) indata = [
                    0xf5, 0x8c, 0x4c, 0x04, 0xd6, 0xe5, 0xf1, 0xba, 0x77, 0x9e, 0xab, 0xfb, 0x5f, 0x7b, 0xfb, 0xd6,
                    0x9c, 0xfc, 0x4e, 0x96, 0x7e, 0xdb, 0x80, 0x8d, 0x67, 0x9f, 0x77, 0x7b, 0xc6, 0x70, 0x2c, 0x7d,
                    0x39, 0xf2, 0x33, 0x69, 0xa9, 0xd9, 0xba, 0xcf, 0xa5, 0x30, 0xe2, 0x63, 0x04, 0x23, 0x14, 0x61,
                    0xb2, 0xeb, 0x05, 0xe2, 0xc3, 0x9b, 0xe9, 0xfc, 0xda, 0x6c, 0x19, 0x07, 0x8c, 0x6a, 0x9d, 0x1b
                ];
            }
            else static if (KEY_LENGTH is 192) {
                immutable(ubyte[KEY_SIZE]) key = [
                    0x8e, 0x73, 0xb0, 0xf7, 0xda, 0x0e, 0x64, 0x52, 0xc8, 0x10, 0xf3, 0x2b, 0x80, 0x90, 0x79, 0xe5,
                    0x62, 0xf8, 0xea, 0xd2, 0x52, 0x2c, 0x6b, 0x7b
                ];
                immutable(ubyte[64]) indata = [
                    0x4f, 0x02, 0x1d, 0xb2, 0x43, 0xbc, 0x63, 0x3d, 0x71, 0x78, 0x18, 0x3a, 0x9f, 0xa0, 0x71, 0xe8,
                    0xb4, 0xd9, 0xad, 0xa9, 0xad, 0x7d, 0xed, 0xf4, 0xe5, 0xe7, 0x38, 0x76, 0x3f, 0x69, 0x14, 0x5a,
                    0x57, 0x1b, 0x24, 0x20, 0x12, 0xfb, 0x7a, 0xe0, 0x7f, 0xa9, 0xba, 0xac, 0x3d, 0xf1, 0x02, 0xe0,
                    0x08, 0xb0, 0xe2, 0x79, 0x88, 0x59, 0x88, 0x81, 0xd9, 0x20, 0xa9, 0xe6, 0x4f, 0x56, 0x15, 0xcd
                ];
            }
            else static if (KEY_LENGTH is 128) {
                immutable(ubyte[KEY_SIZE]) key = [
                    0x2b, 0x7e, 0x15, 0x16, 0x28, 0xae, 0xd2, 0xa6, 0xab, 0xf7, 0x15, 0x88, 0x09, 0xcf, 0x4f, 0x3c
                ];
                immutable(ubyte[64]) indata = [
                    0x76, 0x49, 0xab, 0xac, 0x81, 0x19, 0xb2, 0x46, 0xce, 0xe9, 0x8e, 0x9b, 0x12, 0xe9, 0x19, 0x7d,
                    0x50, 0x86, 0xcb, 0x9b, 0x50, 0x72, 0x19, 0xee, 0x95, 0xdb, 0x11, 0x3a, 0x91, 0x76, 0x78, 0xb2,
                    0x73, 0xbe, 0xd6, 0xb8, 0xe3, 0xc1, 0x74, 0x3b, 0x71, 0x16, 0xe6, 0x9e, 0x22, 0x22, 0x95, 0x16,
                    0x3f, 0xf1, 0xca, 0xa1, 0x68, 0x1f, 0xac, 0x09, 0x12, 0x0e, 0xca, 0x30, 0x75, 0x86, 0xe1, 0xa7
                ];
            }
            ubyte[BLOCK_SIZE] iv = [
                0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f
            ];
            immutable(ubyte[]) outdata = [
                0x6b, 0xc1, 0xbe, 0xe2, 0x2e, 0x40, 0x9f, 0x96, 0xe9, 0x3d, 0x7e, 0x11, 0x73, 0x93, 0x17, 0x2a,
                0xae, 0x2d, 0x8a, 0x57, 0x1e, 0x03, 0xac, 0x9c, 0x9e, 0xb7, 0x6f, 0xac, 0x45, 0xaf, 0x8e, 0x51,
                0x30, 0xc8, 0x1c, 0x46, 0xa3, 0x5c, 0xe4, 0x11, 0xe5, 0xfb, 0xc1, 0x19, 0x1a, 0x0a, 0x52, 0xef,
                0xf6, 0x9f, 0x24, 0x45, 0xdf, 0x4f, 0x9b, 0x17, 0xad, 0x2b, 0x41, 0x7b, 0xe6, 0x6c, 0x37, 0x10
            ];

            ubyte[] dec_output;
            auto temp_iv = iv;
            AESCrypto.decrypt(key, temp_iv, indata, dec_output);
            // writefln("output     =%s", outdata);
            // writefln("dec_output =%s", dec_output);
            // import tagion.crypto.aes.tiny_aes.tiny_aes;
            // auto tiny_indata=indata.dup;
            // auto tiny_temp_iv=iv;
            // auto aes=Tiny_AES!KEY_LENGTH(key, tiny_temp_iv);
            // writefln("tiny_indata=%s", tiny_indata);
            // aes.decrypt(tiny_indata);
            // writefln("tiny_indata=%s", tiny_indata);
            // writefln("    outdata=%s", outdata);

            assert(dec_output == outdata);
        }

        //         {
        //             Random!uint random;
        //             random.seed(1234);
        //             immutable(ubyte[]) gen_key() {
        //                 ubyte[KEY_SIZE] result;
        //                 foreach(ref a; result) {
        //                     result=cast(ubyte)random.value(ubyte.sizeof+1);
        //                 }
        //                 return result.idup;
        //             }
        //             auto iv=iota(16).map!(a => cast(ubyte)a).array;
        //             immutable aes_key=gen_key;
        //             string text="Some very secret message!!!!!";
        //             auto input=cast(immutable(ubyte[]))text;
        //             ubyte[] enc_output;
        //             AESCrypto.encrypt(aes_key, iv, input, enc_output);
        //             writefln("input     (%3d)=%s", input.length, input);
        //             writefln("enc_output(%3d)=%s", enc_output.length, enc_output);
        // //        writefln("input          =%s", input.length, input[0..16]);
        //             writefln("enc_output     =%s", enc_output[0..16]);

        //             assert(input != enc_output[0..input.length]);
        //             ubyte[] dec_output;
        //             AESCrypto.decrypt(aes_key, iv, enc_output, dec_output);
        //             writefln("dec_output(%3d)=%s", dec_output.length, dec_output);
        //             writefln("dec_output     =%s", dec_output[0..16]);
        //             assert(input == dec_output);
        //         }
    }
}

unittest {
    static foreach (key_size; [128, 192, 256]) {
        {
            alias AES = AESCrypto!key_size;
        }
    }
}
