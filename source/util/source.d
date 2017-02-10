module util.source;

import std.array;
import std.string;
import std.algorithm;

string formatCommand(string command, string[] args...) {
    return command.format(args.map!formatArgument.array);
}

string formatArgument(string argument) {
    return `"%s"`.format(escapeArgument(argument));
}

string escapeArgument(string argument) {
    return argument.replace(`\`, `\\`)
                   .replace(`"`, `\"`);
}
