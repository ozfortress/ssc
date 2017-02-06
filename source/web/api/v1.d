module web.api.v1;
import web.api.api;

import std.array;
import std.algorithm;

import vibe.d;

import store;
import models;
import presenters;
static import config.keys;

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
    Json get(string client) {
        auto servers = Server.all;

        auto result = Json.emptyObject;
        result["length"] = servers.length;
        result["servers"] = servers.map!(s => ServerPresenter(s).toJson).array;
        return result;
    }
}

class BookingAPIImpl : BookingV1API {
    Json create(string client, string user, ushort hours) {
        auto now = cast(DateTime)Clock.currTime();
        auto endsAt = now + hours.dur!"hours";

        Booking booking;
        try {
            booking = Booking.create(client, user, endsAt);
        } catch (StoreException e) {
            enforceHTTP(false, HTTPStatus.conflict, "Duplicate client/user");
        }

        return BookingPresenter(booking).toJson;
    }

    Json get(string _user, string client) {
        auto booking = Booking.find(client, _user);
        enforceHTTP(booking !is null, HTTPStatus.notFound, "Booking not found");

        return BookingPresenter(booking).toJson;
    }

    void remove(string _user, string client) {
        auto booking = Booking.find(client, _user);
        enforceHTTP(booking !is null, HTTPStatus.notFound, "Booking not found");

        booking.end();
        enforceHTTP(false, HTTPStatus.noContent);
    }
}

