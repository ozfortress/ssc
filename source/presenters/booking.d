module presenters.booking;
import presenters;

import std.datetime;

import vibe.d;

import models;

struct BookingPresenter {
    Booking booking;
    alias booking this;

    this(Booking booking) {
        this.booking = booking;
    }

    @property auto server() {
        return ServerPresenter(booking.server);
    }

    string deletePath() {
        return "/controller/bookings/%s/delete".format(server.name);
    }

    Json toJson(bool includeServer = true) {
        auto j = Json([
            "client": Json(booking.client),
            "user": Json(booking.user),
            "startedAt": Json(booking.startedAt.toISOExtString),
            "endsAt": Json(booking.endsAt.toISOExtString),
        ]);

        if (includeServer) j["server"] = server.toJson(false);

        return j;
    }
}
