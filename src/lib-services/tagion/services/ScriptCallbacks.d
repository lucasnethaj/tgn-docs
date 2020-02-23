module tagion.services.ScriptCallbacks;

import std.concurrency;
import std.datetime;   // Date, DateTime
import std.exception : assumeUnique;

import tagion.hashgraph.Event : Event, EventScriptCallbacks, EventBody;
import tagion.Base : Buffer, Payload, Control;
import tagion.hibon.HiBON;
import tagion.hibon.Document;
import tagion.Keywords;

import tagion.services.LoggerService;

@safe class ScriptCallbacks : EventScriptCallbacks {
    private Tid _event_script_tid;
    @trusted
    this(ref Tid event_script_tid) {
        _event_script_tid=event_script_tid;
    }

    void epoch(const(Event[]) received_event, immutable long epoch_time) {
        log("Epoch with %d events", received_event.length);
        // auto hibon=new HiBON;
        // hibon[Keywords.time]=time;
        Payload[] payloads;

        foreach(i, e; received_event) {
            if (e.eventbody.payload.length) {
                log("\tepoch=%d %d", i, e.eventbody.payload.length);
            }
            if ( e.eventbody.payload ) {
                payloads~=Payload(e.eventbody.payload);
            }
        }
        if ( payloads ) {
            // hibon[Keywords.epoch]=payloads;
            // immutable data=hibon.serialize;
            log("SEND Epoch with %d transactions", payloads.length);
            send(payloads, epoch_time);
        }
    }

   @trusted
   void send(ref Payload[] payloads, immutable long epoch_time) {
       immutable unique_payloads=assumeUnique(payloads);
       log("send data=%d", unique_payloads.length);
       _event_script_tid.send(unique_payloads);
   }

    @trusted
    void send(immutable(EventBody) ebody) {
        log("ebody.payload=%d", ebody.payload.length);
        if (ebody.payload.length) {
            _event_script_tid.send(ebody);
        }
    }

    @trusted
    bool stop() {
        immutable result= _event_script_tid != _event_script_tid.init;
        if ( result ) {
            _event_script_tid.prioritySend(Control.STOP);
        }
        return result;
    }

}
