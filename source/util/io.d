module util.io;

import core.sys.posix.fcntl;
import core.sys.posix.unistd;
import core.stdc.errno;
import std.stdio;
import std.regex;

/**
 * Marks the file as non-blocking (O_NONBLOCK)
 * After call, only `readlnNoBlock` should be used on this file (for reading)
 */
void markNonBlocking(File file) {
    auto flags = fcntl(file.fileno, F_GETFL);
    fcntl(file.fileno, F_SETFL, O_NONBLOCK | flags);
}

/**
 * Naive readln using non-blocking functions.
 */
string readlnNoBlock(File file) {
    char[] buffer = [];
    char character;

    auto result = read(file.fileno, &character, 1);
    if (result < 1) return null;
    buffer ~= character;

    while (true) {
        result = read(file.fileno, &character, 1);
        if (result == EAGAIN) continue;
        if (result < 1) break;
        if (character == '\n') break;
        buffer ~= character;
    }

    return cast(string)buffer;
}
