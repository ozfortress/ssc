module util.random_test;
import unit_threaded;

import std.algorithm;

import util.random;

@("Uniqueness") @system unittest {
    auto strs = [
        randomBase64(12),
        randomBase64(12),
        randomBase64(12),
        randomBase64(12),
        randomBase64(12),
        randomBase64(12),
        randomBase64(12),
        randomBase64(12),
        randomBase64(12),
    ];

    foreach (str; strs) {
        auto count = strs.count(str);
        count.shouldEqual(1);
    }
}
