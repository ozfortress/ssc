module models.server_status;
import models;

import std.conv;
import std.regex;
import std.string;
import std.datetime;
import std.exception;
import std.algorithm;

struct ServerStatus {
    string hostname;
    string address;
    string map;
    size_t humanPlayers = 0;
    size_t botPlayers = 0;
    size_t maxPlayers = 0;
    string password;
    string rconPassword;
    Player[] players;

    bool hybernating = false;
    bool running = false;
    DateTime lastUpdate;

    bool sent; // State for poll/watch

    struct Player {
        uint id;
        string name;
        string steamId;
        uint ping;
        uint loss;
        string state;
        string address;
    }

    void sendPoll(Server server) {
        if (sent) {
            // Status is already sent, waiting on watcher to read the result
            return;
        }
        sent = true;
        server.sendCMD("status");
        server.sendCMD("sv_password");
        server.sendCMD("rcon_password");
    }

    bool parse(R)(R range) {
        enforce(!range.empty);
        auto line = range.front;

        // status command
        if (line.startsWith("hostname: ")) {
            sent = false; // Allow another status update to be queried
            running = true; // Once we read a status, the server is properly responding
            lastUpdate = cast(DateTime)Clock.currTime();

            parseStatus(range);
        } else if (matchVariable(line, "sv_password")) {
            password = parseVariable(line);
        } else if (matchVariable(line, "rcon_password")) {
            rconPassword = parseVariable(line);
        }
        // TODO: Hybernation/Wakeup
        /*else if (line == "Server is hibernating") {
            status.hybernating = true;
        }*/
        else if (line == "Killed") {
            running = false;
            sent = false;
        } else {
            return false;
        }
        return true;
    }

    private void parseStatus(R)(R range) {
        foreach (line; range) {
            auto split = line.splitter(":");
            string head = split.front.strip();
            split.popFront();
            if (split.empty) break;
            string value = split.join(":").strip();

            switch (head) {
                case "hostname":
                    hostname = value;
                    break;
                case "udp/ip":
                    address = parseUDPIP(value);
                    break;
                case "map":
                    map = value.split(" ")[0];
                    break;
                case "players":
                    humanPlayers = value.matchFirst(`\d+ humans`).front.split(" ")[0].to!size_t;
                    botPlayers = value.matchFirst(`\d+ bots`).front.split(" ")[0].to!size_t;
                    maxPlayers = value.matchFirst(`\d+ max`).front.split(" ")[0].to!size_t;
                    break;
                default:
                    break;
            }
        }

        // Parse until the players header
        foreach (line; range) {
            if (line.startsWith("# userid")) break;
        }

        // Parser players list
        // TODO
        /*foreach (index; 0..status.humanPlayers + status.botPlayers) {
            line = readline();
            if (line is null) return;
        }*/
    }

    private string parseUDPIP(string line) {
        auto udp = line.matchFirst(`[0-9\.]+:[0-9]+`).front;
        auto port = udp.split(":")[1];
        auto ip = line.matchFirst(`public ip: [0-9\.]+`).front.split(":")[1].strip();
        return "%s:%s".format(ip, port);
    }

    private bool matchVariable(string line, string name) {
        return line.startsWith(`"%s" = "`.format(name));
    }

    private string parseVariable(string line) {
        return line.split(" = ")[1].split(`"`)[1];
    }
}
