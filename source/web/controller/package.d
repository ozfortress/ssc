module web.controller;

public {
    import vibe.d;
    import vibe.web.web;
}

mixin template WebInterface() {
    import config.clients : authenticate, Client;
    Client client;

    private void requireAuthentication(scope HTTPServerRequest req, scope HTTPServerResponse res) {
        performBasicAuth(req, res, "all", (string username, string password) {
            if (username != "") return false;

            auto client = authenticate(password);
            if (client.isNull) return false;

            this.client = client.get;
            return this.client.isAdmin;
        });
    }

    private void emptyResponse() {
        enforceHTTP(false, HTTPStatus.noContent);
    }
}
