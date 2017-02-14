module models.booking;
import models;

import std.ascii;
import std.datetime;
import std.exception;

import vibe.d;
import base32;

import store;

class Booking {
    package static shared Store!(Booking, "id") store; // Initialized in package.d

    private static idFor(string client, string user) {
        return client ~ ":" ~ user;
    }

    static @property auto all() {
        return store.all;
    }

    static auto bookingFor(Server server) {
        return store.findBy!"server"(server);
    }

    static auto find(string client, string user) {
        return store.get(idFor(client, user));
    }

    static Booking create(string client, string user, Duration duration) {
        if (store.exists(idFor(client, user))) {
            throw new StoreException("Booking already exists");
        }

        auto servers = Server.allAvailable;
        enforce(!servers.empty, "No server available");
        auto server = servers.front;
        enforce(server.running); // Sanity

        auto endsAt = cast(DateTime)Clock.currTime() + duration;
        auto booking = new Booking(client, user, server, endsAt);
        store.add(booking);

        // Start the booking after successful store
        booking.start();
        return booking;
    }

    string client;
    string user;
    Server server;
    DateTime startedAt;
    DateTime endsAt;

    private Timer endTimer;

    @property auto id() const {
        return idFor(client, user);
    }

    @property auto duration() {
        return endsAt - startedAt;
    }

    /// Returns user base32 encoded in lower-case
    @property auto userEscaped() {
        return Base32.encode(cast(ubyte[])user).toLower;
    }

    private this(string client, string user, Server server, DateTime endsAt) {
        this.client = client;
        this.user = user;
        this.server = server;
        this.endsAt = endsAt;
        this.startedAt = cast(DateTime)Clock.currTime();
    }

    void start() {
        logInfo("Starting booking for %s", id);
        auto now = cast(DateTime)Clock.currTime();
        auto timeout = endsAt - now;
        endTimer = setTimer(timeout, &end, false);

        server.onBookingStart(this);
    }

    void end() {
        logInfo("Ending booking for %s", id);
        server.onBookingEnd(this);

        Booking.store.remove(this);
    }
}
