module supervisor.poller;

import core.time;
import std.stdio;
import std.array;
import std.range;
import std.typecons;
import std.algorithm;

bool pollReadable(int fd, Duration timeout) {
    auto result = poll([fd], [], timeout);
    return result[0].length == 1;
}

bool pollWriteable(int fd, Duration timeout) {
    auto result = poll([], [fd], timeout);
    return result[1].length == 1;
}

version (Posix) {
    import core.sys.posix.sys.select;
    import core.stdc.errno;

    alias poll = select_poll;

    Tuple!(int[], int[]) select_poll(int[] readables, int[] writeables, Duration timeout) {
        fd_set readset;
        readables.each!(fd => FD_SET(fd, &readset));

        fd_set writeset;
        writeables.each!(fd => FD_SET(fd, &writeset));

        int maxfd = reduce!max(0, readables.chain(writeables)) + 1;

        auto time = timeout.toTimeval;

        auto result = select(maxfd, &readset, &writeset, null, &time);

        if (result == -1) {
            if (errno == EBADF) throw new Exception("Invalid fd");
            if (errno == EINVAL) throw new Exception("Invalid Value");
            if (errno == ENOMEM) throw new Exception("Memory Error");
        }

        return tuple(readables.filter!(fd => FD_ISSET(fd, &readset)).array,
                     writeables.filter!(fd => FD_ISSET(fd, &writeset)).array);
    }

    private timeval toTimeval(Duration dur) {
        auto splits = dur.split!("seconds", "usecs");
        return timeval(splits.seconds, splits.usecs);
    }
}
// TODO: Support for other operating systems
