module web.api.api;

import vibe.d;
import vibe.web.rest;

static import config.keys;

static string authenticatev1(scope HTTPServerRequest req, scope HTTPServerResponse res) {
    enforceHTTP("key" in req.query, HTTPStatus.forbidden, "Invalid key");
    auto key = req.query["key"];
    auto client = config.keys.authenticate(key);
    enforceHTTP(client !is null, HTTPStatus.forbidden, "Invalid key");

    return client;
}

enum authv1 = before!authenticatev1("client");

@path("/api/v1")
interface SSCV1API {
    Collection!ServerV1API servers();
    Collection!BookingV1API bookings();
}

interface ServerV1API {
    struct CollectionIndices {
        string _serverName;
    }

    @path("/")
    @authv1
    Json get(string client);

    @path("/restart/")
    @authv1
    void postRestart(string client);
}

interface BookingV1API {
    struct CollectionIndices {
        string _user;
    }

    @path("/")
    @authv1
    @queryParam("user", "user")
    @queryParam("hours", "hours")
    Json create(string client, string user, ushort hours);

    @authv1
    Json get(string _user, string client);

    @authv1
    void remove(string _user, string client);
}
