module tagion.utils.envexpand;

import std.typecons;
import std.algorithm;
import std.range;

enum bracket_pairs = [
        ["$(", ")"],
        ["${", "}"],
        ["$", ""],

    ];

@safe
string envExpand(string text, string[string] env, void delegate(string msg) error = null) pure {
    alias BracketState = Tuple!(string[], "bracket", ptrdiff_t, "index");
    static long envName(string str, string end_sym) pure {
        import std.uni;

        if (end_sym.length) {
            return str.countUntil(end_sym);
        }
        if ((str.length > 0) && !str[0].isAlpha) {
            return -1;
        }
        return (str ~ '!').countUntil!(c => !c.isAlphaNum);
    }

    string innerExpand(string str) {
        string result = str;

        auto begin = bracket_pairs
            .map!(bracket => BracketState(bracket, str.countUntil(bracket[0])))
            .filter!(state => state.index >= 0)
            .take(1);
        if (!begin.empty) {
            const state = begin.front;
            const env_start_index = state.index + state.bracket[0].length;
            auto end_str = innerExpand(str[env_start_index .. $]);
            const env_end_index = envName(end_str, state.bracket[1]);
            string env_value;
            if (env_end_index > 0) {
                const env_name = end_str[0 .. env_end_index];
                end_str = end_str[env_end_index + state.bracket[1].length .. $];
                env_value = env.get(env_name, null);
            }
            result = str[0 .. state.index] ~
                env_value ~
                innerExpand(end_str);
        }
        return result;

    }

    return innerExpand(text);
}

@safe
unittest {
    import std.stdio;

    writefln("%s", "text".envExpand(null));

    // Simple text without env expansion
    assert("text".envExpand(null) == "text");
    writefln("%s", "text$(NAME)".envExpand(null));
    // Expansion with undefined env
    assert("text$(NAME)".envExpand(null) == "text");
    writefln("%s", "text$(NAME)".envExpand(["NAME": "hugo"]));
    // Expansion where the env is defined
    assert("text$(NAME)".envExpand(["NAME": "hugo"]) == "texthugo");
    writefln("%s", "text${NAME}end".envExpand(["NAME": "hugo"]));
    // Full expansion 
    assert("text${NAME}end".envExpand(["NAME": "hugo"]) == "texthugoend");
    writefln("%s", "text$NAME".envExpand(["NAME": "hugo"]));
    // Environment without brackets
    assert("text$NAME".envExpand(["NAME": "hugo"]) == "texthugo");
    writefln("%s", "text$NAMEend".envExpand(["NAME": "hugo"]));
    // Undefined env without brackets expansion
    assert("text$NAMEend".envExpand(["NAME": "hugo"]) == "text");
    writefln("%s", "text$(OF${NAME})".envExpand(["NAME": "hugo"]));
    // Expansion of undefined environment of environment
    assert("text$(OF${NAME})".envExpand(["NAME": "hugo"]) == "text");

    writefln("%s", "text$(OF${NAME})".envExpand(["NAME": "hugo", "OFhugo": "_extra_"]));
    // Expansion of defined environment of environment
    assert("text$(OF${NAME})".envExpand(["NAME": "hugo", "OFhugo": "_extra_"]) == "text_extra_");

    writefln("%s", "text$(OF${NAME}_end)".envExpand(["NAME": "hugo", "OFhugo": "_extra_", "OFhugo_end": "_other_extra_"]));
    // Expansion of defined environment of environment
    assert("text$(OF$(NAME)_end)".envExpand([
        "NAME": "hugo",
        "OFhugo": "_extra_",
        "OFhugo_end": "_other_extra_"
    ]) == "text_other_extra_");

}
