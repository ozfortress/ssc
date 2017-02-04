module config.env;

@property string env() {
    version(unittest) {
        version(development) static assert(0, "Only one environment at a time please");
        version(production) static assert(0, "Only one environment at a time please");

        return "testing";
    } else version(development) {
        version(production) static assert(0, "Only one environment at a time please");

        return "development";
    } else version(production) {
        return "production";
    } else {
        static assert(0, "No environment set");
    }
}
