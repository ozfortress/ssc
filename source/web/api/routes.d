module web.api.routes;

import vibe.d;

static auto router() {
    auto router = new URLRouter("/api");

    router.any("/v1/*", v1_router());

    return router;
}

static auto v1_router() {
    auto router = new URLRouter("/api/v1");

    return router;
}
