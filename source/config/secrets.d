module config.secrets;

import std.file;
import std.json;
import std.exception;

import jsonizer.fromjson;

const CONFIG_PATH = "config/secrets.json";

private const shared static string[string] _secrets;

shared static this() {
    auto json = parseJSON(readText(CONFIG_PATH));

    _secrets = json.fromJSON!(shared string[string]);
}

static auto get(string value) {
    if (value !in _secrets) {
        return null;
    }
    return _secrets[value];
}

