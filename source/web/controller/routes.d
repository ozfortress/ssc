module web.controller.routes;
import web.controller;

import web.controller.controller;
import web.controller.servers;
import web.controller.bookings;

static auto router() {
    auto router = new URLRouter();

    router.registerWebInterface(new ControllerInterface);
    router.registerWebInterface(new ServersInterface);
    router.registerWebInterface(new BookingsInterface);

    return router;
}


