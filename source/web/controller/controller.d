module web.controller.controller;
import web.controller;

import models;
static import store;

@path("/controller")
class ControllerInterface {
    mixin WebInterface;

    @path("")
    void getIndex(scope HTTPServerRequest req) {
        requireAuthentication(req);
        render!("controller/index.dt", key);
    }

    void getServersTable(scope HTTPServerRequest req) {
        requireAuthentication(req);
        auto servers = Server.all;
        render!("controller/servers_table.dt", servers, key);
    }

    void getBookingsTable(scope HTTPServerRequest req) {
        requireAuthentication(req);
        auto bookings = Booking.all;
        render!("controller/bookings_table.dt", bookings, key);
    }

    void postReloadServers(scope HTTPServerRequest req) {
        requireAuthentication(req);
        Server.reload();
        emptyResponse;
    }

    void postRestartServers(scope HTTPServerRequest req) {
        requireAuthentication(req);
        Server.restartAll(false);
        emptyResponse;
    }

    void postDirtyServers(scope HTTPServerRequest req) {
        requireAuthentication(req);
        Server.restartAll(true);
        emptyResponse;
    }
}
