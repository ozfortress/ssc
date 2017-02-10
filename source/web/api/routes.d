module web.api.routes;

import vibe.d;

import web.api.v1;

static auto router() {
    auto router = new URLRouter();

    router.any("/api/v1/*", v1Router());

    return router;
}

static auto v1Router() {
    auto router = new URLRouter();

    router.registerRestInterface(new SSCV1APIImpl());

    return router;
}
