module tagion.tools.tagionshell;

import tagion.tools.Basic;
import std.getopt;
import tagion.tools.revision;
import std.file : exists;
import tagion.tools.shell.shelloptions;


import std.stdio;


mixin Main!(_main, "shell");


int _main(string[] args) {
    immutable program = args[0];
    bool version_switch;
    GetoptResult main_args;


    ShellOptions options;
    
    auto config_file = "shell.json";
    if (config_file.exists) {
        options.load(config_file);
    } else {
        options.setDefault;
    }
    

    try {
        main_args = getopt(args, std.getopt.config.caseSensitive,
            std.getopt.config.bundling,
            "version", "display the version", &version_switch,
        );
    } catch (GetOptException e) {
        stderr.writeln(e.msg);
        return 1;
    }

    if (version_switch) {
        revision_text.writeln;
        return 0;
    }

    return 0;
}
