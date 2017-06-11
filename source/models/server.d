module models.server;
import models;

import core.thread;
import std.file;
import std.conv;
import std.range;
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
import util.json;
import util.random;
import util.source;
import config.application;
import supervisor.poller;

class Server {
    static const POLL_INTERVAL = 15.dur!("seconds");
    static const POLL_TIMEOUT = 2.dur!("minutes");
    static const LOG_LENGTH = 30;
    static const MIN_IDLE_PLAYERS = 2;
    static const SERVER_KICK_DELAY = 5.dur!("seconds");

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
        auto defaultSettings = json["default"];
        foreach (server; json["servers"].array) {
            util.json.merge(server, defaultSettings);
        }

        return json["servers"].fromJSON!(Server[]);
    }

    static void reload() {
        auto serverList = readServerConfig();

        // Perform all actions asynchronously
        Task[] tasks;

        // Get a map from the list of servers
        Server[string] servers;
        foreach (server; serverList) {
            servers[server.name] = server;

            // Don't override existing servers, reload them with new settings instead
            auto old = store.get(server.name);
            if (old is null) {
                tasks ~= runTask((Server server) => server.create(), server);
            } else {
                tasks ~= runTask((Server old, Server server) => old.reload(server), old, server);
            }
        }

        // Mark servers not found in the new config for deletion
        foreach (server; store.all) {
            if (server.name !in servers) {
                if (!server.running || (server.bookable && server.booking is null)) {
                    tasks ~= runTask((Server server) => server.remove(), server);
                } else {
                    server.willDelete = true;
                }
            }
        }

        foreach (task; tasks) task.join();
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
        @jsonize("idle-booking-timeout")  size_t idleBookingTimeout = 15;
        @jsonize("reset-command")         string resetCommand = null;
        @jsonize("booking-start-command") string bookingStartCommand = null;
        @jsonize("booking-end-command")   string bookingEndCommand = null;
        @jsonize("log-path")              string logPath = null;
    }

    bool dirty = true;
    bool willDelete = false;
    bool pollingEnabled = true;
    DList!string logs;
    size_t logLength = LOG_LENGTH;
    ServerStatus status;
    Booking booking = null;

    private {
        ProcessPipes processPipes;
        Thread processWatcher;
        Thread processPoller;
        bool statusSent = false;

        DateTime lastActive;
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
        resetIdleTimer();
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
        if (restartAfterBooking) {
            dirty = true;
        }

        reset();

        if (bookingEndCommand !is null) {
            auto command = bookingEndCommand.replace("{client}", booking.client)
                                            .replace("{user}", booking.userEscaped);
            sendCMD(command);
        }

        this.booking = null;
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
            // Give the server time to kick everyone before restarting
            logInfo("Kicking Everyone: %s", reason);
            sleep(SERVER_KICK_DELAY);
            logInfo("Kicked Everyone");

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
        if (available || (!status.running && autoStart)) {
            restart();
        } else {
            dirty = true;
        }
    }

    /**
     * Restart the server, killing and respawning
     */
    void restart() {
        synchronized (this) {
            if (booking !is null) {
                booking.destroy();
                booking = null;
            }
        }

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

            // Reduce options map to an array
            auto kvoptions = this.options.byKeyValue.map!(o => [o.key, o.value]);
            string[] options = reduce!"a ~ b"(cast(string[])null, kvoptions);

            // Always enable the console
            options ~= "-console";

            // script captures /dev/tty in stdout
            auto params = ["unbuffer", "-p", executable] ~ options;

            log("Started with: %s".format(params));
            logInfo("Spawning %s with: %s", name, params);

            auto redirects = Redirect.stdin | Redirect.stdout | Redirect.stderrToStdout;
            processPipes = pipeProcess(params, redirects);

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

        onServerStop();
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
     * Called when the watcher thread stops.
     */
    private void onServerStop() {
        synchronized (this) {
            if (booking !is null) {
                booking.destroy();
                booking = null;
            }

            status.onServerStop();
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
        if (running) kill();

        store.remove(this);
}

    /**
     * Resets the timer for ending a booking when plays are idle on the server.
     */
    private void resetIdleTimer() {
        this.lastActive = cast(DateTime)Clock.currTime();
    }

    /**
     * Checks whether the idle timer has timed out.
     */
    private @property bool idleTimedOut() {
        auto now = cast(DateTime)Clock.currTime();
        return this.lastActive + idleBookingTimeout.dur!"minutes" < now;
    }

    /**
     * Reload the server configuration (using another server instance)
     * Use to update settings on a running server by setting the dirty flag and waiting for a time to restart
     */
    private void reload(Server config) {
        // Make dirty if server options change
        if (executable != config.executable || options != config.options) {
            makeDirty();
        }

        synchronized (this) {
            executable = config.executable;
            options    = config.options;

            autoStart           = config.autoStart;
            bookable            = config.bookable;
            restartAfterBooking = config.restartAfterBooking;
            autoPassword        = config.autoPassword;
            idleBookingTimeout  = config.idleBookingTimeout;
            resetCommand        = config.resetCommand;
            bookingStartCommand = config.bookingStartCommand;
            bookingEndCommand   = config.bookingEndCommand;
            logPath             = config.logPath;
        }
    }

    /// Writes to the server log file
    private void log(string line) {
        if (logPath is null) {
            logPath = config.application.buildLogPath(name ~ ".log");
            logs = DList!string(new string[logLength]);
        }

        append(logPath, line ~ "\n");
        synchronized (this) {
            if (logLength != 0) logs.removeFront();
            logs.insertBack(line);
        }
    }

    /**
     * Reads a line from the process's stdout
     */
    private auto readline() {
        auto line = processPipes.stdout.readln();
        // Strip any line ending characters
        line = line.stripRight!(chr => chr == '\n' || chr == '\r').text;

        log(line);
        return line;
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
        // Notify that the server stopped
        onServerStop();
        logInfo("Terminated watcher for '%s'", name);
    }

    private void watch() {
        auto hasData = pollReadable(processPipes.stdout.fileno, dur!"msecs"(500));
        if (!hasData) return;

        auto range = generate!(() => readline());
        if (status.parse(range)) {
            if (!status.running) {
                status.sendPoll(this);
            }

            // Check for idle timeouts
            if (booking !is null && idleBookingTimeout > 0) {
                if (status.humanPlayers >= MIN_IDLE_PLAYERS) {
                    resetIdleTimer();
                } else if (idleTimedOut()) {
                    runWorkerTask!(Booking.sharedEnd)(cast(shared)booking);
                }
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

        // If we didn't get first poll within the timeout time, send again.
        // Sometimes srcds likes to ignore the first 'status'
        auto now = Clock.currTime();
        auto pollingTimeout = now - startTime > POLL_TIMEOUT;

        if (pollingEnabled && (status.running || pollingTimeout)) {
            status.sendPoll(this);
        }
    }
}
