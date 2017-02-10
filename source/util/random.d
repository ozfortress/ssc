module util.random;

import std.range;
import std.base64;
import std.random;
import std.algorithm;

string randomBase64(size_t length) {
    rndGen.seed(unpredictableSeed);
    auto bytes = rndGen.map!(a => cast(ubyte)a).take(length);

    return Base64URL.encode(bytes);
}
