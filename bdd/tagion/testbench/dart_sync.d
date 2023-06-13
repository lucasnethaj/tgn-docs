module tagion.testbench.dart_sync;

import tagion.behaviour.Behaviour;
import tagion.testbench.functional;
import tagion.hibon.HiBONRecord : fwrite;
import tagion.tools.Basic;
import std.traits : moduleName;

import tagion.testbench.dart;
import tagion.testbench.tools.BDDOptions;
import tagion.testbench.tools.Environment;

import tagion.dart.DARTFakeNet : DARTFakeNet;
import tagion.crypto.SecureInterfaceNet : SecureNet, HashNet;
import tagion.communication.HiRPC : HiRPC;

import std.path : setExtension, buildPath;
import std.range : take;
import std.array;
import tagion.basic.Types : FileExtension;
import tagion.testbench.tools.Environment;

import tagion.testbench.dart.dartinfo;

mixin Main!(_main);

int _main(string[] args) {
    BDDOptions bdd_options;
    setDefaultBDDOptions(bdd_options);
    bdd_options.scenario_name = __MODULE__;

    const string module_path = env.bdd_log.buildPath(bdd_options.scenario_name);
    const string dartfilename = buildPath(module_path, "dart_sync_start_full".setExtension(FileExtension.dart));
    const string dartfilename2 = buildPath(module_path, "dart_sync_start_empty".setExtension(FileExtension.dart));

    const SecureNet net = new DARTFakeNet("very_secret");
    const hirpc = HiRPC(net);

    DartInfo dart_info = DartInfo(dartfilename, module_path, net, hirpc, dartfilename2);
    dart_info.states = dart_info.generateStates(0, 10).take(10).array;

    auto dart_sync_feature = automation!(basic_dart_sync)();
    dart_sync_feature.FullSync(dart_info);
    dart_sync_feature.run();


    return 0;


}