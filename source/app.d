import vibe.d;

static import models;
static import web.routes;
static import config.clients;
static import config.application;

version (unittest) {} else
shared static this() {
    // Initialize configs
    config.clients.init();
    config.application.init();


	auto settings = config.application.serverSettings;

    // Log access to the log file
    //settings.accessLogToConsole = true;
    settings.accessLogFile = config.application.accessLogFile;

    // Log to the proper log file
    auto fileLogger = cast(shared)new FileLogger(config.application.logFile);
    fileLogger.minLevel = config.application.logLevel;
    registerLogger(fileLogger);

    // Better log formatting
    setLogFormat(FileLogger.Format.thread, FileLogger.Format.thread);

    // Reload servers
    models.Server.reload();

	listenHTTP(settings, web.routes.router);
	logInfo("See status at http://127.0.0.1:%s/status".format(settings.port));
}
