module tagion.testbench.dart_sync_stress;


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
import tagion.crypto.SecureNet : StdSecureNet;

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

    if (env.stage == Stage.performance) {
        BDDOptions bdd_options;
        setDefaultBDDOptions(bdd_options);
        bdd_options.scenario_name = __MODULE__;

        const string module_path = env.bdd_log.buildPath(bdd_options.scenario_name);
        const string dartfilename = buildPath(module_path, "dart_sync_stress_test".setExtension(FileExtension.dart));
        const string dartfilename2 = buildPath(module_path, "dart_sync_start_slave".setExtension(FileExtension.dart));

        
        SecureNet net;
        bool real_hashes;

        if (real_hashes) {
            net = new DARTFakeNet("very secret");
        } else {
            net = new StdSecureNet();
            net.generateKeyPair("very secret");
        }
        
        const hirpc = HiRPC(net);

        DartInfo dart_info = DartInfo(dartfilename, module_path, net, hirpc, dartfilename2);
       

        auto dart_sync_stress_feature = automation!(dart_sync_stress)();
        dart_sync_stress_feature.AddRemoveAndReadTheResult(dart_info, env.getSeed, 100_000, 1000, 1000);

        auto dart_sync_context = dart_sync_stress_feature.run();

    } 

 


    return 0;


}