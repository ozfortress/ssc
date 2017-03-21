module web.routes;

import vibe.d;

static import web.api.routes;
static import web.controller.routes;

static auto router() {
    auto router = new URLRouter();

    router.get("/status", &status);

    router.any("/api/*", web.api.routes.router);
    router.any("/*", web.controller.routes.router);

    // Serve static files
    auto fsettings = new HTTPFileServerSettings;
    fsettings.serverPathPrefix = "/static";
    router.get("*", serveStaticFiles("public/", fsettings));

    return router;
}

void status(HTTPServerRequest req, HTTPServerResponse res) {
    res.writeBody("Running\n");
}
