module tagion.behaviour.BehaviourIssue;

import tagion.behaviour.BehaviourBase;
import std.traits;
import std.algorithm : each, map;
import std.range : tee;
import std.format;

MarkdownT!(Stream) Markdown(Stream)(Stream bout) {
    alias MasterT=MarkdownT!Stream;
    MasterT.master=masterMarkdown;
    return MasterT(bout);
}

DlangT!(Stream) Dlang(Stream)(Stream bout) {
    alias MasterT=DlangT!Stream;
    auto result=MasterT(bout);
//    result.master=masterDlang;g
    return result;
}

struct MarkdownFMT{
    string indent;
    string name;
    string scenario;
    string feature;
    string property;
}

static MarkdownFMT masterMarkdown = {
indent : "  ",
name : "`%2$s`",
scenario :"### %2$s: %3$s",
feature : "## %2$s: %3$s",
property : "%s*%s* %s",
};

// static FMT masterDlang = {
// indent : "  ",
// name : "`%2$s`",
// scenario :"### %2$s: %3$s",
// feature : q{module %2$s %3$s;},
// property : "%s*%s* %s",
// };


enum EXT {
    Markdown="md",
    Dlang="d",
}


@safe
struct MarkdownT(Stream) {
    Stream bout;
    //  enum property_fmt="%s*%s* %s"; //=function(string indent, string propery, string description);
    static MarkdownFMT master;

    void issue(Descriptor)(const(Descriptor) descriptor, string indent, string fmt) if(isDescriptor!Descriptor) {
        bout.writefln(fmt, indent, Descriptor.stringof, descriptor.description);
    }

    void issue(I)(const(I) info, string indent, string fmt) if (isInfo!I) {
        issue(info.property, indent, fmt);
        bout.writeln;
        bout.writefln(master.name, indent~master.indent, info.name); //
    }

    void issue(Group)(const(Group) group, string indent, string fmt) if (isBehaviourGroup!Group) {
        if (group !is group.init) {
            issue(group.info, indent, master.property);
            group.ands
                .each!(a => issue(a, indent~master.indent, fmt));
        }
    }

    void issue(const(ScenarioGroup) scenario_group, string indent=null) {
        issue(scenario_group.info, indent, master.scenario);
        issue(scenario_group.given, indent~master.indent, master.property);
        issue(scenario_group.then, indent~master.indent, master.property);
        issue(scenario_group.when, indent~master.indent, master.property);
    }

    void issue(const(FeatureGroup) feature_group, string indent=null) {
        issue(feature_group.info, indent, master.feature);
        feature_group.scenarios
            .tee!(a => bout.writeln)
            .each!(a => issue(a, indent~master.indent));
    }
}


unittest { // Markdown scenario test
    auto bout=new OutBuffer;
    auto markdown = Markdown(bout);
//    pragma(msg, "markdown_call ", FunctionTypeOf!(markdown_func));
    alias unit_mangle=mangleFunc!(MarkdownU);
//Markdown!OutBuffer); //markdown_call)); //Markdown(bout)));
//    issueMakedown!(tagion.behaviour.BehaviourUnittest)(bout);
    auto awesome = new Some_awesome_feature;
    const runner_awesome=scenario(awesome);
//    ScenarioGroup scenario=getScenarioGroup!Some_awesome_feature;
    const scenario_result = runner_awesome();
    {
        scope(exit) {
            bout.clear;
        }
        immutable filename=unit_mangle("descriptor")
            .unitfile
            .setExtension(EXT.Markdown);
        markdown.issue(scenario_result.given.info, null, markdown.master.property);
        writefln("bout=%s", bout);
        filename.fwrite(bout.toString);
    }
    {
        scope(exit) {
            bout.clear;
        }
        immutable filename=unit_mangle("scenario")
            .unitfile
            .setExtension(EXT.Markdown);
        markdown.issue(scenario_result);
        writefln("bout=%s", bout);
        filename.write(bout.toString);
    }
//    assert(bout.toString == "Not code");
}

unittest {
    auto bout=new OutBuffer;
    auto markdown = Markdown(bout);
    alias unit_mangle=mangleFunc!(MarkdownU);
//Markdown!OutBuffer); //markd
    const feature_group = getFeature!(tagion.behaviour.BehaviourUnittest);
    {
        scope(exit) {
            bout.clear;
        }
        immutable filename=unit_mangle("feature")
            .unitfile
            .setExtension(EXT.Markdown);
        markdown.issue(feature_group);
//        writefln("bout=%s", bout);
        filename.fwrite(bout.toString);
    }

}

unittest {
    auto bout=new OutBuffer;
    auto dlang = Dlang(bout);
    alias unit_mangle=mangleFunc!(DlangU);
    const feature_group = getFeature!(tagion.behaviour.BehaviourUnittest);
    {
        scope(exit) {
            bout.clear;
        }
        immutable filename=unit_mangle("feature")
            .unitfile
            .setExtension(EXT.Dlang);
        dlang.issue(feature_group);
        filename.fwrite(bout.toString);
    }
}

@safe
struct DlangT(Stream) {
    Stream bout;
    //  enum property_fmt="%s*%s* %s"; //=function(string indent, string propery, string description);
    static MarkdownFMT master;

    void issue(Descriptor)(const(Descriptor) descriptor, string indent, string fmt) if(isDescriptor!Descriptor) {
        bout.writefln(fmt, indent, Descriptor.stringof, descriptor.description);
    }

    void issue(I)(const(I) info, string indent, string fmt) if (isInfo!I) {
        issue(info.property, indent, fmt);
        bout.writeln;
        bout.writefln(master.name, indent~master.indent, info.name); //
    }

    void issue(Group)(const(Group) group, string indent, string fmt) if (isBehaviourGroup!Group) {
        if (group !is group.init) {
            issue(group.info, indent, master.property);
            group.ands
                .each!(a => issue(a, indent~master.indent, fmt));
        }
    }

    string issue(const(ScenarioGroup) scenario_group, string indent=null) {
        immutable scenario_param=format(
            `"%s",\n[%-("%3$s"%,\n%)]`,
            scenario_group.info.property.description,
            scenario_group.info.property.comments
            );
        return format(q{
                @safe
                    @Scenario(%1$s)
                    class %2$s {
                    %3$s
                        }
            },
            scenario_param,
            scenario_group.info.name,
            "// code");
//        issue(scenario_group.info, indent, master.scenario);
        // issue(scenario_group.given, indent~master.indent, master.property);
        // issue(scenario_group.then, indent~master.indent, master.property);
        // issue(scenario_group.when, indent~master.indent, master.property);
    }

    void issue(const(FeatureGroup) feature_group, string indent=null) {
        immutable comments=format(`[%-("%3$s"%,\n%)]`, feature_group.info.property.comments);
        bout.writefln(q{
                module %1$s;
                // Auto generated imports
                import tagion.behaviour.BehaviourBase;

                enum feature = Feature(
                    "%2$s",
                    %3$s);

            },
            feature_group.info.name,
            feature_group.info.property.description,
            comments);
//            feature_group.property.descriptions);


        // issue(feature_group.info, indent, master.feature);
        feature_group.scenarios
            .map!(a => issue(a, indent~master.indent))
            .each!(a => bout.writeln(a));
        bout.writeln("// End");

        writefln("End of %s", __FUNCTION__);
             // .tee!(a => bout.writeln)
             // .each!(a => issue(a, indent~master.indent));
    }
}

unittest {
    auto bout=new OutBuffer;
    auto dlang = Dlang(bout);
    alias unit_mangle=mangleFunc!(DlangU);
    const feature_group = getFeature!(tagion.behaviour.BehaviourUnittest);
    {
        scope(exit) {
            bout.clear;
        }
        immutable filename=unit_mangle("feature")
            .unitfile
            .setExtension(EXT.Dlang);
        dlang.issue(feature_group);
        bout.writeln("End of file %s", );
        filename.fwrite(bout.toString);
    }
}

version(unittest) {
    import tagion.basic.Basic : mangleFunc, unitfile;
    import tagion.behaviour.BehaviourUnittest;
    import tagion.behaviour.Behaviour;
    import tagion.hibon.Document;
    alias MarkdownU=Markdown!OutBuffer;
    alias DlangU=Dlang!OutBuffer;

    import std.file : fwrite=write, fread=read;
    import std.stdio;
    import std.path;
    import std.outbuffer;
}
