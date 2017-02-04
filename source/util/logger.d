module util.logger;

import vibe.d;

class SSCLogger : Logger {
    private {
        Logger[] subloggers = [];
    }

    this(Logger[] subloggers...) {
        this.subloggers = subloggers;
    }
}
