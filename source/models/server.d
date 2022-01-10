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
import supervised;

import store;
import util.json;
import util.random;
import util.source;
import config.application;

auto createTimer(void delegate() @safe callback) @safe {
    return vibe.core.core.createTimer(() @trusted nothrow {
        try {
            callback();
        } catch (Exception error) {
            logWarn("Timer callback failed: %s", error.toString());

            scope (failure) assert(false);
        }
    });
}

class Server {
    static const POLL_INTERVAL = 15.dur!"seconds";
    static const POLL_TIMEOUT = 2.dur!"minutes";
    static const LOG_LENGTH = 30;
    static const MIN_IDLE_PLAYERS = 2;
    static const SERVER_KICK_DELAY = 5.dur!"seconds";
    static const IDLE_BOOKING_UNIT = "minutes";

    static shared Store!(Server, "name") store; // Initialized in package.d

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
    ServerStatusParser statusParser;
    Booking booking = null;

    private {
        shared ProcessMonitor processMonitor;

        DateTime lastActive;
        Timer idleTimeoutTimer;
        Timer pollTimer;
        Timer pollTimeoutTimer;

        enum TimerType {
            idleTimeout,
            poll,
            pollTimeout,
        }
        Task timerTask;
    }

    @property auto available() {
        return bookable && booking is null && active;
    }

    @property auto active() {
        return running && status.running;
    }

    this() {
        processMonitor = new shared ProcessMonitor;

        processMonitor.stdoutCallback = (line) @trusted => this.onReadLine(line);
        processMonitor.stderrCallback = (line) @trusted => this.onReadLine(line);
        processMonitor.terminateCallback = () @trusted => this.onServerStop();

        idleTimeoutTimer = createTimer(() @trusted => this.onIdleBookingTimeout());
        pollTimer = createTimer(() @trusted => this.sendPoll());
        pollTimeoutTimer = createTimer(() @trusted => this.onPollTimeout());

        // Timers can only be manipulated from the thread that created them, ie. the main thread.
        // So we need to start a task that handles the timers for us
        // TODO: Kill this task when the server dies
        timerTask = runTask({
            auto running = true;
            while (running) {
                std.concurrency.receive(
                    (TimerType type, Duration duration) {
                        Timer timer;
                        final switch (type) {
                            case TimerType.idleTimeout:
                                timer = idleTimeoutTimer;
                                break;
                            case TimerType.poll:
                                timer = pollTimer;
                                break;
                            case TimerType.pollTimeout:
                                timer = pollTimeoutTimer;
                                break;
                        }
                        timer.rearm(duration);
                    },
                    (bool _) {
                        running = false;
                    },
                );
            }
        });
    }

    /**
     * Hook for when a booking starts
     */
    void onBookingStart(Booking booking) {
        this.booking = booking;

        if (idleBookingTimeout > 0) idleTimeoutTimer.rearm(idleBookingTimeout.dur!IDLE_BOOKING_UNIT);

        reset();

        if (bookingStartCommand !is null) {
            auto command = bookingStartCommand.replace("{client}", booking.client.name)
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

        if (idleTimeoutTimer) idleTimeoutTimer.stop();

        if (!willDelete) reset();

        if (bookingEndCommand !is null) {
            auto command = bookingEndCommand.replace("{client}", booking.client.name)
                                            .replace("{user}", booking.userEscaped);
            sendCMD(command);
        }

        this.booking = null;

        if (willDelete) remove();
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

        try {
            processMonitor.kill();
            processMonitor.wait();
        } catch (Exception e) {}
        spawn();
    }

    /**
     * Start the server, spawning a server process and a watcher for it.
     * Also resets the server.
     */
    void spawn() {
        synchronized (this) {
            // Reduce options map to an array
            auto kvoptions = this.options.byKeyValue.map!(o => [o.key, o.value]);
            string[] options = reduce!"a ~ b"(cast(string[])null, kvoptions);

            // Always enable the console
            options ~= "-console";

            // script captures /dev/tty in stdout
            auto params = ["unbuffer", "-p", executable] ~ options;

            processMonitor.start(params.idup);

            resetPollTimers();

            dirty = false;
            reset();
            sendPoll();
        }
    }

    /**
     * Check whether the server process is running
     */
    @property bool running() @safe {
        return processMonitor.running;
    }

    /**
     * Kill the running server
     */
    void kill() {
        processMonitor.kill();
        processMonitor.wait();
    }

    /**
     * Send a command to the server via a source console
     */
    void sendCMD(string command, string[] args...) {
        auto line = formatCommand(command, args);
        processMonitor.send(line);
    }

    /**
     * Called when the process stops
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

        // Kill the timer task as well
        timerTask.send(true);

        store.remove(this);
    }

    /**
     * Reload the server configuration (using another server instance)
     * Use to update settings on a running server by setting the dirty flag and waiting for a time to restart
     */
    private void reload(Server config) {
        bool changed;

        synchronized (this) {
            changed = executable != config.executable || options != config.options;

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

        // Make dirty if server options change
        if (changed) {
            makeDirty();
        }
    }

    // Callback for when a line is read from the server
    private void onReadLine(string line) {
        // Parse the output to check for status updates
        if (statusParser.parse(&status, line)) {
            resetPollTimers();

            if (idleTimeoutTimer && idleBookingTimeout > 0 && booking &&  status.humanPlayers >= MIN_IDLE_PLAYERS) {
                timerTask.tid.send(TimerType.idleTimeout, cast(Duration)idleBookingTimeout.dur!IDLE_BOOKING_UNIT);
            }
        }

        log(line);
    }

    private void log(string line) {
        // Create the log file if it doesn't exist
        if (logPath is null) {
            logPath = config.application.buildLogPath(name ~ ".log");
            logs = DList!string(new string[logLength]);
        }

        // Write to the server log file
        append(logPath, line ~ "\n");
        synchronized (this) {
            if (logLength != 0) logs.removeFront();
            logs.insertBack(line);
        }
    }

    private void sendPoll() {
        try {
            sendCMD("status");
            sendCMD("sv_password");
            sendCMD("rcon_password");
        } catch (InvalidStateException error) {
            logWarn("Failed to send poll, process not running");
        }
    }

    private void onPollTimeout() {
        // After a large timeout, send the poll again. Adds stability for the case when srcds misses a poll
        sendPoll();
        log("SSC: Poll Timeout");
    }

    private void onIdleBookingTimeout() {
        // TODO: Come up with a way to do synchronization properly
        //synchronized (this) {
        auto booking = this.booking;
        if (booking !is null) booking.end();
        //}
    }

    private void resetPollTimers() {
        timerTask.tid.send(TimerType.poll, cast(Duration)POLL_INTERVAL);
        timerTask.tid.send(TimerType.pollTimeout, cast(Duration)POLL_TIMEOUT);
    }
}
