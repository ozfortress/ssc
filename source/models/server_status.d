module models.server_status;
import models;

import vibe.d;

import std.conv;
import std.stdio;
import std.range;
import std.regex;
import std.string;
import std.datetime;
import std.exception;
import std.algorithm;

struct ServerStatusParser {
    // Parse state
    private {
        enum StatusState {
            initial,
            header,
            table,
        }

        auto statusState = StatusState.initial;
    }

    bool parse(ServerStatus* status, string line) {
        if (statusState == StatusState.initial) {
            return parseLine(status, line);
        } else if (statusState == StatusState.header) {
            parseHeader(status, line);
        } else if (statusState == StatusState.table) {
            parseTable(status, line);
        }

        return false;
    }

    private bool parseLine(ServerStatus* status, string line) {
        if (line.startsWith("hostname: ")) {
            status.running = true;
            status.lastStatusUpdate = cast(DateTime)Clock.currTime();

            statusState = StatusState.header;

            parseHeader(status, line);

            return true;
        } else if (matchVariable(line, "sv_password")) {
            status.password = parseVariable(line);
        } else if (matchVariable(line, "rcon_password")) {
            status.rconPassword = parseVariable(line);
        } else if (line.strip() == "Killed") {
            status.running = false;
        }

        return false;
    }

    private void parseHeader(ServerStatus* status, string line) {
        auto separatorIndex = line.indexOf(':');
        // Move to parsing the table, if the table header was encountered (It doesn't have a `:` in it)
        if (separatorIndex == -1) {
            statusState = StatusState.table;
            return;
        }

        auto title = line[0..separatorIndex].strip();
        auto value = line[separatorIndex + 1..$].strip();

        switch (title) {
            case "hostname":
                status.hostname = value;
                break;
            case "udp/ip":
                status.address = parseUDPIP(value);
                break;
            case "map":
                status.map = value.split(" ")[0];
                break;
            case "players":
                status.humanPlayers = value.matchFirst(`\d+ humans`).front.split(" ")[0].to!size_t;
                status.botPlayers = value.matchFirst(`\d+ bots`).front.split(" ")[0].to!size_t;
                status.maxPlayers = value.matchFirst(`\d+ max`).front.split(" ")[0].to!size_t;
                break;
            default:
                break;
        }
    }

    private void parseTable(ServerStatus* status, string line) {
        // TODO: Actually parse players
        statusState = StatusState.initial;
    }

    private string parseUDPIP(const string line) {
        auto udp = line.matchFirst(`[0-9\.]+:[0-9]+`);
        if (udp.empty) return "";
        auto ip_port = udp.front.split(":");
        auto ip = ip_port[0];
        auto port = ip_port[1];
        return "%s:%s".format(ip, port);
    }

    private bool matchVariable(string line, string name) {
        return line.startsWith(`"%s" = "`.format(name));
    }

    private string parseVariable(string line) {
        return line.split(" = ")[1].split(`"`)[1];
    }
}

struct ServerStatus {
    struct Player {
        uint id;
        string name;
        string steamId;
        uint ping;
        uint loss;
        string state;
        string address;
    }

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
    DateTime lastStatusUpdate;

    void onServerStop() {
        running = false;
    }
}

unittest {
    auto result = `
blah
blah
hostname: ozfortress.com 16 :: hosted by infinite.net.au
version : 4218712/24 4218712 secure
udp/ip  : 0.0.0.0:27161  (public ip: 119.15.96.156)
steamid : [A:1:279956484:9268] (90111798584265732)
account : not logged in  (No account specified)
map     : cp_process_final at: 0 x, 0 y, 0 z
tags    : cp,nocrits,ozfortress
sourcetv:  port 27164, delay 90.0s
players : 0 humans, 1 bots (25 max)
edicts  : 1047 used of 2048 max
# userid name                uniqueid            connected ping loss state  adr
#      2 "SourceTV"          BOT                                     active
sv_password
"sv_password" = "abcdefg" ( def. "" )
 notify
 - Server password for entry into multiplayer games
rcon_password
"rcon_password" = "hijklmnop" ( def. "" )`;

    ServerStatus status;
    ServerStatusParser parser;
    foreach (line; result.split("\n")) {
        parser.parse(&status, line);
    }

    assert(status.maxPlayers == 25);
    assert(status.password == "abcdefg");
    assert(status.rconPassword == "hijklmnop");
}
