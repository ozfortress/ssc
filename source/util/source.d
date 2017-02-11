module util.source;

import std.array;
import std.string;
import std.algorithm;

string formatCommand(string command, string[] args...) {
    if (args.empty) return command;
    return `%s %s`.format(command, args.map!formatArgument.join(" "));
}

string formatArgument(string argument) {
    return `"%s"`.format(escapeArgument(argument));
}

string escapeArgument(string argument) {
    return argument.replace(`\`, `\\`)
                   .replace(`"`, `\"`);
}
