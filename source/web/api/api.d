module web.api.api;

import vibe.d;
import vibe.web.rest;

import config.clients;

static Client authenticatev1(scope HTTPServerRequest req, scope HTTPServerResponse res) {
    enforceHTTP("key" in req.query, HTTPStatus.forbidden, "Invalid key");
    auto key = req.query["key"];
    auto client = authenticate(key);
    enforceHTTP(!client.isNull, HTTPStatus.forbidden, "Invalid key");

    return client.get;
}

static Client authenticatev1Admin(scope HTTPServerRequest req, scope HTTPServerResponse res) {
    auto client = authenticatev1(req, res);

    enforceHTTP(client.isAdmin, HTTPStatus.forbidden, "Must be admin");

    return client;
}

enum authv1 = before!authenticatev1("client");
enum authv1Admin = before!authenticatev1Admin("client");

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
    Json get(Client client);

    @path("/restart/")
    @authv1Admin
    void postRestart(Client client);
}

interface BookingV1API {
    struct CollectionIndices {
        string _user;
    }

    @path("/")
    @authv1
    @queryParam("user", "user")
    @queryParam("hours", "hours")
    Json create(Client client, string user, ushort hours);

    @authv1
    Json get(string _user, Client client);

    @authv1
    void remove(string _user, Client client);
}
