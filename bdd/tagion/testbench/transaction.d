module tagion.testbench.transaction;

import tagion.behaviour.Behaviour;
import tagion.testbench.functional;
import tagion.hibon.HiBONRecord : fwrite;
import std.stdio;

import tagion.tools.Basic;
import std.traits : moduleName;
import tagion.testbench.tools.utils : Genesis;
import tagion.testbench.tools.BDDOptions;
import tagion.testbench.tools.Environment;

import std.format;

mixin Main!(_main, "functional");

int _main(string[] args)
{
    if (env.stage == Stage.acceptance) {
        string scenario_name = __MODULE__;

        BDDOptions bdd_options;
        setDefaultBDDOptions(bdd_options);
        bdd_options.scenario_name = __MODULE__;
        bdd_options.network.mode = 1;
        bdd_options.network.monitor = true;

        bdd_options.save(format("/tmp/%s.json", scenario_name));

        auto create_wallets_feature = automation!(create_wallets)();
        create_wallets_feature.GenerateNWallets(bdd_options);
        auto create_wallets_context = create_wallets_feature.run;

        auto create_dart_feature = automation!(create_dart)();
        create_dart_feature.GenerateDart(create_wallets_context.GenerateNWallets, bdd_options);
        auto create_dart_context = create_dart_feature.run;

        auto create_network_in_mode_one_feature = automation!(create_network_in_mode_one)();
        create_network_in_mode_one_feature.CreateNetworkWithNAmountOfNodesInModeone(create_dart_context.GenerateDart,
            create_wallets_context.GenerateNWallets, bdd_options);
        auto create_network_in_mode_one_context = create_network_in_mode_one_feature.run;

        auto create_transaction_feature = automation!(create_transaction)();
        create_transaction_feature.CreateTransaction(
            create_wallets_context.GenerateNWallets,
            create_network_in_mode_one_context.CreateNetworkWithNAmountOfNodesInModeone,
            bdd_options,
        );
        auto create_transaction_context = create_transaction_feature.run;

        auto double_spend_feature = automation!(create_double_spend);
        writefln("%s", bdd_options);
        bdd_options.genesis_wallets.wallets[0].amount = create_transaction_context.CreateTransaction.wallet_0.total;
        bdd_options.genesis_wallets.wallets[1].amount = create_transaction_context.CreateTransaction.wallet_1.total;

        writefln("%s", bdd_options);
        double_spend_feature.DoubleSpendSameWallet(create_wallets_context.GenerateNWallets,
            create_network_in_mode_one_context.CreateNetworkWithNAmountOfNodesInModeone,
            bdd_options,
        );

        auto double_spend_context = double_spend_feature.run;

        auto kill_network_feature = automation!(kill_network)();
        kill_network_feature.KillTheNetworkWithPIDS(
            create_network_in_mode_one_context.CreateNetworkWithNAmountOfNodesInModeone, bdd_options);
        auto kill_network_context = kill_network_feature.run;
    }
    return 0;

}
