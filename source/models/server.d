module models.server;
import models;

import core.thread;
import std.file;
import std.array;
import std.string;
import std.process;
import std.algorithm;
import std.container;

import vibe.d;
import vibe.stream.stdio;
import jsonizer : fromJSON;

import store;
import util.io;
import util.json;
import util.random;
import config.application;

class Server {
    static const POLL_INTERVAL = 15.dur!("seconds");
    static const LOG_LENGTH = 30;

    package static shared Store!(Server, "name") store; // Initialized in package.d

    static Server get(string name) {
        return store.get(name);
    }

    static @property auto all() {
        return store.all;
    }

    static @property auto available() {
        return all.filter!(s => s.booking is null && s.bookable);
    }

    private static auto readServerConfig() {
        auto json = readJSON(buildConfigPath("servers.json"));

        // Merge in default options
        auto defaultOptions = json["default-options"];
        foreach (server; json["servers"].array) {
            util.json.merge(server["options"], defaultOptions);
        }

        return json["servers"].fromJSON!(Server[]);
    }

    static void reload() {
        auto serverList = readServerConfig();

        // Get a map from the list of servers
        Server[string] servers;
        foreach (server; serverList) {
            servers[server.name] = server;

            // Don't override existing servers, reload them with new settings instead
            logInfo("%s %s", server.name, store.all);
            auto old = store.get(server.name);
            if (old is null) {
                server.create();
            } else {
                old.reload(server);
            }
        }

        // Mark servers not found in the new config for deletion
        foreach (server; store.all) {
            if (server.name !in servers) {
                if (!server.running || server.bookable && server.booking is null) {
                    server.remove();
                } else {
                    server.willDelete = true;
                }
            }
        }
    }

    mixin JsonizeMe;
    @jsonize(Jsonize.opt) {
        string name;
        string executable;
        string[string] options;

        @jsonize("auto-start") bool autoStart = true;
        bool bookable = true;
        @jsonize("reset-command") string resetCommand = "";
        @jsonize("log-path") string logPath = null;
    }

    bool dirty = true;
    bool willDelete = false;
    DList!string logs;
    ServerStatus status;

    private {
        ProcessPipes processPipes;
        Task processWatcher;
        Task processPoller;
        bool statusSent = false;
    }

    @property auto booking() {
        return Booking.bookingFor(cast(Server)this);
    }

    this() {
    }

    /**
     * Initialize the server, called when a server is ready to be added to the store
     */
    private void create() {
        store.add(this);

        if (autoStart) spawn();
    }

    /**
     * Generate a strong set of passwords.
     */
    void generatePasswords() {
        enforce(running);
        // Update status immediately for getting connect strings
        status.password = randomBase64(12);
        status.rconPassword = randomBase64(12);

        sendCMD(`sv_password "%s"`.format(status.password));
        sendCMD(`rcon_password "%s"`.format(status.rconPassword));
    }

    /**
     * Reload the server configuration (using another server instance)
     * Use to update settings on a running server by setting the dirty flag and waiting for a time to restart
     */
    void reload(Server config) {
        synchronized (this) {
            if (executable != config.executable || options != config.options) {
                dirty = true;
            }

            executable = config.executable;
            options = config.options;
            autoStart = config.autoStart;
            bookable = config.bookable;
            resetCommand = config.resetCommand;
            logPath = config.logPath;
        }
    }

    /**
     * Reset the server by running the reset command and restarting if dirty.
     * Will also kick all players for the given reason.
     */
    void reset(string reason = "Server Reset") {
        enforce(running);
        sendCMD(`kickall "%s"`.format(reason));

        if (dirty) {
            restart();
        } else {
            if (resetCommand !is null) sendCMD(resetCommand);
            generatePasswords();
        }
    }

    /**
     * Restart the server, killing and respawning
     */
    void restart() {
        synchronized (this) {
            auto booking = this.booking;
            if (booking !is null) booking.end;

            if (running) kill();
            spawn();
        }
    }

    /**
     * Start the server, spawning a server process and a watcher for it.
     * Also resets the server.
     */
    void spawn() {
        synchronized (this) {
            enforce(!running);

            auto options = this.options.byKeyValue.map!((o) => "%s %s".format(o.key, o.value)).array;
            // Always enable the console
            options ~= "-console";

            auto serverCommand = "%s %s".format(executable, options.join(" "));
            // script captures /dev/tty in stdout
            auto command = "unbuffer -p %s".format(serverCommand);

            log("Started with: %s".format(command));
            logInfo("Spawning %s with: %s", name, command);

            auto redirects = Redirect.stdin | Redirect.stdout | Redirect.stderrToStdout;
            processPipes = pipeShell(command, redirects);

            // Set the process's stdout as non-blocking
            processPipes.stdout.markNonBlocking();

            runWorkerTaskH!(Server.watcher)(cast(shared)this);
            runWorkerTaskH!(Server.poller)(cast(shared)this);

            dirty = false;
            reset();
            statusSent = false;
            status.sendPoll(this);
        }
    }

    /**
     * Check whether the server process is running
     */
    @property bool running() @safe {
        synchronized (this) {
            if (processPipes.pid is null) return false;

            auto status = processPipes.pid.tryWait();
            return !status.terminated;
        }
    }

    /// Same as running but shared. D has its quirks
    private @property bool sharedRunning() shared {
        return (cast(Server)this).running;
    }

    /**
     * Kill the running server
     */
    void kill() {
        synchronized (this) {
            enforce(running);

            logInfo("Killing %s".format(name));
            processPipes.stdin.close();
            processPipes.stdout.close();
            processPipes.pid.kill();
            processPipes.pid.wait();
            enforce(!running);

            // Reset status
            status = ServerStatus();
        }
    }

    /**
     * Remove the server, killing if necessary
     */
    void remove() {
        synchronized (this) {
            if (running) kill();

            store.remove(this);
        }
    }

    /**
     * Send a command to the server via a source console
     */
    void sendCMD(string value) {
        synchronized (this) {
            processPipes.stdin.writeln(value);
            processPipes.stdin.flush();
        }
    }

    private void log(string line, bool cache = true) {
        if (logPath is null) {
            logPath = config.application.buildLogPath(name ~ ".log");
            logs = DList!string(new string[LOG_LENGTH]);
        }

        append(logPath, line ~ "\n");
        if (cache) {
            synchronized (this) {
                logs.removeFront();
                logs.insertBack(line);
            }
        }
    }

    /**
     * Reads a line asynchronously from the process's stdout
     */
    private auto readline() {
        auto line = processPipes.stdout.readlnNoBlock();
        if (line == null) return null;
        line = line[0..$-1]; // source uses CRLF and readlnNoBlock stops at LF

        log(line, true);
        //logInfo("Server '%s': %s", name, line);
        return line;
    }

    private auto readlineRange(string firstLine) {
        struct Range {
            this(string f, Server s) {
                front = f;
                server = s;
            }
            string front;
            Server server;
            void popFront() { front = server.readline(); }
            @property bool empty() { return front is null; }
        }
        return Range(firstLine, this);
    }

    private void watcher() shared {
        logInfo("Started watcher for %s", name);
        while (sharedRunning) {
            try {
                (cast(Server)this).watch();
            } catch (Throwable e) {
                logError("'%s' Watcher: %s", name, e);
            }
        }
        logInfo("Terminated watcher for %s", name);
    }

    private void watch() {
        auto line = readline();
        if (line == null) {
            sleep(100.dur!"msecs");
            return;
        }

        auto range = readlineRange(line);
        if (status.parse(range)) {
            if (!status.running) {
                status.sendPoll(this);
            }
        }
    }

    private void poller() shared {
        logInfo("Started poller for %s", name);
        while (sharedRunning) {
            try {
                (cast(Server)this).poll();
            } catch (Throwable e) {
                logError("'%s' Poller: %s", name, e);
            }
        }
        logInfo("Terminated poller for %s", name);
    }

    private void poll() {
        if (status.running) {
            status.sendPoll(this);
        }

        sleep(POLL_INTERVAL);
    }
}
