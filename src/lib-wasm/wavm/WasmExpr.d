module wavm.WasmExpr;

import std.bitmanip : nativeToLittleEndian;
import std.traits : Unqual, isArray, isIntegral, ForeachType;
import std.outbuffer;
import std.format;
import std.stdio;

import wavm.WasmBase;
import wavm.LEB128;

struct WasmExpr {
    protected OutBuffer bout;
    @disable this();
    this(OutBuffer bout) {
        this.bout=bout;
    }

    ref WasmExpr opCall(Args...)(const IR ir, Args args) {
        immutable instr=instrTable[ir];
        bout.write(cast(ubyte)ir);
        immutable irtype=instr.irtype;
        with(IRType) {
            final switch(irtype) {
            case CODE:
                assert(Args.length == 0, format("Instruction %s should have no arguments", instr.name));
                // No args
                break;
            case BLOCK, BRANCH, CALL, LOCAL, GLOBAL:
                assert(Args.length == 1, format("Instruction %s only one argument expected", instr.name));
                static if (Args.length == 1) {
                    assert(isIntegral!(Args[0]), format("Args idx must be an integer for %s not %s",
                            instr.name, Args[0].stringof));
                    pragma(msg, "opCall ARGS=", Args);
                    pragma(msg, "opCall ARGS[0]=", Args[0]);
                    pragma(msg, "opCall args=", typeof(args[0]));
                    static if (isIntegral!(Args[0])) {
                        bout.write(encode(args[0]));
                    }
                }
                break;
            case BRANCH_TABLE:
                scope uint[] table;
                pragma(msg, "BRANCH_TABLE >> ", Args);

                static foreach(i, a; args) {
                    {
                        enum OK=is(Args[i]:const(uint)) || is(Args[i]:const(uint[])); // || isArray!(Args[i]); // && isIntegral!(ForeachType!(Args[i])));
                        assert(OK, format("Argument %d must be integer or uint[] of integer not %s", i, Args[i].stringof));
                        static if (OK) {
                            table~=a;
                        }
                    }
                    version(none)
                    {
                        alias BaseT=Unqual!(Args[i]);
                        pragma(msg, "BRANCH_TABLE BaseT=", BaseT, " ", isIntegral!BaseT);
                        writefln("BRANCH_TABLE BaseT=%s %s isArray=%s", BaseT.stringof, isIntegral!BaseT, isArray!BaseT);
                        static if (is(isArray!BaseT)) {
                            writefln("\tinside isArray!BaseT is TRUE");
                        }
                        static if (is(isArray!BaseT)) {
                            writefln("\tinside isArray!BaseT");
                            assert(isIntegral!(ForeachType!BaseT),
                                format("Type %s for as argument for instruction %s is not allowed",
                                    Args[i], instr.name));
                            static if (isIntegral!(ForeachType!BaseT)) {
                                //foreach(e; args[i]) {
                                table~=a;
                                //}
                            }
                        }
                        else {
//                            static if (!isArray!BaseT) {
                            writefln("BRANCH_TABLE %s Args[i]=%s", isArray!BaseT, Args[i].stringof);
                            // assert(is(BaseT==uint) ,
                            //     format("Bad type %s of argument %d for instruction %s",
                            //         BaseT.stringof, i, instr.name));
                            pragma(msg, "table~=a ", typeof(a));
                            static if (is(BaseT==uint)) {
                                table~=a;
                            }
//                            }
                        }
                    }
                }
                writefln("table=%s", table);
                check(table.length >= 2, format("Too few arguments for %s instruction", instr.name));
                bout.write(encode(table.length-1));
                foreach(t; table) {
                    bout.write(encode(t));
                }
                break;
            case CALL_INDIRECT:
                assert(Args.length == 1, format("Instruction %s one argument", instr.name));
                static if (Args.length == 1) {
                    assert(isIntegral!(Args[0]), format("The funcidx must be an integer for %s", instr.name));
                    static if (isIntegral!(Args[0])) {
                        bout.write(encode(args[0]));
                        bout.write(cast(ubyte)(0x00));
                    }
                }
                break;
            case MEMORY:
                assert(Args.length == 2, format("Instruction %s two arguments", instr.name));
                static if (Args.length == 2) {
                    assert(isIntegral!(Args[0]), format("The funcidx must be an integer for %s", instr.name));
                    assert(isIntegral!(Args[1]), format("The funcidx must be an integer for %s", instr.name));
                    static if (isIntegral!(Args[0]) && isIntegral!(Args[1])) {
                        bout.write(encode(args[0]));
                        bout.write(encode(args[1]));
                    }
                }
                break;
            case MEMOP:
                assert(Args.length == 0, format("Instruction %s should have no arguments", instr.name));
                bout.write(cast(ubyte)(0x00));
                break;
            case CONST:
                assert(Args.length == 1, format("Instruction %s one argument", instr.name));
                static if (Args.length == 1) {
                    alias BaseArg0=Unqual!(Args[0]);
                    pragma(msg, "CONST BaseArg0=", BaseArg0);
                    with(IR) {
                        switch (ir) {
                        case I32_CONST:
                            assert(is(BaseArg0==int) || is(BaseArg0==uint),
                                format("Bad type %s for the %s instruction",
                                    BaseArg0.stringof, instr.name));
                            static if (is(BaseArg0==int) || is(BaseArg0==uint)) {
                                bout.write(encode(args[0]));
                            }
                            break;
                        case I64_CONST:
                            assert(isIntegral!(BaseArg0),
                                format("Bad type %s for the %s instruction",
                                    BaseArg0 .stringof, instr.name));
                            static if (isIntegral!(BaseArg0)) {
                                bout.write(encode(args[0]));
                            }
                            break;
                        case F32_CONST:
                            assert(is(BaseArg0:float),
                                format("Bad type %s for the %s instruction",
                                    Args[0].stringof, instr.name));
                            static if (is(BaseArg0:float)) {
                                float x=args[0];
                                bout.write(nativeToLittleEndian(x));
                            }
                            break;
                        case F64_CONST:
                            assert(is(BaseArg0:double), format("Bad type %s for the %s instruction",
                                    Args[0].stringof, instr.name));
                            static if (is(BaseArg0:double)) {
                                double x=args[0];
                                bout.write(nativeToLittleEndian(x));
                            }
                            break;
                        default:
                            assert(0, format("Bad const instruction %s", instr.name));
                        }
                    }
                }
                break;
            case END:
                assert(Args.length == 0, format("Instruction %s should have no arguments", instr.name));
            }
        }
        return this;
    }
}
