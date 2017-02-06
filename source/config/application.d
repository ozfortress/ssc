module config.application;

import std.file;
import std.path;
import std.string;

import vibe.d;

import config.env;
import util.json;

const CONFIG_PATH = "config";

/**
 * Settings struct for easy json parsing
 */
private struct Settings {
    mixin JsonizeMe;

    @jsonize(Jsonize.opt) {
        ushort port = 8080;
        @jsonize("bind-addresses") string[] bindAddresses = ["::1", "127.0.0.1"];
        string hostName = "ssc";

        @jsonize("log-dir") string logDir = "logs";
        @jsonize("log-level") LogLevel logLevel = LogLevel.info;
    }
}

private shared Settings _settings;

shared static this() {
    auto json = readJSON(buildConfigPath("environments", env ~ ".json"));
    auto common = readJSON(buildConfigPath("application.json"));
    json.merge(common);

    _settings = cast(shared)json.fromJSON!Settings;

    // Initialize directories
    mkdirRecurse(logsPath);
}

@property auto serverSettings() {
    auto settings = new HTTPServerSettings;
    settings.port = _settings.port;
    settings.bindAddresses = cast(string[])_settings.bindAddresses;
    settings.hostName = _settings.hostName;
    return settings;
}

auto buildConfigPath(string[] args...) {
    return buildPath([CONFIG_PATH] ~ args);
}

auto buildLogPath(string[] args...) {
    return buildPath([logsPath] ~ args);
}

@property auto logsPath() {
    return _settings.logDir;
}

@property auto logFile() {
    return buildPath(logsPath(), env ~ ".log");
}

@property auto logLevel() {
    return _settings.logLevel;
}
