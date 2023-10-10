/// Global logger module 
module tagion.logger.Logger;

import core.sys.posix.pthread;
import std.string;
import std.format;

import tagion.utils.pretend_safe_concurrency;
import tagion.basic.Types : Control;
import tagion.hibon.HiBONRecord;
import tagion.hibon.HiBONJSON;
import tagion.hibon.Document : Document;
import tagion.logger.LogRecords;
import tagion.basic.Version : ver;

/// Is a but mask for the logger
enum LogLevel {
    NONE = 0, /// No log is e
    INFO = 1, /// Enable info logs
    TRACE = INFO << 1, /// Enable trace logs
    WARN = TRACE << 1, /// Enable warning
    ERROR = WARN << 1, /// Enable errors
    FATAL = ERROR << 1, /// Enable fatal
    ALL = INFO | TRACE | WARN | ERROR | FATAL, /// Enable all types
    STDERR = WARN | ERROR | FATAL
}

private static Tid logger_tid; /// In multi-threading mode this Tid is used

/// Logger used one for each thread
@safe
static struct Logger {

    import std.format;

    protected {
        string _task_name; /// Logger task name
        uint[] masks; /// Logger mask stack
        __gshared string logger_task_name; /// Logger task name
        __gshared Tid logger_subscription_tid;

    }

    @property
    string task_name() @nogc @safe nothrow const {
        return _task_name;
    }

    @property
    bool task_name(const string name) @safe nothrow {
        try {
            const registered = locate(name);
            const i_am_the_registered = (() @trusted => registered == thisTid)();
            if (registered is Tid.init) {
                
                    .register(name, thisTid);
                _task_name = name;
                setThreadName(name);
                return true;
            }
            else if (i_am_the_registered) {
                _task_name = name;
                return true;
            }
            else {
                return false;
            }
        }
        catch (Exception e) {
            return false;
        }
    }

    shared bool silent; /// If true the log is silened (no logs is process from any tasks)

    /**
    Register the task logger name.
    Should be done when the task starts
    */
    pragma(msg, "TODO: Remove log register when prior services are removed");
    @trusted
    void register(string task_name) nothrow
    in (logger_tid is logger_tid.init)
    do {
        push(LogLevel.ALL);
        scope (exit) {
            pop;
        }
        try {
            logger_tid = locate(logger_task_name);

            const registered = this.task_name = task_name;

            if (!registered) {
                log.error("%s logger not register", _task_name);
            }

            import std.stdio : stderr;

            static if (ver.not_unittest) {
                stderr.writefln("Register: %s logger\n", _task_name);
                log("Register: %s logger", _task_name);
            }
        }
        catch (Exception e) {
            log.error("%s logger not register", _task_name);
        }
    }

    /**
    Sets the task name of the logger for the whole program
    Note should be set in the logger task when the logger task 
is ready and has been started correctly
*/
    @trusted @nogc
    void set_logger_task(string logger_task_name) nothrow
    in {
        assert(this.logger_task_name.length == 0);
    }
    do {
        this.logger_task_name = logger_task_name;
    }

    /**
        Returns: true if the task_name has been register by the logger
    */
    @property @trusted
    bool isLoggerServiceRegistered() const nothrow {
        import std.exception : assumeWontThrow;

        return assumeWontThrow(logger_tid != logger_tid.init);
    }

    @trusted
    void registerSubscriptionTask(string task_name) {
        logger_subscription_tid = locate(task_name);
    }

    @trusted
    bool isLoggerSubRegistered() nothrow {
        return logger_subscription_tid !is Tid.init;
    }

    /**
        Push the current logger mask to the mask stack
    */
    void push(const uint mask) nothrow {
        masks ~= mask;
    }

    /**
        Pops the current logger mask
        Returns: the current mask
    */
    @nogc
    uint pop() nothrow {
        uint result = masks[$ - 1];
        if (masks.length > 1) {
            masks = masks[0 .. $ - 1];
        }
        return result;
    }

    /**
    Reports the text to the logger with the level LogLevel
    */
    @trusted
    void report(const LogLevel level, lazy scope string text) const nothrow {
        version (unittest)
            return;
        if ((masks.length > 0) && (level & masks[$ - 1]) && !silent) {
            import std.exception : assumeWontThrow;
            import std.conv : to;

            if (!isLoggerServiceRegistered) {
                import core.stdc.stdio;

                scope const _level = assumeWontThrow(level.to!string);
                scope const _text = assumeWontThrow(toStringz(text));
                if (_task_name.length > 0) {
                    // printf("ERROR: Logger not register for '%.*s'\n", cast(int) _task_name.length, _task_name
                    //         .ptr);
                }
                printf("%.*s:%.*s: %s\n",
                        cast(int) _task_name.length, _task_name.ptr,
                        cast(int) _level.length, _level.ptr,
                        _text);
            }
            else {
                try {
                    immutable info = LogInfo(_task_name, level);
                    immutable doc = TextLog(text).toDoc;
                    logger_tid.send(info, doc);
                }
                catch (Exception e) {
                    import std.stdio;

                    assumeWontThrow({ stderr.writefln("\t%s:%s: %s", task_name, level, text); stderr.writefln("%s", e); }());
                }
            }
        }
    }

    /// This function should be rewritte it' for the event logging
    deprecated("use Topic based subscription")
    @trusted
    void report(T)(string symbol_name, T h) const nothrow if (isHiBONRecord!T) {
        version (unittest)
            return;
        import std.exception : assumeWontThrow;

        if (isLoggerServiceRegistered) {
            try {
                immutable info = LogInfo(_task_name, symbol_name);
                immutable doc = h.toDoc;
                logger_tid.send(info, doc);
            }
            catch (Exception e) {
                import std.stdio;

                assumeWontThrow({ stderr.writefln("%s", e.msg); stderr.writefln("\t%s:%s env", task_name, symbol_name); }());

            }
        }
    }

    /// Conditional subscription logging
    @trusted
    void report(Topic topic, lazy string identifier, lazy const(Document) data) const nothrow {
        report(LogLevel.INFO, "%s|%s| %s", topic.name, identifier, data.toPretty);
        if (topic.subscribed && log.isLoggerSubRegistered) {
            try {
                logger_subscription_tid.send(topic, identifier, data);
            }
            catch (Exception e) {
                import std.stdio;
                import std.exception : assumeWontThrow;

                assumeWontThrow({
                    stderr.writefln("%s", e.msg);
                    stderr.writefln("\t%s:%s = %s", identifier, data.toPretty);
                }());
            }
        }
    }

    void opCall(Topic topic, lazy string identifier, lazy const(Document) data) const nothrow {
        report(topic, identifier, data);
    }

    void opCall(T)(Topic topic, lazy string identifier, lazy T data) const nothrow if (isHiBONRecord!T) {
        report(topic, identifier, data.toDoc);
    }

    void opCall(Topic topic, lazy string identifier) const nothrow {
        report(topic, identifier, Document.init);
    }

    import std.traits : isBasicType;

    void opCall(T)(Topic topic, lazy string identifier, lazy T data) const nothrow if (isBasicType!T && !is(T : void)) {
        import tagion.hibon.HiBON;

        if (topic.subscribed && log.isLoggerSubRegistered) {
            try {
                auto hibon = new HiBON;
                hibon["data"] = data;
                report(topic, identifier, Document(hibon));
            }
            catch (Exception e) {
            }
        }
    }

    /**
    formatted logger 
    */
    @trusted
    void report(Args...)(LogLevel level, string fmt, lazy Args args) const nothrow {
        report(level, format(fmt, args));
    }

    /**
    logs the text to in INFO level
*/
    void opCall(lazy string text) const nothrow {
        report(LogLevel.INFO, text);
    }

    /**
logs the fmt text in INFO level
*/
    void opCall(Args...)(string fmt, lazy Args args) const nothrow {
        report(LogLevel.INFO, fmt, args);
    }

    /// Should be rewritten to support subscription
    bool env(T)(
            string symbol_name,
            T h,
            string file = __FILE__,
            size_t line = __LINE__) nothrow if (isHiBONRecord!T) {
        static bool registered;
        if (!registered) {
            // Register the task name and the symbol_name
        }
        report(symbol_name, h);

        return registered;
    }

    @trusted
    void opCall(lazy const(Throwable) t) const nothrow {
        import std.exception;

        auto mt = assumeWontThrow(cast(Throwable) t);

        fatal(assumeWontThrow(mt.toString));
        fatal(mt.info.toString);
    }

    void trace(lazy string text) const nothrow {
        report(LogLevel.TRACE, text);
    }

    void trace(Args...)(string fmt, lazy Args args) const nothrow {
        report(LogLevel.TRACE, fmt, args);
    }

    void warning(lazy string text) const nothrow {
        report(LogLevel.WARN, text);
    }

    void warning(Args...)(string fmt, Args args) const nothrow {
        report(LogLevel.WARN, fmt, args);
    }

    void error(lazy string text) const nothrow {
        report(LogLevel.ERROR, text);
    }

    void error(Args...)(string fmt, lazy Args args) const nothrow {
        report(LogLevel.ERROR, fmt, args);
    }

    void fatal(lazy string text) const nothrow {
        report(LogLevel.FATAL, text);
    }

    void fatal(Args...)(string fmt, lazy Args args) const nothrow {
        report(LogLevel.FATAL, fmt, args);
    }

    @trusted
    void close() const nothrow {
        if (isLoggerServiceRegistered) {
            import std.exception : assumeWontThrow;

            assumeWontThrow(logger_tid.send(Control.STOP));
        }
    }
}

mixin template Log(alias name) {
    mixin(format(q{const bool %1$s_logger = log.env("%1$s", %1$s);}, __traits(identifier, name)));
}

template Log_(alias name) {
    void Log_(Topic topic) {
        log.report(topic, __traits(identifier, name), name);
    }
}

static Logger log;

unittest {
    import tagion.hibon.HiBONRecord;

    static struct S {
        int x;
        mixin HiBONRecord!(
                q{this(int x) {this.x = x;}}
        );
    }

    const s = S(10);
    mixin Log!s;

}

import std.typecons;

@safe
struct Topic {
    string name;
    private const(Subscribed)* _subscribed;

    @property
    bool subscribed() nothrow {
        if (_subscribed is null) {
            return false;
        }
        return (*_subscribed is Subscribed.yes);
    }

}

alias Subscribed = shared(Flag!"subscribed");
shared struct SubscriptionMask {
    //      yes|no     topic
    private Subscribed[string] _registered_topics;

    @safe
    Topic register(string topic) {
        Subscribed* s = topic in _registered_topics;
        if (s is null) {
            _registered_topics[topic] = Subscribed.no;
            s = topic in _registered_topics;
        }
        return Topic(topic, s);
    }

    @trusted
    void subscribe(string topic) {
        if (thisTid == log.logger_subscription_tid) {
            _registered_topics[topic] = Subscribed.yes;
            return;
        }
        assert(0, "Only the logger subscription task can control the subscription");
    }

    @trusted
    void unsubscribe(string topic) {
        if (thisTid == log.logger_subscription_tid) {
            _registered_topics[topic] = Subscribed.no;
            return;
        }
        assert(0, "Only the logger subscription task can control the subscription");
    }
}

static shared SubscriptionMask submask;

unittest {
    import core.time;

    Topic topic = submask.register("some_tag");
    assert(!topic.subscribed, "Topic was subscribed, it shouldn't");
    register("log_sub_task", thisTid);
    log.registerSubscriptionTask("log_sub_task");
    auto some_symbol = Document.init;
    Log_!(some_symbol)(topic);
    assert(false == receiveTimeout(Duration.zero, (Topic _, string __, const(Document)) {}), "Received an unsubscribed topic");
    // receiveTimeout(Duration.zero, (Topic _, string __, typeof(some_symbol)) {});
    submask.subscribe(topic.name);
    assert(topic.subscribed, "Topic wasn't subscribed, it should");
    Log_!(some_symbol)(topic);
    assert(true == receiveTimeout(Duration.zero, (Topic _, string __, const(Document)) {}), "Didn't receive subscribed topic");
}

version (Posix) {
    import std.string : toStringz;
    import core.sys.posix.pthread;

    extern (C) int pthread_setname_np(pthread_t, const char*) nothrow;

    /**
    Set the thread name to the same as the task name
    Note. Makes it easier to debug because pthread name is the same as th task name
    */
    @trusted
    void setThreadName(string name) nothrow {
        pthread_setname_np(pthread_self(), toStringz(name));
    }
}
else {
    @trusted
    void setThreadName(string _) nothrow {
    }
}
