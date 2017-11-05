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
        return "/bookings/%s/delete".format(server.name);
    }

    string demosURL() {
        import base32;
        return "https://demos.ozfortress.com/%s/%s".format(booking.client, Base32.encode(booking.user).toLower);
    }

    Json toJson(bool includeServer = true) {
        auto j = Json([
            "client": Json(booking.client.name),
            "user": Json(booking.user),
            "startedAt": Json(booking.startedAt.toISOExtString),
            "endsAt": Json(booking.endsAt.toISOExtString),
        ]);

        if (includeServer) j["server"] = server.toJson(false);

        return j;
    }
}
