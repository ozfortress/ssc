module config.clients;

import std.file;
import std.typecons;

import vibe.d;

import util.json;
import config.application;

const CONFIG_FILE = "clients.json";

struct Client {
    string name;
    string secret;
    bool isAdmin = false;
}

private __gshared Client[string] _clientSecretMap;

void init() {
    auto json = parseJsonString(readText(buildConfigPath(CONFIG_FILE)));
    auto clients = deserializeJson!(Client[])(json);

    foreach (client; clients) {
        _clientSecretMap[client.secret] = client;
    }
}

Nullable!Client authenticate(string secret) {
    if (secret in _clientSecretMap) {
        return _clientSecretMap[secret].nullable;
    }
    return Nullable!Client.init;
}
