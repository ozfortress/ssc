module web.controller.controller;
import web.controller;

import models;
static import store;

@path("/controller")
class ControllerInterface {
    mixin WebInterface;

    @path("")
    void getIndex(scope HTTPServerRequest req, scope HTTPServerResponse res) {
        requireAuthentication(req, res);
        render!("controller/index.dt");
    }

    void getServersTable(scope HTTPServerRequest req, scope HTTPServerResponse res) {
        requireAuthentication(req, res);
        auto servers = Server.all;
        render!("controller/servers_table.dt", servers);
    }

    void getBookingsTable(scope HTTPServerRequest req, scope HTTPServerResponse res) {
        requireAuthentication(req, res);
        auto bookings = Booking.all;
        render!("controller/bookings_table.dt", bookings);
    }

    void postReloadServers(scope HTTPServerRequest req, scope HTTPServerResponse res) {
        requireAuthentication(req, res);
        Server.reload();
        emptyResponse;
    }

    void postRestartServers(scope HTTPServerRequest req, scope HTTPServerResponse res) {
        requireAuthentication(req, res);
        Server.restartAll(false);
        emptyResponse;
    }

    void postDirtyServers(scope HTTPServerRequest req, scope HTTPServerResponse res) {
        requireAuthentication(req, res);
        Server.restartAll(true);
        emptyResponse;
    }
}
