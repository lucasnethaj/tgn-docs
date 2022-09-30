module tagion.utils.Escaper;

import std.format;
import std.algorithm.iteration : map, joiner;
import std.array : join;
import std.range.primitives : isInputRange;

//import std.range.primitives : ElementType;
import std.traits : ForeachType;
import std.range;
import std.string : indexOf;

enum special_chars = "ntr'\"\\";
enum code_esc_special_chars =
    format(q{enum escaped_special_chars="%s";},
            zip('\\'.repeat(special_chars.length),
            special_chars.map!(c => cast(char) c))
            .map!(m => only(m[0], m[1])).array.join);
//pragma(msg, code_esc_special_chars);
mixin(code_esc_special_chars);

/** 
    Range which takes a range of char and translate it to raw range of char 
*/
@safe
struct Escaper(S) if (isInputRange!S && is(ForeachType!S : const(char))) {
    protected {
        char escape_char;
        S range;
    }
    @disable this();
    this(S range) @nogc {
        this.range = range;
    }

    pure {
        bool empty() const {
            return range.empty;
        }

        char front() const {
            if (escape_char !is char.init) {
                return escape_char;
            }
            return cast(char) range.front;
        }

        void popFront() {
            if (escape_char is char.init) {
                const index = escaped_special_chars.indexOf(range.front);
                if (index < 0) {
                    range.popFront;

                    return;
                }
                escape_char = special_chars[index];
                return;
            }
            
        }
    }
}

@safe
Escaper!S escaper(S)(S range) {
    return Escaper!S(range);
}

    ///Examples: Escaping a text
@safe
unittest {
    import std.stdio;

    { //
    auto test = escaper("text");
    writefln("test = '%s'\n", test);
    assert(equal(test, "text");

    pragma(msg, isInputRange!(typeof("text")));
    pragma(msg, ForeachType!(typeof("text")));
}
