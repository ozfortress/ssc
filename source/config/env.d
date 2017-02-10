module config.env;

import std.conv;

enum Environment {
    testing,
    development,
    production,
}

@property Environment env() {
    version(unittest) {
        version(development) static assert(0, "Only one environment at a time please");
        version(production) static assert(0, "Only one environment at a time please");

        return Environment.testing;
    } else version(development) {
        version(production) static assert(0, "Only one environment at a time please");

        return Environment.development;
    } else version(production) {
        return Environment.production;
    } else {
        static assert(0, "No environment set");
    }
}

@property string envName() {
    return env.to!string;
}
