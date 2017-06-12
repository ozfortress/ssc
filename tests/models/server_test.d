module models.server_test;
import unit_threaded;
import support.mock_server;

import core.thread;
import std.array;
import std.algorithm;

import models.server;

void sleep() {
    Thread.sleep(dur!("msecs")(100));
}

@("running") unittest {
    auto server = mockServer("running test");
    server.running.shouldBeFalse;
    server.spawn();
    server.running.shouldBeTrue;
    sleep();
    server.status.running.shouldBeTrue;

    server.kill();
    server.running.shouldBeFalse;
    server.status.running.shouldBeFalse;

    server.logs[].count("_STARTED").shouldEqual(1);
    server.logs[].count("_STOPPED").shouldEqual(0);
}

@("restart") unittest {
    auto server = mockServer("restart test");
    server.running.shouldBeFalse;

    server.restart();
    server.running.shouldBeTrue;
    sleep();
    server.status.running.shouldBeTrue;

    server.restart();
    server.running.shouldBeTrue;
    sleep();
    server.status.running.shouldBeTrue;

    server.restart();
    server.running.shouldBeTrue;
    sleep();
    server.status.running.shouldBeTrue;

    server.kill();
    server.running.shouldBeFalse;
    server.status.running.shouldBeFalse;

    server.logs[].count("_STARTED").shouldEqual(3);
    server.logs[].count("_STOPPED").shouldEqual(0);
}

@("crashed server") unittest {
    auto server = mockServer("crashed test server");
    server.spawn();
    sleep();

    server.sendCMD("quit");
    sleep();

    server.running.shouldBeFalse;
    server.status.running.shouldBeFalse;

    server.logs[].count("_STARTED").shouldEqual(1);
    server.logs[].count("_STOPPED").shouldEqual(1);
}
