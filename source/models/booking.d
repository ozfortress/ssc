module models.booking;
import models;

import std.datetime;
import std.exception;

import store;

class Booking {
    shared static this() {
        store = new typeof(store);
    }
    private static shared Store!(Booking, "id") store;

    static @property auto all() {
        return store.all;
    }

    static auto bookingFor(Server server) {
        return store.findBy!"server"(server);
    }

    static Booking create(string client, string user, DateTime endsAt) {
        auto servers = Server.available;
        enforce(!servers.empty, "No server available");
        auto server = servers.front;

        auto booking = new Booking(client, user, server, endsAt);
        enforce(store.findBy!"id"(booking.id) is null, "Duplicate booking");
        store.add(booking);
        return booking;
    }

    string client;
    string user;
    Server server;
    DateTime startedAt;
    DateTime endsAt;

    @property auto id() const {
        return client ~ ":" ~ user;
    }

    @property auto duration() {
        return endsAt - startedAt;
    }

    private this(string client, string user, Server server, DateTime endsAt) {
        this.client = client;
        this.user = user;
        this.server = server;
        this.endsAt = endsAt;
        this.startedAt = cast(DateTime)Clock.currTime();
    }

    void end() {
        Booking.store.remove(this);
    }


}

/*private static void update() {
    synchronized(bookingsMutex) {
        auto bookings = cast(DList!Booking)_bookings;
        auto now = cast(DateTime)Clock.currTime();

        while (now > bookings.front.endsAt) {
            auto booking = bookings.front;
            bookings.removeFront();
            endBooking(booking);
        }
    }
}*/
