import std.getopt;
import std.stdio;
import std.file: exists;
import std.format;
import std.algorithm : map, max, min;
import std.range : lockstep;
import std.array;
import std.string : strip, toLower;
import std.conv : to;
import std.array : join;
import std.exception : assumeUnique;
import std.string : representation;
import core.time : MonoTime;
import std.socket : InternetAddress, AddressFamily;
import core.thread;

import tagion.hibon.HiBON : HiBON;
import tagion.hibon.Document : Document;
import tagion.hibon.HiBONRecord;
import tagion.hibon.HiBONJSON;

import tagion.basic.Basic : basename, Buffer, Pubkey;
import tagion.script.StandardRecords;
import tagion.crypto.SecureNet : StdSecureNet, StdHashNet, scramble;
import tagion.wallet.KeyRecover;
import tagion.utils.Term;
import tagion.basic.Message;
import tagion.utils.Miscellaneous;
import tagion.script.StandardRecords : Invoice;
import tagion.communication.HiRPC;
import tagion.network.SSLSocket;
import tagion.Keywords;

//import tagion.revision;

enum LINE="------------------------------------------------------";

StdSecureNet net;

enum ulong AXION_UNIT=1_000_000;
enum ulong AXION_MAX=1_000_000*AXION_UNIT;

ulong toAxion(const double amount) pure {
    auto result=AXION_UNIT*amount;
    if (result > AXION_MAX) {
        result=AXION_MAX;
    }
    return cast(ulong)result;
}

double toTagion(const ulong amount) pure {
    return (cast(real)amount)/AXION_UNIT;
}

string TGN(const ulong amount) pure {
    const ulong tagions=amount/AXION_UNIT;
    const ulong axions=amount % AXION_UNIT;
    return format("%d.%d TGN", tagions, axions);
}

// Order
// Is defined as information's which the customer send to receive get payment information (pubkeys)
//

// Invoice
// Is defined as information's which the seller generates to the costumer about the (pubkeys)
//

Buffer drive_state;
void writeAccounts(string file, Buffer[Pubkey] accounts) {
    if (accounts.length) {
        auto hibon_accounts=new HiBON;
        foreach(hashpkey, drive; accounts) {
            hibon_accounts[hashpkey.toHexString]=drive;
        }
        auto hibon=new HiBON;
        hibon["state"]=drive_state;
        hibon[accounts.stringof]=hibon_accounts;
        file.fwrite(hibon);
    }
}

Buffer[Pubkey] readAccounts(string file) {
    Buffer[Pubkey] accounts;
    if (file.exists) {
        const doc=file.fread;
        // immutable data=assumeUnique(cast(ubyte[])file.fread);
        // const doc=Document(data);
        // if (doc.isInOrder) {
        drive_state=doc["state"].get!Buffer;
        const doc_accounts=doc[accounts.stringof].get!Document;
        foreach(e; doc_accounts[]) {
            Pubkey key=decode(e.key);
            accounts[key]=e.get!Buffer;
            // }
        }
    }
    return accounts;
}

ulong calcTotal(const(StandardBill[]) bills) {
    ulong result;
    foreach(b; bills) {
        result+=b.value;
    }
    return result;
}

ulong calcTotal(const(Invoice[]) invoices) {
    ulong result;
    foreach(b; invoices) {
        result+=b.amount;
    }
    return result;
}


void updateBills(string file, StandardBill[] bills) {
    import tagion.dart.DARTFile;
    if (bills.length) {
        auto bills_hibon=new HiBON;
        foreach(i, bill; bills) {
            HiBON archive = new HiBON;
            archive[DARTFile.Params.archive] = bill.toHiBON;
            archive[DARTFile.Params.type]=cast(uint)(DARTFile.Recorder.Archive.Type.ADD);
            bills_hibon[i] = archive;
        }
        file.fwrite(bills_hibon);
    }
}

StandardBill[] readBills(string file) {
    StandardBill[] result;
    if (file.exists) {
        const doc_recorder=file.fread;
        if (doc_recorder.isInorder && doc_recorder.isArray) {
            foreach(e; doc_recorder[]) {
                const doc_archive=e.get!Document;
                const doc_bill=doc_archive["archive"].get!Document;
                auto bill=StandardBill(doc_bill);
                Pubkey pkey=bill.owner;
                if (pkey in accounts) {
                    result~=bill;
                }
            }
        }
    }
    return result;
}

string accountfile="account.hibon";
Buffer[Pubkey] accounts;

string walletfile="tagionwallet.hibon";

void warning() {
    writefln("%sWARNING%s: This wallet should only be used for the Tagion Dev-net%s", RED, BLUE, RESET);
}

Invoice[] readInvoices(string file) {
    Invoice[] result;
    if (file.exists) {
        const doc=file.fread;
        if (doc.isInorder && doc.isArray) {
            foreach(e; doc[]) {
                const sub_doc=e.get!Document;
                result~=Invoice(sub_doc);
            }
        }
    }
    return result;
}

//alias ContractT=Contract!(ContractType.INTERNAL);
bool payment(const(Invoice[]) orders, const(StandardBill[]) bills, ref SignedContract result) {
    if (net) {
        const topay=calcTotal(orders);

        StandardBill[] contract_bills;
        if (topay > 0) {
            string source;
            uint count;
            foreach(o; orders) {
                source=assumeUnique(format("%s %s", o.amount, source));
                count++;
            }

            // Input
            ulong amount=topay;


            foreach(b; bills) {
                amount-=min(amount, b.value);
                contract_bills~=b;
                if (amount == 0) {
                    break;
                }
            }
            if(amount != 0){
                return false;
            }
//        result.input=contract_bills; // Input bills
//        Buffer[] inputs;
            foreach(b; contract_bills) {
                result.contract.input~=net.calcHash(b.toHiBON.serialize);
            }
            const _total_input=calcTotal(contract_bills);
            if ( _total_input >= topay) {
                const _rest=_total_input-topay;
                count++;
                result.contract.script=assumeUnique(format("%s %s %d pay", source, _rest, count));
                // output
                Invoice money_back;
                money_back.amount=_rest;
                createInvoice(money_back);
                result.contract.output~=money_back.pkey;
                foreach(o; orders) {
                    result.contract.output~=o.pkey;
                }
            }
            else {
                return false;
            }
        }

        // Sign all inputs
        immutable message=net.calcHash(result.contract.toHiBON.serialize);
        shared shared_net=cast(shared)net;
        foreach(i, b; contract_bills) {
            Pubkey pkey=b.owner;
            if (pkey in accounts) {
                writefln("%d] b.owner        %s", i, b.owner.toHexString);
                writefln("%d] account        %s", i, net.derivePubkey(accounts[pkey]).toHexString);
                immutable tweak_code=accounts[pkey];
                auto bill_net=new StdSecureNet;
                bill_net.derive(tweak_code, shared_net);
                immutable signature=bill_net.sign(message);
                result.signs~=signature;
                writefln("signed %5s pkey=%s", net.verify(message, signature, pkey), pkey.toHexString);
            }
        }

//    result.contract=Document(contract);
        return true;
    }
    return false;
}

void createInvoice(ref Invoice invoice) {
    string current_time=MonoTime.currTime.toString;
    scope seed=new ubyte[net.hashSize];
    scramble(seed);
    drive_state=net.calcHash(seed~drive_state~current_time.representation);
    scramble(seed);
//                invoice.drive=drive_state;

    const pkey=net.derivePubkey(drive_state);
    invoice.pkey=cast(Buffer)pkey;
    accounts[pkey]=drive_state;
}

string contractfile="contract.hibon";
string billsfile="bills.hibon";
string invoicefile="invoice.hibon";
Invoice[] invoices;
Invoice[] orders;
StandardBill[] bills;

void accounting() {
    int ch;
    KeyStroke key;

    if (drive_state.length is 0) {
        const seed="invoices";
        drive_state=net.calcHash(seed.representation);
    }

    write(CLEARSCREEN);
    scope(success) {
        write(CLEARSCREEN);
    }

    scope(success) {
        if (invoices.length) {
            auto hibon=new HiBON;
            foreach(i, ref invoice; invoices) {
                const index=cast(uint)i;
                /++
                 string current_time=MonoTime.currTime.toString;
                 scope seed=new ubyte[net.hashSize];
                 scramble(seed);
                 drive_state=net.calcHash(seed~drive_state~current_time.representation);
                 scramble(seed);
//                invoice.drive=drive_state;

                const pkey=net.drivePubkey(drive_state);
                invoice.pkey=cast(Buffer)pkey;
                accounts[pkey]=drive_state;
                +/
                createInvoice(invoice);
                hibon[index]=invoice.toHiBON;
            }
            invoicefile.fwrite(hibon);
            accountfile.writeAccounts(accounts);
        }
    }

    uint select_index = 0;
    uint selected = uint.max;
    const _total=calcTotal(bills);
    while (ch != 'q') {
        write(HOME);
        warning();
        writefln(" Invoices ");
        writefln(LINE);
        writefln("                                 total %s", TGN(_total));
        writefln(LINE);
        if (invoices) {
            foreach(i, a; invoices) {
                string select_code;
                string chosen_code;
                if ( select_index == i ) {
                    select_code = BLUE~BACKGOUND_WHITE;
                }
                if (selected == i) {
                    chosen_code = GREEN;
                }
                // const ulong tagions=a.amount/AXION_UNIT;
                // const ulong axions=a.amount % AXION_UNIT;

                writefln("%2d %s%s%s %s%s", i, select_code, chosen_code, a.name, TGN(a.amount), RESET);
            }
            writefln(LINE);
            writefln("%sq%s:quit %si%s:invoice %sEnter%s:select %sUp/Down%s:move              ",
                FKEY,RESET,FKEY,RESET,FKEY,RESET,FKEY,RESET,
            );
        }
        else {
            writefln("%sq%s:quit %si%s:invoice ",
                FKEY,RESET,FKEY,RESET,
                );
        }
        writeln(CLEARDOWN);
        const keycode=key.getKey(ch);

        with(KeyStroke.KeyCode) {
            switch (keycode) {
            case UP:
                if (invoices.length) {
                    select_index = (select_index-1) % invoices.length;
                }
                break;
            case DOWN:
                if (invoices.length) {
                    select_index = (select_index+1) % invoices.length;
                }
                break;
            case ENTER:
                selected=select_index;
                // writefln("%s%s%s", questions[select_index], CLEAREOL, CLEARDOWN);
                // answers[select_index]=readln.strip;
                //writefln("line=%s", answers[select_index]);
                break;
            case NONE:
                switch(ch) {
                case 'i':
                    writeln("Item name");
                    Invoice new_invoice;
                    new_invoice.name=readln.strip;
                    if (new_invoice.name.length==0 || (new_invoice.name[0]==':')) {
                        break;
                    }
                    writefln("Price in TGN");
                    const amount_tagion=readln.strip;
                    if (amount_tagion.length==0 || (amount_tagion[0]==':')) {
                        break;
                    }
                    new_invoice.amount=toAxion(amount_tagion.to!double);
                    if (new_invoice.amount) {
                        invoices~=new_invoice;
                    }
                    write(CLEARSCREEN);
                    break;
                default:
                    // ignore
                }
                break;
            default:
                // ignore
            }
        }
    }
}

bool loginPincode(string pincode) {
    auto hashnet=new StdHashNet;
    auto recover=new KeyRecover(hashnet);
    auto pinhash=recover.checkHash(pincode.representation);
    //writefln("pinhash=%s", pinhash.toHexString);
    auto R=new ubyte[hashnet.hashSize];
    xor(R, wallet.Y, pinhash);
    if (wallet.check == recover.checkHash(R)) {
        net=new StdSecureNet;
        net.createKeyPair(R);
        return true;
    }
    return false;
}

Wallet* wallet;

void accountView() {

    enum State {
        CREATE_ACCOUNT,
        WAIT_LOGIN,
        LOGGEDIN
    }
    State state;

    version(none)
        if (walletfile.exists) {
            immutable data=assumeUnique(cast(ubyte[])walletfile.fread);
            const doc=Document(data);
            if (doc.isInorder) {
                auto hashnet=new StdHashNet;
                wallet=new Wallet(doc);
                state=State.WAIT_LOGIN;
            }
        }

    if (wallet !is null) {
        if (net is null) {
            state=State.WAIT_LOGIN;
        }
        else {
            state=State.LOGGEDIN;
        }
    }

    int ch;
    KeyStroke key;
    write(CLEARSCREEN);
    while(ch != 'q') {
        write(HOME);
        warning();
        const _total=calcTotal(bills);
        writefln(" Account overview ");
        writefln(LINE);
        writefln("                                 total %s", TGN(_total));
        writefln(LINE);
        with(State) final switch(state) {
            case CREATE_ACCOUNT:
                writefln("%sq%s:quit %sa%s:account %sc%s:create%s",
                    FKEY, RESET, FKEY, RESET, FKEY, RESET, CLEARDOWN
                    );
                break;
            case WAIT_LOGIN:
                writefln("Pincode:%s", CLEARDOWN);
                auto pincode=readln.strip;
                version(none) {
                    auto hashnet=new StdHashNet;
                    auto recover=new KeyRecover(hashnet);
                    auto pinhash=recover.checkHash(pincode.representation);
                    //writefln("pinhash=%s", pinhash.toHexString);
                    auto R=new ubyte[hashnet.hashSize];
                    xor(R, wallet.Y, pinhash);
                    if (wallet.check == recover.checkHash(R)) {
                        net=new StdSecureNet;
                        net.createKeyPair(R);
                        state=LOGGEDIN;
                        continue;
                    }
                    else {
                        writefln("%sWrong pin%s", RED, RESET);
                        writefln("Press %sEnter%s", YELLOW, RESET);
                    }
                }
                if (loginPincode(pincode)) {
                    state=LOGGEDIN;
                    continue;
                }
                else {
                    writefln("%sWrong pin%s", RED, RESET);
                    writefln("Press %sEnter%s", YELLOW, RESET);
                }
                break;
            case LOGGEDIN:
                version(none) {
                    writefln("%sq%s:quit %sa%s:account %sr%s:recover%s",
                        FKEY, RESET, FKEY, RESET, FKEY, RESET, CLEARDOWN
                        );
                }
                else {
                    writefln("%sq%s:quit %sa%s:account%s",
                        FKEY, RESET, FKEY, RESET, CLEARDOWN
                        );
                }
                break;
            }
        writeln(CLEARDOWN);
        const keycode=key.getKey(ch);
        switch(ch) {
        case 'a':
            if(walletfile.exists){
                accounting;
            }else{
                writeln("Account doesn't exists");
                Thread.sleep(1.seconds);
            }
            break;
        case 'c':
            generateSeed(standard_questions.idup, false);
            break;
            version(none) {
                case 'r':
                    generateSeed(standard_questions.idup, true);
                    break;
            }
        default:
            // ignore
        }
    }
}

enum FKEY=YELLOW;

HiBON generateSeed(const(string[]) questions, const bool recover_flag) {
    auto answers=new string[questions.length];
    auto translated_questions=questions.map!(s => message(s));
    uint select_index = 0;
    uint confidence;
//    import core.stdc.stdio : getc, stdin;
    int ch;
    KeyStroke key;
    write(CLEARSCREEN);
    scope(success) {
        write(CLEARSCREEN);
    }

    while (ch != 'q') {
        write(HOME);
        warning();
        writefln("Create a new account");
        writefln("Answers two to more of the questions below");
        writefln(LINE);
        uint number_of_answers;
        foreach(i, question, answer; lockstep(translated_questions, answers)) {
            string select_code;
            string chosen_code;
            if ( select_index == i ) {
                select_code = BLUE~BACKGOUND_WHITE;
            }
            if (answer.length) {
                chosen_code = GREEN;
                number_of_answers++;
            }
            writefln("%2d %s%s%s %s%s%s", i, select_code, chosen_code, question, CLEAREOL, answer, RESET);
        }
        confidence=min(confidence, number_of_answers);
        writefln("Confidence %d", confidence);

        writefln(LINE);
        writefln("%sq%s:quit %sEnter%s:select %sUp/Down%s:move %sLeft/Right%s:confidence %sc%s:create%s",
            FKEY,RESET,FKEY,RESET,FKEY,RESET,FKEY,RESET,FKEY,RESET,CLEARDOWN
            );

        const keycode=key.getKey(ch);
        with(KeyStroke.KeyCode) {
            switch (keycode) {
            case UP:
                select_index = (select_index-1) % questions.length;
                break;
            case DOWN:
                select_index = (select_index+1) % questions.length;
                break;
            case LEFT:
                if ( confidence > 2 ) {
                    confidence--;
                }
                break;
            case RIGHT:
                confidence=max(confidence+1, number_of_answers);
                break;
            case ENTER:
                writefln("%s%s%s", questions[select_index], CLEAREOL, CLEARDOWN);
                auto answer=readln.strip;
                // writefln("answer.length=%d", answer.length);
                answers[select_index]=answer;
                confidence++;
                //writefln("line=%s", answers[select_index]);
                break;
            case NONE:
                switch(ch) {
                case 'c':
                    string[] selected_questions;
                    string[] selected_answers;
                    foreach(i, question, answer; lockstep(questions, answers)) {
                        if (answer.length) {
                            selected_questions~=question.idup;
                            selected_answers~=answer.idup;
                        }
                    }

                    if (selected_questions.length < 3) {
                        writefln("Answers must be more than %d%s", selected_questions.length, CLEAREOL);
                    }
                    else {
                        auto hashnet = new StdHashNet;
                        auto recover = KeyRecover(hashnet);

                        if (confidence == selected_questions.length) {
                            // Due to some bug in KeyRecover
                            confidence--;
                        }

                        recover.createKey(selected_questions, selected_answers, confidence);
                        string pincode1;
                        string pincode2;
                        bool ok;
                        do {
                            writefln("Pincode:%s", CLEARDOWN);
                            pincode1=readln.strip;
                            writefln("Repeate:");
                            pincode2=readln.strip;
                            if (pincode1 != pincode2) {
                                writefln("%sPincode is not the same%s", RED, RESET);
                            }
                            else if (pincode1.length>4) {
                                writefln("%sPincode must be more than 4 chars%s", RED, RESET);
                            }
                            else {
                                writefln("%sWallet created%s", GREEN, RESET);
                                writefln("Press %sEnter%s", YELLOW, RESET);
                                ok=true;
                            }
                        } while (!ok);

                        Wallet wallet;
                        {
                            net=new StdSecureNet;
                            auto R=new ubyte[net.hashSize];

                            recover.findSecret(R, selected_questions, selected_answers);
                            //writefln("R=0x%s", R.idup.hex);
                            import std.string : representation;
                            auto pinhash=recover.checkHash(pincode1.representation);
                            //writefln("R.length=%d pinhash.length=%d", R.length, pinhash.length);
                            wallet.Y=xor(R, pinhash);
                            wallet.check=recover.checkHash(R);
                            net.createKeyPair(R);
                            wallet.pubkey=net.pubkey;
                            const seed_data=recover.toHiBON.serialize;
                            const seed_doc=Document(seed_data);
                            wallet.seed=KeyRecover.RecoverSeed(seed_doc);

                        }
                        walletfile.fwrite(wallet.toHiBON);
                        readln;
                    }
                    break;
                default:
                    // ignore
                }
                break;
            default:
                // ignore
            }
        }

    }
    return null;
}

enum REVNO=0;
enum HASH="xxx";

int main(string[] args) {
    immutable program=args[0];
    bool version_switch;
    string payfile;
    bool wallet_ui;
    bool update_wallet;
    uint number_of_bills;
    string passphrase="verysecret";
    ulong value=1000_000_000;
    bool generate_wallet;
    string item;
    string pincode;
    string addr="localhost";
    ushort port=10800;
    bool send_flag;
    string create_invoice_command;
    bool print_amount;
    //   pragma(msg, "bill_type ", GetLabel!(StandardBill.bill_type));
    auto main_args = getopt(args,
        std.getopt.config.caseSensitive,
        std.getopt.config.bundling,
        "version",   "display the version",     &version_switch,
        "wallet|w",  format("Walletfile : default %s", walletfile), &walletfile,
        "invoice|c",  format("Invoicefile : default %s", invoicefile), &invoicefile,
        "create-invoice", "Create invoice by format LABEL:PRICE. Example: Foreign_invoice:1000", &create_invoice_command,
        "contract|t", format("Contractfile : default %s", contractfile), &contractfile,
        "send|s", "Send contract to the network", &send_flag,
        "amount", "Display the wallet amount", &print_amount,
        "pay|I",  format("Invoice to be payed : default %s", payfile), &payfile,
        "update|U", "Update your wallet", &update_wallet,
        "item|m",  "Invoice item select from the invoice file", &item,
        "pin|x",  "Pincode", &pincode,
        "port|p", format("Tagion network port : default %d", port), &port,
        "url|u",  format("Tagion url : default %s", addr), &addr,
        "visual|g", "Visual user interface", &wallet_ui,
        );

    if (version_switch) {
        writefln("version %s", REVNO);
        writefln("Git handle %s", HASH);
        return 0;
    }

    if (walletfile.exists) {
        const doc=walletfile.fread;
        if (doc.isInorder) {
            auto hashnet=new StdHashNet;
            wallet=new Wallet(doc);
//            state=State.WAIT_LOGIN;
        }
    }

    if ((wallet !is null) && pincode) {
        const flag=loginPincode(pincode);
        if (!flag) {
            stderr.writefln("%sWrong pincode%s", RED, RESET);
            return 3;
        }
    }

    if (accountfile.exists) {
        accounts=accountfile.readAccounts;
    }

    if (billsfile.exists) {
        bills=billsfile.readBills;
    }

    if (payfile.exists) {
        orders=payfile.readInvoices;
        // const contract=payment(orders, bills);
        // contractfile.fwrite(contract.toHiBON.serialize);
    }

    if ( main_args.helpWanted ) {
        defaultGetoptPrinter(
            [
                format("%s version %s", program, REVNO),
                "Documentation: https://tagion.org/",
                "",
                "Usage:",
                format("%s [<option>...]", program),
                "",
                // "Where:",
                // format("<file>           hibon outfile (Default %s", outputfilename),
                // "",

                "<option>:",

                ].join("\n"),
            main_args.options);
        return 0;
    }

    if(update_wallet){
        HiRPC hirpc;
        Buffer prepareSearch(Buffer[] owners){
            HiBON params = new HiBON;
            foreach(i, owner; owners){
                params[i] = owner;
            }
            const sender=hirpc.action("search", params);
            immutable data=sender.toDoc.serialize;
            return data;
        }

        // writeln(accounts.length);
        StandardBill[] new_bills;
        Buffer[] pkeys;
        foreach(pkey, dkey; accounts){
            pkeys~=cast(Buffer)pkey;
        }
        auto client = new SSLSocket(AddressFamily.INET, EndpointType.Client);
        client.connect(new InternetAddress(addr, port));
        scope(exit) {
            client.close;
        }
        client.blocking=true;
        // writefln("looking for %s", (cast(Buffer)pkey).toHexString);
        auto to_send = prepareSearch(pkeys);
        client.send(to_send);

        auto rec_buf=new void[4000];
        ptrdiff_t rec_size;

        do {
            rec_size = client.receive(rec_buf); //, current_max_size);
            // writefln("read rec_size=%d", rec_size);
            Thread.sleep(400.msecs);
        } while (rec_size < 0);
        auto resp_doc = Document(cast(Buffer)rec_buf[0..rec_size]);
        auto received = hirpc.receive(resp_doc);
        if(!received.error.hasMethod(Keywords.code)){
            foreach(bill; received.params[]){
                auto std_bill = StandardBill(bill.get!Document);
                new_bills ~= std_bill;
            }
            billsfile.updateBills(new_bills);
            bills = new_bills;
            writeln("Wallet updated");
        }else{
            writeln("Wallet update failed");
        }
    }
    if (wallet_ui) {
        accountView;
    }
    else {
        if(print_amount){
            const total_input=calcTotal(bills);
            writeln(TGN(total_input));
        }
        if(create_invoice_command.length){
            auto invoice_args = create_invoice_command.split(':');
            bool invalid = false;
            if(invoice_args.length==2){

                scope(success) {
                    if (invoices.length && !invalid) {
                        auto hibon=new HiBON;
                        foreach(i, ref invoice; invoices) {
                            const index=cast(uint)i;
                            createInvoice(invoice);
                            hibon[index]=invoice.toHiBON;
                        }
                        invoicefile.fwrite(hibon);
                        accountfile.writeAccounts(accounts);
                    }
                }

                auto invoice_name = invoice_args[0];
                auto invoice_price = invoice_args[1];
                Invoice new_invoice;
                new_invoice.name=invoice_name;
                if (new_invoice.name.length==0 || invoice_price.length==0) {
                    invalid = true;
                }else{
                    new_invoice.amount=toAxion(invoice_price.to!double);
                    if (new_invoice.amount) {
                        invoices~=new_invoice;
                    }else{
                        invalid = true;
                    }
                }
            }else{
                invalid = true;
            }
            if(invalid){
                writeln("Bad command");
            }
        }else if(orders){
            SignedContract signed_contract;
            const flag=payment(orders, bills, signed_contract);
            // writefln("signed_contract.contarct.output.length=%d", signed_contract.contract.output.length);
            if ( flag ) {
                //contractfile.fwrite(signed_contract.toHiBON.serialize);
                HiRPC hirpc;
                const sender=hirpc.action("transaction", signed_contract.toHiBON);
                immutable data=sender.toDoc.serialize;
                const test=Document(data);

                const scontract=SignedContract(test["message"].get!Document["params"].get!Document);
                //writefln("%s", Document(scontract.toHiBON.serialize).toJSON.toPrettyString);
                // writefln("scontract.contarct.output.length=%d", scontract.contract.output.length);
                // writefln("scontract.contarct.output=%s", scontract.contract);
                contractfile.fwrite(sender.toDoc);
            }
        }
        if (send_flag) {
            if(contractfile.exists){
                immutable data=contractfile.fread();
                writeln(data.data[0..$]);
            auto doc1= Document(data.data);
            writeln(doc1.size);

import LEB128=tagion.utils.LEB128;
            writeln(LEB128.calc_size(doc1.serialize));
                auto client = new SSLSocket(AddressFamily.INET, EndpointType.Client);
                client.connect(new InternetAddress(addr, port));
                scope(exit) {
                    client.close;
                }
                client.blocking=true;
                // writeln(cast(string) data.data);
                client.send(data.data);

                auto rec_buf=new void[4000];
                ptrdiff_t rec_size;

                do {
                    rec_size = client.receive(rec_buf); //, current_max_size);
                    // writefln("read rec_size=%d", rec_size);
                    Thread.sleep(400.msecs);
                } while (rec_size < 0);

                HiRPC hirpc;
                auto resp_doc = Document(cast(Buffer)rec_buf[0..rec_size]);
                auto received = hirpc.receive(resp_doc);
                if(received.params.hasElement(Keywords.code) && received.error[Keywords.code].get!int != 0){
                    writeln(received.error[Keywords.message].get!string);
                }else{
                    accountfile.writeAccounts(accounts);
                    writeln("Successfuly sended");
                }

                Thread.sleep(200.msecs);
            }
        }
    }
    return 0;
}
