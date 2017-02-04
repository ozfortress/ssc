module util.json;

public import std.json;
public import jsonizer;

import std.file;

void merge(JSONValue self, JSONValue other) {
    if (self.type is JSON_TYPE.OBJECT) {
        foreach (string key, value; other) {
            if (key !in self) {
                self[key] = value;
            } else {
                self[key].merge(value);
            }
        }
    }
}

auto readJSON(string path) {
    return parseJSON(readText(path));
}
