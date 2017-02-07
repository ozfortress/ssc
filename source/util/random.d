module util.random;

import std.range;
import std.base64;
import std.random;
import std.algorithm;

string randomBase64(size_t length) {
    auto bytes = rndGen().map!(a => cast(ubyte)a).take(length);

    return Base64.encode(bytes);
}
