module web.controller;

public {
    import vibe.d;
    import vibe.web.web;
}

mixin template WebInterface() {
    static import config.keys;
    string key;
    string client;

    private void requireAuthentication(scope HTTPServerRequest req) {
        enforceHTTP("key" in req.query, HTTPStatus.forbidden, "Invalid key");
        key = req.query["key"];
        client = config.keys.authenticate(key);
        enforceHTTP(client !is null, HTTPStatus.forbidden, "Invalid key");
    }

    private void emptyResponse() {
        enforceHTTP(false, HTTPStatus.noContent);
    }
}
