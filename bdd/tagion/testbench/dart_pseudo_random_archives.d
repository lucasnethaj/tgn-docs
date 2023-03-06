module tagion.testbench.dart_pseudo_random_archives;

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

import tagion.basic.Version;


mixin Main!(_main);


int _main(string[] args) {
    pragma(msg, "fixme(pr): add switch for running the test in commit stage with ex 10. and acceptance with ex 100.");

    if (env.stage == Stage.commit) {
        BDDOptions bdd_options;
        setDefaultBDDOptions(bdd_options);
        bdd_options.scenario_name = __MODULE__;

        const string module_path = env.bdd_log.buildPath(bdd_options.scenario_name);
        const string dartfilename = buildPath(module_path, "dart_pseudo_random_test".setExtension(FileExtension.dart));
        const SecureNet net = new DARTFakeNet("very_secret");
        const hirpc = HiRPC(net);


        DartInfo dart_info = DartInfo(dartfilename, module_path, net, hirpc);
        dart_info.states = dart_info.generateStates(1, 10).take(10).array;

        auto dart_pseudo_random_feature = automation!(dart_pseudo_random)();

        dart_pseudo_random_feature.AddPseudoRandomData(dart_info);
        
        auto dart_pseudo_random_context = dart_pseudo_random_feature.run();

    }

    return 0;


}



