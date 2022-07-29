module tagion.tools.hibonutil;

import std.getopt;
import std.stdio;
import std.file : fread = read, fwrite = write, exists, readText;
import std.format;
import std.exception : assumeUnique, assumeWontThrow;
import std.json;
import std.range : only;

import tagion.hibon.HiBON : HiBON;
import tagion.hibon.Document : Document;
import tagion.basic.Types : FileExtension;
import tagion.basic.Basic : fileExtension;
import tagion.hibon.HiBONJSON;
import std.utf : toUTF8;
import std.encoding : BOMSeq, BOM;

import std.array : join;

import tagion.tools.Basic;

mixin Main!_main;

enum VERSION_HIBONUTIL = "1.9";

/**
 * @brief wrapper for BOM extracting
 */
const(BOMSeq) getBOM(string str) @trusted {
    import std.encoding : _getBOM = getBOM;
    return _getBOM(cast(ubyte[])str);
}

int _main(string[] args)
{
    immutable program = args[0];
    bool version_switch;

    string inputfilename;
    string outputfilename;
    bool pretty;
    auto logo = import("logo.txt");

    GetoptResult main_args;
    try
    {
        main_args = getopt(args,
            std.getopt.config.caseSensitive,
            std.getopt.config.bundling,
            "version", "display the version", &version_switch,
            "inputfile|i", "Sets the HiBON input file name", &inputfilename,
            "outputfile|o", "Sets the output file name", &outputfilename,
            "pretty|p", format("JSON Pretty print: Default: %s", pretty), &pretty,
        );
    }
    catch (std.getopt.GetOptException e)
    {
        writeln(e.msg);
        return 1;
    }

    if (version_switch)
    {
        writefln("version %s", VERSION_HIBONUTIL);
        return 0;
    }

    if (main_args.helpWanted)
    {
        writeln(logo);
        defaultGetoptPrinter(
            [
            "Documentation: https://tagion.org/",
            "",
            "Usage:",
            format("%s [<option>...] <in-file> <out-file>", program),
            format("%s [<option>...] <in-file>", program),
            "",
            "Where:",
            "<in-file>           Is an input file in .json or .hibon format",
            "<out-file>          Is an output file in .json or .hibon format",
            "                    stdout is used of the output is not specifed the",
            "",

            "<option>:",

        ].join("\n"),
        main_args.options);
        return 0;
    }

    if (args.length == 2)
    {
        inputfilename = args[1];
    }
    else if (args.length == 1 && !inputfilename)
    {
        stderr.writefln("Input file missing");
        return 1;
    }

    immutable standard_output = (outputfilename.length == 0);
    if (!exists(inputfilename))
    {
        writeln("File " ~ inputfilename ~ " not found");
        return 1;
    }

    switch (inputfilename.fileExtension)
    {
    case FileExtension.hibon:
        immutable data = assumeUnique(cast(ubyte[]) fread(inputfilename));
        const doc = Document(data);
        const error_code = doc.valid(
            (
                const(Document) sub_doc,
                const Document.Element.ErrorCode error_code,
                const(Document.Element) current, const(
                Document.Element) previous) nothrow{
            assumeWontThrow(writefln("%s", current));
            return true;
        });
        if (error_code !is Document.Element.ErrorCode.NONE)
        {
            writefln("Errorcode %s", error_code);
            return 1;
        }
        auto json = doc.toJSON;
        auto json_stringify = (pretty) ? json.toPrettyString : json.toString;
        if (standard_output)
        {
            writefln("%s", json_stringify);
        }
        else
        {
            outputfilename.fwrite(json_stringify);
        }
        break;
    case FileExtension.json:
        string text;
        try
        {
            text = inputfilename.readText;
        }
        catch(Exception e)
        {
            writeln(e.msg);
            return 1;
        }
        const bom = getBOM(text);
        with(BOM) switch(bom.schema)
        {
            case utf8:
                 text = text[bom.sequence.length..$];
            break;
            case none:
            //do nothing
            break;
            default:
                stderr.writefln("File type %s not supported", bom.schema);
                return 1;
        }

        HiBON hibon;
        try
        {
            auto parse = text.parseJSON;
            hibon = parse.toHiBON;
        }
        catch(HiBON2JSONException e)
        {
            writeln("Conversion error, please validate input JSON file");
            writeln(e.msg);
            return 1;
        }
        catch(JSONException e)
        {
            writeln("JSON syntax error");
            writeln(e.msg);
            return 1;
        }
        catch(Exception e)
        {
            writeln(e.msg);
            return 1;
        }
        if (standard_output)
        {
            write(hibon.serialize);
        }
        else
        {
            outputfilename.fwrite(hibon.serialize);
        }
        break;
    default:
        stderr.writefln("File %s not valid (only %(.%s %))",
            inputfilename, only(FileExtension.hibon, FileExtension.json));
        return 1;
    }

    return 0;
}
