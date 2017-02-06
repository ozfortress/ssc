module models.server;
import models;

import core.thread;
import std.path;
import std.conv;
import std.file;
import std.array;
import std.regex;
import std.format;
import std.process;
import std.datetime;
import std.algorithm;
import std.container;

import vibe.d;
import vibe.stream.stdio;
import jsonizer;

import store;
import util.io;
import util.json;
import util.random;
import config.application;

class Server {
    static const POLL_INTERVAL = 15.dur!("seconds");
    static const LOG_LENGTH = 30;

    shared static this() {
        store = new typeof(store);
    }
    private static shared Store!(Server, "name") store;

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
        auto json = parseJSON(readText(buildConfigPath("servers.json")));

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
                store.add(server);
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

    ~this() {
        kill();
    }

    void generatePasswords() {
        sendCMD(`sv_password "%s"`.format(randomBase64(12)));
        sendCMD(`rcon_password "%s"`.format(randomBase64(12)));
    }

    /**
     * Reload the server configuration (using another server instance)
     * Use to update settings on a running server by setting the dirty flag and waiting for a time to restart
     */
    void reload(Server config) {
        name = config.name;
        executable = config.executable;
        options = config.options;
        bookable = config.bookable;
        dirty = true;
    }

    /**
     * Reset the server by running the reset command
     */
    void reset() {
        if (resetCommand !is null) sendCMD(resetCommand);
    }

    /**
     * Restart the server, killing and respawning
     */
    void restart() {
        synchronized (this) {
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
            // script captures /dev/tty which valve seems to love
            // but we do our own log storing, so save to /dev/null
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
            sendStatusPoll();
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

    @property bool sharedRunning() shared {
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
            logPath = buildPath(config.application.logsPath, name ~ ".log");
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

    private struct ServerStatus {
        string hostname;
        string address;
        string map;
        size_t humanPlayers = 0;
        size_t botPlayers = 0;
        size_t maxPlayers = 0;
        string password;
        string rconPassword;
        bool hybernating = false;
        bool running = false;
        DateTime lastUpdate;

        @property string connectString() {
            return "connect %s; password \"%s\"; rcon_password \"%s\"".format(address, password, rconPassword);
        }
    }

    private void sendStatusPoll() {
        if (statusSent) {
            // Status is already sent, waiting on watcher to read the result
            return;
        }
        statusSent = true;
        sendCMD("status");
        sendCMD("sv_password");
        sendCMD("rcon_password");
    }

    private auto readline() {
        auto line = processPipes.stdout.readlnNoBlock();
        if (line == null) return null;

        logInfo("Server '%s': %s", name, line);
        return line;
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

        auto cacheLine = true;

        // status
        if (line.startsWith("hostname: ")) {
            statusSent = false; // Allow another status update to be queried
            status.running = true; // Once we read a status, the server is properly responding
            status.lastUpdate = cast(DateTime)Clock.currTime();

            cacheLine = false; // Don't output this, parse it instead

            parseStatus(line);
        } else if (matchVariable(line, "sv_password")) {
            status.password = parseVariable(line);
        } else if (matchVariable(line, "rcon_password")) {
            status.rconPassword = parseVariable(line);
        } else if (line == "Server is hibernating") {
            status.hybernating = true;
        } // TODO: wakeup
        else if (line == "Killed") {
            status.running = false;
            statusSent = false;
            sendStatusPoll();
        }

        log(line, cacheLine);
    }

    private void parseStatus(string line) {
        status.hostname = line.split(":")[1].strip();
        /*version =*/readline();
        auto udpIp = readline();
        auto udp = udpIp.matchFirst(`[0-9\.]+:[0-9]+`).front;
        auto port = udp.split(":")[1];
        auto ip = udpIp.matchFirst(`public ip: [0-9\.]+`).front.split(":")[1].strip();
        status.address = "%s:%s".format(ip, port);
        /*steamID = */readline();
        /*account = */readline();
        auto map = readline();
        status.map = map.split(":")[1].strip().split(" ")[0];
        /*tags = */readline();
        auto players = readline();
        if (players.startsWith("sourcetv")) players = readline();
        logInfo(players);
        status.humanPlayers = matchFirst(players, `\d+ humans`).front.split(" ")[0].to!size_t;
        status.botPlayers = matchFirst(players, `\d+ bots`).front.split(" ")[0].to!size_t;
        status.maxPlayers = matchFirst(players, `\d+ max`).front.split(" ")[0].to!size_t;

        // TODO: parse players
    }

    private bool matchVariable(string line, string name) {
        return line.startsWith(`"%s" = "`.format(name));
    }

    private string parseVariable(string line) {
        return line.split(" = ")[1].split(`"`)[1];
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
            sendStatusPoll();
        }

        sleep(POLL_INTERVAL);
    }
}
