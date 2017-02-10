module config.keys;

import std.file;
import std.json;

import util.json;
import config.application;

const CONFIG_FILE = "keys.json";

private const shared static string[string] _keys;

shared static this() {
    auto json = readJSON(buildConfigPath(CONFIG_FILE));

    shared string[string] keys;
    foreach (string client, key; json.object) {
        keys[key.str] = client;
    }
    _keys = keys;
}

string authenticate(string key) {
    if (key in _keys) {
        return _keys[key];
    }
    return null;
}
