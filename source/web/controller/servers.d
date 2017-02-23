module web.controller.servers;
import web.controller;

import models;

@path("/controller/servers/:server")
class ServersInterface {
    mixin WebInterface;

    Server server;

    protected void requireServer(scope HTTPServerRequest req) {
        server = Server.get(req.params["server"]);
        enforceHTTP(server !is null, HTTPStatus.notFound);
    }

    @path("")
    void getShow(scope HTTPServerRequest req) {
        requireAuthentication(req);
        requireServer(req);

        render!("controller/servers/show.dt", server, key);
    }

    void getLogs(scope HTTPServerRequest req) {
        requireAuthentication(req);
        requireServer(req);

        synchronized (server) {
            enforceHTTP(!server.logs.empty, HTTPStatus.noContent);
            auto logs = server.logs[];
            render!("controller/servers/logs.dt", logs, key);
        }
    }

    void getStatus(scope HTTPServerRequest req) {
        requireAuthentication(req);
        requireServer(req);

        render!("controller/servers/status.dt", server, key);
    }

    void postCommand(scope HTTPServerRequest req, string command) {
        requireAuthentication(req);
        requireServer(req);
        server.sendCMD(command);

        emptyResponse;
    }

    void postRestart(scope HTTPServerRequest req) {
        requireAuthentication(req);
        requireServer(req);
        server.restart();

        emptyResponse;
    }

    void postStop(scope HTTPServerRequest req) {
        requireAuthentication(req);
        requireServer(req);
        server.kill();

        emptyResponse;
    }

    void postDirty(scope HTTPServerRequest req) {
        requireAuthentication(req);
        requireServer(req);
        server.makeDirty();

        emptyResponse;
    }

    void postTogglePolling(scope HTTPServerRequest req) {
        requireAuthentication(req);
        requireServer(req);
        server.pollingEnabled = !server.pollingEnabled;

        emptyResponse;
    }
}
