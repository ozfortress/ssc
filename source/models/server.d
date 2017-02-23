module models.server;
import models;

import core.thread;
import std.file;
import std.array;
import std.string;
import std.process;
import std.datetime;
import std.algorithm;
import std.container;

import vibe.d;
import vibe.stream.stdio;
import jsonizer : fromJSON;

import store;
import util.io;
import util.json;
import util.random;
import util.source;
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

    static @property auto allAvailable() {
        return all.filter!(s => s.available);
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
                if (!server.running || (server.bookable && server.booking is null)) {
                    server.remove();
                } else {
                    server.willDelete = true;
                }
            }
        }
    }

    static void restartAll(bool makeDirty = true) {
        // Restart concurrently, since it blocks
        auto tasks = all.map!(server => runTask({
            if (makeDirty) {
                server.makeDirty();
            } else {
                server.restart();
            }
        })).array;

        foreach (task; tasks) task.join();
    }

    mixin JsonizeMe;
    @jsonize(Jsonize.opt) {
        string name;
        string executable;
        string[string] options;

        @jsonize("auto-start")            bool autoStart = true;
        @jsonize("bookable")              bool bookable = true;
        @jsonize("restart-after-booking") bool restartAfterBooking = true;
        @jsonize("auto-password")         bool autoPassword = true;
        @jsonize("reset-command")         string resetCommand = null;
        @jsonize("booking-start-command") string bookingStartCommand = null;
        @jsonize("booking-end-command")   string bookingEndCommand = null;
        @jsonize("log-path")              string logPath = null;
    }

    bool dirty = true;
    bool willDelete = false;
    bool pollingEnabled = true;
    DList!string logs;
    ServerStatus status;
    Booking booking = null;

    private {
        ProcessPipes processPipes;
        Thread processWatcher;
        Thread processPoller;
        bool statusSent = false;
    }

    @property auto available() {
        return bookable && booking is null && active;
    }

    @property auto active() {
        return running && status.running;
    }

    this() {
    }

    /**
     * Hook for when a booking starts
     */
    void onBookingStart(Booking booking) {
        this.booking = booking;

        reset();
        if (bookingStartCommand !is null) {
            auto command = bookingStartCommand.replace("{client}", booking.client)
                                              .replace("{user}", booking.userEscaped);
            sendCMD(command);
        }
    }

    /**
     * Hook for when a booking ends
     */
    void onBookingEnd(Booking booking) {
        this.booking = null;

        if (restartAfterBooking) {
            restart();
        } else {
            reset();

            if (bookingEndCommand !is null) {
                auto command = bookingEndCommand.replace("{client}", booking.client)
                                                .replace("{user}", booking.userEscaped);
                sendCMD(command);
            }
        }
    }

    /**
     * Generate a strong set of passwords.
     */
    void generatePasswords() {
        enforce(running);
        // Update status immediately for getting connect strings
        status.password = randomBase64(12);
        status.rconPassword = randomBase64(12);

        sendCMD("sv_password", status.password);
        sendCMD("rcon_password", status.rconPassword);
    }

    /**
     * Reset the server by running the reset command and restarting if dirty.
     * Will also kick all players for the given reason.
     */
    void reset(string reason = "Server Reset") {
        enforce(running);
        sendCMD("kickall", reason);

        if (dirty) {
            restart();
        } else {
            if (resetCommand !is null) sendCMD(resetCommand);
            if (autoPassword) generatePasswords();
        }
    }

    /**
     * Marks the server as dirty, making the server restart either immediately or when it becomes available
     */
    void makeDirty() {
        if (available) {
            restart();
        } else {
            dirty = true;
        }
    }

    /**
     * Restart the server, killing and respawning
     */
    void restart() {
        auto booking = this.booking;
        if (booking !is null) booking.end();

        if (running) kill();
        spawn();
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

            processWatcher = new Thread(() => this.watcher).start();
            processPoller = new Thread(() => this.poller).start();

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
            processPipes = typeof(processPipes).init;
            enforce(!running);

            // Reset status
            status = ServerStatus();
        }
        processWatcher.join();
        processPoller.join();
    }

    /**
     * Send a command to the server via a source console
     */
    void sendCMD(string command, string[] args...) {
        synchronized (this) {
            processPipes.stdin.writeln(formatCommand(command, args));
            processPipes.stdin.flush();
        }
    }

    /**
     * Initialize the server, called when a server is ready to be added to the store
     */
    private void create() {
        store.add(this);

        if (autoStart) spawn();
    }

    /**
     * Remove the server, killing if necessary
     */
    private void remove() {
        synchronized (this) {
            if (running) kill();

            store.remove(this);
        }
    }

    /**
     * Reload the server configuration (using another server instance)
     * Use to update settings on a running server by setting the dirty flag and waiting for a time to restart
     */
    private void reload(Server config) {
        synchronized (this) {
            if (executable != config.executable || options != config.options) {
                // Reset if we wouldn't disturb anyone
                if (available) reset();
                else dirty = true;
            }

            executable = config.executable;
            options = config.options;
            autoStart = config.autoStart;
            bookable = config.bookable;
            resetCommand = config.resetCommand;
            logPath = config.logPath;
        }
    }

    /// Writes to the server log file
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
        string line;
        synchronized (this) line = processPipes.stdout.readlnNoBlock();
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

    /// Watcher thread for the server process
    private void watcher() {
        logInfo("Started watcher for '%s'", name);
        while (running) {
            try {
                watch();
            } catch (Throwable e) {
                logError("'%s' Watcher: %s", name, e);
            }
        }
        logInfo("Terminated watcher for '%s'", name);
    }

    private void watch() {
        auto line = readline();
        if (line == null) {
            Thread.sleep(200.dur!"msecs");
            return;
        }

        auto range = readlineRange(line);
        if (status.parse(range)) {
            if (!status.running) {
                status.sendPoll(this);
            }
        }
    }

    /// Poller thread for the server process
    private void poller() {
        logInfo("Started poller for %s", name);
        while (running) {
            try {
                poll();
            } catch (Throwable e) {
                logError("'%s' Poller: %s", name, e);
            }
        }
        logInfo("Terminated poller for %s", name);
    }

    private void poll() {
        auto startTime = Clock.currTime();

        while (true) {
            if (!running) return;

            auto now = Clock.currTime();
            if (now - startTime > POLL_INTERVAL) {
                break;
            }
            Thread.sleep(200.dur!"msecs");
        }

        if (status.running && pollingEnabled) {
            status.sendPoll(this);
        }
    }
}
