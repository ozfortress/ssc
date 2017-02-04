module web.controller.bookings;
import web.controller;

static import store;
import models;

@path("/bookings/:server")
class BookingsInterface {
    mixin WebInterface;

    Booking booking;

    protected void requireBooking(scope HTTPServerRequest req) {
        auto server = Server.get(req.params["server"]);
        booking = Booking.bookingFor(cast(Server)server);
        enforceHTTP(booking !is null, HTTPStatus.notFound);
    }

    @path("")
    void postCreate(scope HTTPServerRequest req) {
        requireAuthentication(req);
        requireBooking(req);

        emptyResponse;
    }
}
