module models.booking;
import models;

import std.ascii;
import std.datetime;
import std.exception;

import vibe.d;
import base32;

import store;
import config.clients;

class Booking {
    static shared Store!(Booking, "id") store; // Initialized in package.d

    private static idFor(Client client, string user) {
        return client.name ~ ":" ~ user;
    }

    static @property auto all() {
        return store.all;
    }

    static auto bookingFor(Server server) {
        return store.findBy!"server"(server);
    }

    static auto find(Client client, string user) {
        return store.get(idFor(client, user));
    }

    static Booking create(Client client, string user, Duration duration) {
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

    Client client;
    string user;
    Server server;
    DateTime startedAt;
    DateTime endsAt;
    bool ended;

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

    private this(Client client, string user, Server server, DateTime endsAt) {
        this.client = client;
        this.user = user;
        this.server = server;
        this.endsAt = endsAt;
        this.startedAt = cast(DateTime)Clock.currTime();
        this.ended = false;
    }

    void start() {
        logInfo("Starting booking for %s for %s", id, duration);
        auto now = cast(DateTime)Clock.currTime();
        auto timeout = endsAt - now;
        endTimer = setTimer(timeout, &end, false);

        server.onBookingStart(this);
    }

    void end() {
        synchronized (this) {
            if (ended) return;
            ended = true;
        }
        logInfo("Ending booking for %s", id);

        server.onBookingEnd(this);

        Booking.store.remove(this);
    }

    void destroy() {
        synchronized (this) {
            ended = true;
        }
        Booking.store.remove(this);
    }
}
