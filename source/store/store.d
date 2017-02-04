module store.store;

import core.sync.rwmutex;
import std.meta;
import std.range;
import std.array;
import std.container;
import std.algorithm;
import std.exception;

/**
 * Simple generic query-able in-memory store.
 * Uses RBTree internally.
 */
shared class Store(Element, string primaryField = "") {
    private {
        struct KVPair {
            Primary key;
            Element value;
        }

        alias Primary = typeof(mixin("Element."~primaryField));
        alias Container = RedBlackTree!(KVPair, "a.key < b.key");

        ReadWriteMutex _mutex;
        Container container;
    }

    this() {
        _mutex = cast(shared)new ReadWriteMutex;
        container = cast(shared)new Container();
    }

    @property Element[] all() {
        synchronized (mutex.reader) {
            return syncContainer[].map!(e => e.value).array;
        }
    }

    private @property auto syncContainer() {
        return cast(Container)container;
    }

    @property auto mutex() {
        return cast(ReadWriteMutex)_mutex;
    }

    Element findBy(fields...)(FieldTypes!fields values) {
        synchronized (mutex.reader) {
            foreach (element; syncContainer) {
                if (matchFields!fields(values, element.value)) {
                    return element.value;
                }
            }
        }
        return null;
    }

    Element[] getBy(fields...)(FieldTypes!fields values) {
        Element[] result = [];
        synchronized (mutex.reader) {
            foreach (element; syncContainer) {
                if (matchFields!fields(values, element.value)) {
                    result ~= element.value;
                }
            }
        }
        return result;
    }

    void add(Element element) {
        synchronized (mutex.writer) {
            auto entry = KVPair(primary(element), element);
            auto range = syncContainer.equalRange(entry);
            enforce(range.empty || range.front.value is null, "Primary key conflict");
            syncContainer.insert(entry);
        }
    }

    void remove(Element element) {
        remove(primary(element));
    }

    void remove(Primary key) {
        synchronized (mutex.writer) {
            auto value = KVPair(key, null);
            auto range = syncContainer.equalRange(value).take(1);
            syncContainer.remove(range);
        }
    }

    Element get(Primary key) {
        synchronized (mutex.reader) {
            auto value = KVPair(key, null);
            auto range = syncContainer.equalRange(value);
            if (range.empty) return null;
            return range.front.value;
        }
    }

    bool exists(Primary key) {
        return get(key) !is null;
    }

    private bool matchFields(fields...)(FieldTypes!fields values, Element element) {
        foreach (index, field; fields) {
            auto value = mixin("element."~field);

            if (value != values[index]) return false;
        }
        return true;
    }

    private Primary primary(Element element) {
        return mixin("element."~primaryField);
    }

    private template FieldType(string field) {
        alias FieldType = typeof(mixin("Element."~field));
    }

    private template FieldTypes(fields...) {
        alias FieldTypes = staticMap!(FieldType, fields);
    }
}
