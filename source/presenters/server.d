module presenters.server;

import std.string;
import std.datetime;

import models;

struct ServerPresenter {
    Server server;
    alias server this;

    this(Server server) {
        this.server = server;
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
}
