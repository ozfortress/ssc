module web.api.v1;
import web.api.api;

import std.array;
import std.algorithm;

import vibe.d;

import store;
import models;
import presenters;
import config.clients;

class SSCV1APIImpl : SSCV1API {
    private ServerAPIImpl serverApi;
    private BookingAPIImpl bookingApi;

    this() {
        serverApi = new typeof(serverApi);
        bookingApi = new typeof(bookingApi);
    }

    Collection!(ServerV1API) servers() {
        return Collection!(ServerV1API)(serverApi);
    }

    Collection!(BookingV1API) bookings() {
        return Collection!(BookingV1API)(bookingApi);
    }
}

class ServerAPIImpl : ServerV1API {
    Json get(Client client) {
        auto servers = Server.all;

        auto result = Json.emptyObject;
        result["length"] = servers.length;
        result["servers"] = servers.map!(s => ServerPresenter(s).toJson).array;
        return result;
    }

    void postRestart(Client client) {
        Server.restartAll;
    }
}

class BookingAPIImpl : BookingV1API {
    Json create(Client client, string user, ushort hours) {
        Booking booking;
        try {
            booking = Booking.create(client, user, hours.dur!"hours");
        } catch (StoreException e) {
            enforceHTTP(false, HTTPStatus.conflict, "Duplicate client/user");
        }

        return BookingPresenter(booking).toJson;
    }

    Json get(string _user, Client client) {
        auto booking = Booking.find(client, _user);
        enforceHTTP(booking !is null, HTTPStatus.notFound, "Booking not found");

        return BookingPresenter(booking).toJson;
    }

    void remove(string _user, Client client) {
        auto booking = Booking.find(client, _user);
        enforceHTTP(booking !is null, HTTPStatus.notFound, "Booking not found");

        booking.end();
        enforceHTTP(false, HTTPStatus.noContent);
    }
}
