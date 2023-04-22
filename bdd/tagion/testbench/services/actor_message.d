module tagion.testbench.services.actor_message;

import tagion.actor.actor;
import core.time;
import std.stdio;
import std.format : format;
import std.meta;
import std.variant : Variant;
import std.concurrency;

// Default import list for bdd
import tagion.behaviour;
import tagion.hibon.Document;
import std.typecons : Tuple;
import tagion.testbench.tools.Environment;
import tagion.basic.basic : TrustedConcurrency;

import core.thread;

enum feature = Feature(
            "Actor messaging",
            ["This feature should verify the message send between actors"]);

alias FeatureContext = Tuple!(
        MessageBetweenSupervisorAndChild, "MessageBetweenSupervisorAndChild", SendMessageBetweenTwoChildren, "SendMessageBetweenTwoChildren",
        FeatureGroup*, "result"
);

enum supervisor_task_name = "supervisor";
enum child1_task_name = "0";
enum child2_task_name = "1";

// Child actor
struct MyActor {
static:
    int counter = 0;
    void increase(Msg!"increase") {
        counter++;
        sendOwner(Msg!"response"(), counter);
    }

    void decrease(Msg!"decrease") {
        counter--;
        sendOwner(Msg!"response"(), counter);
    }

    void relay(Msg!"relay", string message) {
        sendOwner(Msg!"relay"(), message);
    }

    mixin Actor!(&increase, &decrease, &relay); /// Turns the struct into an Actor
}

alias ChildHandle = ActorHandle!MyActor;

struct MySuperActor {
static:
    MyActor child1;
    MyActor child2;
    alias children = AliasSeq!(child1, child2);

    void receiveStatus(Msg!"response", int status) {
        sendOwner(status);
    }

    void roundtrip(Msg!"roundtrip", string message) {
        ChildHandle child = actorHandle!MyActor(child1_task_name);
        child.send(Msg!"relay"(), message);
    }

    void relay(Msg!"relay", string message) {
        sendOwner(message);
    }

    mixin Actor!(&receiveStatus, &roundtrip, &relay); /// Turns the struct into an Actor
}

alias SupervisorHandle = ActorHandle!MySuperActor;

@safe @Scenario("Message between supervisor and child",
        [])
class MessageBetweenSupervisorAndChild {
    SupervisorHandle supervisorHandle;
    ChildHandle childHandleUno;
    ChildHandle childHandleDos;

    @Given("a supervisor #super and two child actors #child1 and #child2")
    Document actorsChild1AndChild2() @trusted {
        supervisorHandle = spawnActor!MySuperActor(supervisor_task_name);

        Ctrl ctrl = receiveOnlyTimeout!CtrlMsg.ctrl;
        check(ctrl is Ctrl.STARTING, "Supervisor is not starting");

        ctrl = receiveOnlyTimeout!CtrlMsg.ctrl;
        check(ctrl is Ctrl.ALIVE, "Supervisor is not alive");

        return result_ok;
    }

    @When("the #super has started the #child1 and #child2")
    Document theChild1AndChild2() @trusted {
        // The supervisor should only send alive when it has receive alive from the children.
        // we assign the child handles
        childHandleUno = actorHandle!MyActor(child1_task_name);
        childHandleDos = actorHandle!MyActor(child2_task_name);

        return result_ok;
    }

    @Then("send a message to #child1")
    Document aMessageToChild1() @trusted {
        childHandleUno.send(Msg!"increase"());

        return result_ok;
    }

    @Then("send this message back from #child1 to #super")
    Document fromChild1ToSuper() @trusted {
        check(receiveOnlyTimeout!int == 1, "Child 1 did not send back the expected value of 1");

        return result_ok;
    }

    @Then("send a message to #child2")
    Document aMessageToChild2() @trusted {
        childHandleDos.send(Msg!"decrease"());
        return result_ok;
    }

    @Then("send thus message back from #child2 to #super")
    Document fromChild2ToSuper() @trusted {
        check(receiveOnlyTimeout!int == -1, "Child 2 did not send back the expected value of 1");
        return result_ok;
    }

    @Then("stop the #super")
    Document stopTheSuper() @trusted {
        supervisorHandle.send(Sig.STOP);
        Ctrl ctrl = receiveOnlyTimeout!CtrlMsg.ctrl;
        check(ctrl is Ctrl.END, "The supervisor did not stop");

        return result_ok;
    }

}

@safe @Scenario("send message between two children",
        [])
class SendMessageBetweenTwoChildren {
    SupervisorHandle supervisorHandle;
    ChildHandle childHandleUno;
    ChildHandle childHandleDos;

    @Given("a supervisor #super and two child actors #child1 and #child2")
    Document actorsChild1AndChild2() @trusted {
        supervisorHandle = spawnActor!MySuperActor(supervisor_task_name);

        CtrlMsg ctrl = receiveOnlyTimeout!CtrlMsg;
        check(ctrl.ctrl is Ctrl.STARTING, "Supervisor is not starting");

        ctrl = receiveOnlyTimeout!CtrlMsg;
        check(ctrl.ctrl is Ctrl.ALIVE, "Supervisor is not alive");

        return result_ok;
    }

    @When("the #super has started the #child1 and #child2")
    Document theChild1AndChild2() @trusted {
        // The supervisor should only send alive when it has receive alive from the children.
        // we assign the child handles
        childHandleUno = actorHandle!MyActor(child1_task_name);
        childHandleDos = actorHandle!MyActor(child2_task_name);

        return result_ok;
    }

    @When("send a message from #super to #child1 and from #child1 to #child2 and back to the #super")
    Document backToTheSuper() @trusted {

        enum message = "Hello Tagion";
        supervisorHandle.send(Msg!"roundtrip"(), message);
        check(receiveOnlyTimeout!string == message, "Did not get the same message back");

        return result_ok;
    }

    @Then("stop the #super")
    Document stopTheSuper() @trusted {
        supervisorHandle.send(Sig.STOP);
        CtrlMsg ctrl = receiveOnlyTimeout!CtrlMsg;
        check(ctrl.ctrl is Ctrl.END, "The supervisor did not stop");

        return result_ok;
    }

}
