module presenters.server;
import presenters;

import std.string;
import std.datetime;

import vibe.d;

import models;

struct ServerPresenter {
    Server server;
    alias server this;

    this(Server server) {
        this.server = server;
    }

    @property auto booking() {
        return BookingPresenter(server.booking);
    }

    @property string connectString() {
        auto status = server.status;
        return "connect %s; password \"%s\"; rcon_password \"%s\"".format(
            status.address, status.password, status.rconPassword);
    }

    string path() {
        return "/servers/%s".format(server.name);
    }

    string path(string action) {
        return "/servers/%s/%s".format(server.name, action);
    }

    string statusDisplay() {
        auto name = statusName;
        if (server.dirty) {
            name ~= " (dirty)";
        }
        if (server.willDelete) {
            name ~= " (will delete)";
        }
        return name;
    }

    string statusName() {
        if (server.running) {
            if (server.status.running) {
                if (server.status.hybernating) {
                    return "Hybernating";
                }
                return "Active";
            }
            return "Starting";
        }
        return "Stopped";
    }

    string statusClass() {
        if (server.running) {
            if (server.status.running) {
                return "success";
            }
            return "info";
        }
        return "warning";
    }

    string bookingStatus() {
        if (server.bookable) {
            if (server.booking is null) {
                return "Available";
            }
            return "Booked";
        }
        return "Not Bookable";
    }

    string playerStatus() {
        auto status = "%s/%s".format(server.status.humanPlayers, server.status.maxPlayers);
        if (server.status.botPlayers > 0) {
            status ~= " (%s bots)".format(server.status.botPlayers);
        }
        return status;
    }

    auto lastUpdateDuration() {
        auto now = cast(DateTime)Clock.currTime();
        return now - server.status.lastUpdate;
    }

    string lastUpdate() {
        if (server.status.lastUpdate == DateTime.init) {
            return "never";
        }
        return lastUpdateDuration.toString() ~ " ago";
    }

    string lastUpdateClass() {
        if (lastUpdateDuration > Server.POLL_INTERVAL) {
            return "warning";
        }
        return "success";
    }

    Json toJson(bool includeBooking = true) {
        auto j = Json([
            "name": Json(server.name),
            "status": Json(statusName),
            "address": Json(server.status.address),
            "connect-string": Json(connectString),
        ]);

        if (includeBooking) j["booking"] = server.booking is null ? Json.undefined : booking.toJson;

        return j;
    }
}
