module support.mock_server;

import models.server;

Server mockServer(string name) {
    auto server = new Server;
    server.name = name;
    server.executable = "tests/support/mock_source_server.py";
    server.logLength = 0;
    return server;
}
