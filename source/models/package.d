module models;

public {
    import models.server;
    import models.server_status;
    import models.booking;
}

shared static this() {
    Server.store = new shared typeof(Server.store);
    Booking.store = new shared typeof(Booking.store);
}
