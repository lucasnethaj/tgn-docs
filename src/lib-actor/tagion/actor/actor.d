/// Main implementation of actor framework
module tagion.actor.actor;

import std.stdio;
import std.format : format;
import std.typecons;
import core.thread;
import std.exception;
import std.traits;

import tagion.utils.pretend_safe_concurrency;
import tagion.actor.exceptions;
import tagion.actor.exceptions : TaskFailure;
import tagion.basic.tagionexceptions : TagionException;

version(Posix) {
    import core.sys.posix.pthread;
    extern (C) int pthread_setname_np(pthread_t, const char*) nothrow;
}

/**
 * Message "Atom" type
 * Examples:
 * ---
 * // As a type
 * Msg!"hi";
 * // As a value
 * Msg!"hi"();
 * ---
 */
struct Msg(string name) {
}

// State messages send to the supervisor
enum Ctrl {
    STARTING, // The actors is lively
    ALIVE, /// Send to the ownerTid when the task has been started
    END, /// Send for the child to the ownerTid when the task ends
}

// Signals send from the supervisor to the direct children
enum Sig {
    STOP,
}

/// Control message sent to a supervisor
/// contains the Tid of the actor which send it and the state
alias CtrlMsg = Tuple!(string, "task_name", Ctrl, "ctrl");

bool all(Ctrl[string] aa, Ctrl ctrl) @safe {
    foreach (val; aa) {
        if (val != ctrl) {
            return false;
        }
    }
    return true;
}

import std.traits;
template isActor(A) {

    template isTask(args...)
    if (args.length == 1 && isCallable!(args[0])) {
        alias task = args[0];
        alias params = Parameters!(task);
        enum bool isTask = is(params[0] : string)
                        && ParameterIdentifierTuple!(task)[0] == "task_name"
                        && hasFunctionAttributes!(task, "nothrow");
    }

    enum bool isActor = hasMember!(A, "task") 
                     && isTask!(A.task);
}

/**
 * A "reference" to an actor that may or may not be spawned, we will never know
 * Params:
 *  A = an actor type
 */
struct ActorHandle(A) {
    import concurrency = tagion.utils.pretend_safe_concurrency;

    /// the tid of the spawned task
    Tid tid;
    /// the name of the possibly running task
    string task_name;

    alias Actor = A;

    @safe void send(T...)(T args) {
        locate(task_name).send(args);
        // concurrency.send(tid, args);
    }

    // pragma(msg, format("# %s:", Actor.stringof));
    version(none) static foreach(member; __traits(allMembers, Actor)) {
        // alias getMem = __traits(getMember, Actor, member);
        
        // enum params = Parameters!(member);
        // pragma(msg, format("\t%s:%s", member, __traits(getMember, Actor, member)));
        static if(
                isCallable!(__traits(getMember, Actor, member)) 
                && Parameters!(__traits(getMember, Actor, member))
            ) {
            // pragma(msg, member);
        }
    }

    /// use
    // void opDispatch(string method, Args...)(Args args) {
    //     send(actor.Msg!method, args);
    // }

}

/**
 * Create an actorHandle
 * Params:
 *   A = The type of actor you want to create a handle for
 *   task_name = the task name to search for
 * Returns: Actorhandle with type A
 * Examples:
 * ---
 * actorHandle!MyActor("my_task_name");
 * ---
 */
ActorHandle!A handle(A)(string task_name) @safe
if (isActor!A) {
    Tid tid = locate(task_name);
    return ActorHandle!A(tid, task_name);
}

/**
 * Params:
 *   A = The type of actor you want to create a handle for
 *   task_name = the name it should be started as
 *   args = list of arguments to pass to the task function
 * Returns: An actorHandle with type A
 * Examples:
 * ---
 * spawn!MyActor("my_task_name", 42);
 * ---
 */
ActorHandle!A spawn(A, Args...)(string task_name, Args args) @safe nothrow
if (isActor!A) {
    try {
        immutable A actor = A();
        Tid tid;

        import concurrency = tagion.utils.pretend_safe_concurrency;
        // import concurrency = std.concurrency;
        tid = concurrency.spawn(&(actor.task), task_name, args);
        writefln("spawning %s", task_name);
        tid.setMaxMailboxSize(int.sizeof, OnCrowding.throwException);
        register(task_name, tid);
        writefln("%s registered", task_name);

        return ActorHandle!A(tid, task_name);
    }
    catch (Exception e) {
        assert(0, e.msg);
    }
}

/*
 *
 * Params:
 *   a = an active actorhandle
 */
A respawn(A)(A actor_handle) @safe
if(isActor!(A.Actor)) {
    writefln("%s", typeid(actor_handle.Actor));
    actor_handle.send(Sig.STOP);
    unregister(actor_handle.task_name);

    return spawn!(A.Actor)(actor_handle.task_name);
}

/// Nullable and nothrow wrapper around ownerTid
Nullable!Tid tidOwner() @safe nothrow {
    // tid is "null"
    Nullable!Tid tid;
    try {
        // Tid is assigned
        tid = ownerTid;
    }
    catch (TidMissingException) {
        // Tid is "just null"
    }
    catch (Exception e) {
        // logger.fatal(e);
    }
    return tid;
}

/// Send to the owner if there is one
void sendOwner(T...)(T vals) @safe {
    if (!tidOwner.isNull) {
        send(tidOwner.get, vals);
    }
    else {
        write("No owner, writing message to stdout instead: ");
        writeln(vals);
    }
}

void fail(string task_name, Throwable t) @trusted nothrow {
    if (tidOwner.get !is Tid.init) {
        assumeWontThrow(
            ownerTid.prioritySend(
                TaskFailure(task_name, cast(immutable) t)
            )
        );
    }
}

/// send your state to your owner
void setState(Ctrl ctrl, string task_name) @safe nothrow {
    try {
        if (!tidOwner.isNull) {
            tidOwner.get.prioritySend(CtrlMsg(task_name, ctrl));
        }
        else {
            /* write("No owner, writing message to stdout instead: "); */
            /* writeln(ctrl); */
        }
    }
    catch (PriorityMessageException e) {
        /* logger.fatal(e); */
    }
    catch (Exception e) {
        /* logger.fatal(e); */
    }
}

/**
 * Base template
 * All members should be static
 *
 * Params:
 *  T... = a list of message handlers passed to the receive function
 * 
 * Implemnt:
 *  Struct may implement starting callback that gets called after the actor sends Ctrl.STARTING
 *  ---
 *  void starting() {...}
 *  ---
 * 
 *  fail a callable to override the default failhandler
 *  ---
 *  auto fail = (TaskFailure tf) {,,,};
 *  ---
 */
mixin template Actor(T...) {
static:
    import std.exception : assumeWontThrow;
    import std.variant : Variant;
    import tagion.utils.pretend_safe_concurrency : OwnerTerminated, Tid, thisTid, ownerTid, receive, prioritySend, ThreadInfo, send, locate;
    import std.format : format;
    import std.traits : isCallable;
    import tagion.actor.exceptions : TaskFailure, taskException, ActorException, UnknownMessage;
    import std.stdio : writefln, writeln;

    bool stop = false;
    Ctrl[string] childrenState; // An AA to keep a copy of the state of the children

    alias This = typeof(this);

    void signal(Sig signal) @safe {
        with (Sig) final switch (signal) {
        case STOP:
            stop = true;
            break;
        }
    }

    /// Controls message sent from the children.
    void control(CtrlMsg msg) @safe {
        childrenState[msg.task_name] = msg.ctrl;
    }

    /// Stops the actor if the supervisor stops
    void ownerTerminated(OwnerTerminated) @safe {
        writefln("%s, Owner stopped... nothing to life for... stopping self", thisTid);
        stop = true;
    }

    /**
     * The default message handler, if it's an unknown messages it will send a FAIL to the owner.
     * Params:
     *   message = literally any message
     */
    void unknown(Variant message) @trusted  {
        throw new UnknownMessage("No delegate to deal with message: %s".format(message));
    }

    /// The tasks that get run when you call spawn!
    void task(string task_name) nothrow {
        try {

            // Set the system thread name on posix for better debugging abiiities
            version(Posix) {
                import std.string;
                import core.sys.posix.pthread;
                pthread_setname_np(pthread_self(), toStringz(task_name));
            }
            setState(Ctrl.STARTING, task_name); // Tell the owner that you are starting.
            scope (exit) {
                if (childrenState.length != 0) {
                    foreach (child_task_name, ctrl; childrenState) {
                        if (ctrl is Ctrl.ALIVE) {
                            locate(child_task_name).send(Sig.STOP);
                        }
                    }

                    while (!(childrenState.all(Ctrl.END))) {
                        receive(
                                (CtrlMsg ctrl) { childrenState[ctrl.task_name] = ctrl.ctrl; },
                                (TaskFailure tf) {
                            writefln("While stopping `%s` received taskfailure: %s", task_name, tf.throwable.msg);
                        }
                        );
                    }
                }

                end(task_name);
            }

            // Call starting() if it's implemented
            static if (__traits(hasMember, This, "starting")) {
                alias startingCall = __traits(getMember, This, "starting");
                static assert(isCallable!startingCall, "the starting callback is not callable");
                startingCall();
            }

            // // Asign the failhandler if a custom one is defined override the default one
            static if (__traits(hasMember, This, "failHandler")) {
                auto failhandler = __traits(getMember, This, "failHandler");
            }
            else {
                // default failhandler
                auto failhandler = (TaskFailure tf) {
                    if (ownerTid != Tid.init) {
                        ownerTid.prioritySend(tf);
                    }
                };
            }

            setState(Ctrl.ALIVE, task_name); // Tell the owner that you running
            while (!stop) {
                try {
                    receive(
                            T, // The message handlers you pass to your Actor template
                            failhandler,
                            &signal,
                            &control,
                            &ownerTerminated,
                            &unknown,
                    );
                }
                catch (Throwable t) {
                    fail(task_name, t);
                }
            }
        }

        // If we catch an exception we send it back to owner for them to deal with it.
        catch (Throwable t) {
            fail(task_name, t);
        }
    }
}

import std.exception : assumeWontThrow;
import std.variant : Variant;
import tagion.utils.pretend_safe_concurrency : OwnerTerminated, Tid, thisTid, ownerTid, receive, prioritySend, ThreadInfo, send, locate;
import std.format : format;
import std.traits : isCallable;
import std.stdio : writefln, writeln;

void end(string task_name) nothrow {
    assumeWontThrow(ThreadInfo.thisInfo.cleanup);
    assumeWontThrow(setState(Ctrl.END, task_name));
}


void run(Args...)(string task_name, Args args) nothrow {
    bool stop = false;
    Ctrl[string] childrenState; // An AA to keep a copy of the state of the children

    void signal(Sig signal) {
        with (Sig) final switch (signal) {
        case STOP:
            stop = true;
            break;
        }
    }

    /// Controls message sent from the children.
    void control(CtrlMsg msg) {
        childrenState[msg.task_name] = msg.ctrl;
    }

    /// Stops the actor if the supervisor stops
    void ownerTerminated(OwnerTerminated) {
        writefln("%s, Owner stopped... nothing to life for... stopping self", thisTid);
        stop = true;
    }

    /**
     * The default message handler, if it's an unknown messages it will send a FAIL to the owner.
     * Params:
     *   message = literally any message
     */
    void unknown(Variant message) {
        throw new UnknownMessage("No delegate to deal with message: %s".format(message));
    }

    try {
        setState(Ctrl.STARTING, task_name); // Tell the owner that you are starting.
        scope (exit) {
            if (childrenState.length != 0) {
                foreach (child_task_name, ctrl; childrenState) {
                    if (ctrl is Ctrl.ALIVE) {
                        locate(child_task_name).send(Sig.STOP);
                    }
                }

                while (!(childrenState.all(Ctrl.END))) {
                    receive(
                            (CtrlMsg ctrl) { childrenState[ctrl.task_name] = ctrl.ctrl; },
                            (TaskFailure tf) {
                        writefln("While stopping `%s` received taskfailure: %s", task_name, tf.throwable.msg);
                    }
                    );
                }
            }
        }

        auto failhandler = (TaskFailure tf) {
            if (ownerTid != Tid.init) {
                ownerTid.prioritySend(tf);
            }
        };


        setState(Ctrl.ALIVE, task_name); // Tell the owner that you running
        while (!stop) {
            try {
                receive(
                        args, // The message handlers you pass to your Actor template
                        failhandler,
                        &signal,
                        &control,
                        &ownerTerminated,
                        &unknown,
                );
            }
            catch (Throwable t) {
                if (ownerTid != Tid.init) {
                    ownerTid.prioritySend(TaskFailure(task_name, cast(immutable) t));
                }
            }
        }
    }

    // If we catch an exception we send it back to owner for them to deal with it.
    catch (Throwable t) {
        if (tidOwner.get !is Tid.init) {
            assumeWontThrow(ownerTid.prioritySend(TaskFailure(task_name, cast(immutable) t)));
        }
    }
}
