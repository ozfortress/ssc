module web.controller;

public {
    import vibe.d;
    import vibe.web.web;
}

mixin template WebInterface() {
    static import config.keys;
    string key;
    string client;

    private void requireAuthentication(scope HTTPServerRequest req, scope HTTPServerResponse res) {
        performBasicAuth(req, res, "all", (string username, string password) {
            if (username != "") return false;
            key = password;
            client = config.keys.authenticate(key);
            return client !is null;
        });
    }

    private void emptyResponse() {
        enforceHTTP(false, HTTPStatus.noContent);
    }
}
