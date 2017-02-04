module store_test;
import unit_threaded;

import std.datetime;
import std.algorithm;

import store;

class Storeable {
    int id;
    string stringField;
    int intField;
    DateTime dateTimeField;

    this(string s, int i, DateTime d) {
        static idinc = 0;
        id = idinc++;
        stringField = s;
        intField = i;
        dateTimeField = d;
    }
}

@("primary stringField add find store remove") unittest {
    auto store = new shared Store!(Storeable, "stringField");

    auto element1 = new Storeable("foo", 2, DateTime(2017, 1, 1));
    store.add(element1);

    store.all.shouldEqual([element1]);
    store.findBy!"stringField"("foo").shouldEqual(element1);
    store.findBy!"stringField"("bar").shouldBeNull;

    auto element2 = new Storeable("bar", 42, DateTime(2017, 1, 1));
    store.add(element2);

    store.all.shouldEqual([element2, element1]);
    store.findBy!"stringField"("foo").shouldEqual(element1);
    store.findBy!"stringField"("bar").shouldEqual(element2);
    store.findBy!"stringField"("bizz").shouldBeNull;

    store.remove(element1);

    store.all.shouldEqual([element2]);
    store.findBy!"stringField"("foo").shouldBeNull;
    store.findBy!"stringField"("bar").shouldEqual(element2);
    store.findBy!"stringField"("bizz").shouldBeNull;
}

@("getBy") unittest {
    auto store = new shared Store!(Storeable, "id");

    store.add(new Storeable("s1", 1, DateTime(2017, 1, 1)));
    store.add(new Storeable("s2", 2, DateTime(2017, 1, 2)));
    store.add(new Storeable("s3", 1, DateTime(2017, 1, 3)));
    store.add(new Storeable("s1", 2, DateTime(2017, 1, 4)));
    store.add(new Storeable("s2", 1, DateTime(2017, 1, 5)));
    store.add(new Storeable("s3", 2, DateTime(2017, 1, 6)));

    store.all.length.shouldEqual(6);
    store.getBy!"stringField"("s1").length.shouldEqual(2);
    store.getBy!"stringField"("s2").length.shouldEqual(2);
    store.getBy!"stringField"("s3").length.shouldEqual(2);
    store.getBy!"intField"(1).length.shouldEqual(3);
    store.getBy!"intField"(2).length.shouldEqual(3);
    store.getBy!"dateTimeField"(DateTime(2017, 1, 1)).length.shouldEqual(1);
    store.getBy!"dateTimeField"(DateTime(2017, 1, 2)).length.shouldEqual(1);
    store.getBy!"dateTimeField"(DateTime(2017, 1, 3)).length.shouldEqual(1);
    store.getBy!"dateTimeField"(DateTime(2017, 1, 4)).length.shouldEqual(1);
    store.getBy!"dateTimeField"(DateTime(2017, 1, 5)).length.shouldEqual(1);
    store.getBy!"dateTimeField"(DateTime(2017, 1, 6)).length.shouldEqual(1);

    store.getBy!("stringField", "intField")("s1", 2).length.shouldEqual(1);
    store.getBy!("stringField", "intField", "dateTimeField")("s2", 2, DateTime(2017, 1, 5)).length.shouldEqual(0);
}

@("findBy") unittest {
    auto store = new shared Store!(Storeable, "id");

    store.add(new Storeable("s1", 1, DateTime(2017, 1, 1)));
    store.add(new Storeable("s2", 2, DateTime(2017, 1, 2)));
    store.add(new Storeable("s3", 1, DateTime(2017, 1, 3)));
    store.add(new Storeable("s1", 2, DateTime(2017, 1, 4)));
    store.add(new Storeable("s2", 1, DateTime(2017, 1, 5)));
    store.add(new Storeable("s3", 2, DateTime(2017, 1, 6)));

    store.findBy!"stringField"("s1").shouldNotBeNull;
    store.findBy!"stringField"("s2").shouldNotBeNull;
    store.findBy!"stringField"("s3").shouldNotBeNull;
    store.findBy!"stringField"("s4").shouldBeNull;
}

@("get") unittest {
    auto store = new shared Store!(Storeable, "stringField");

    auto element = new Storeable("foo", 2, DateTime(2017, 1, 1));
    store.add(element);

    store.get("foo").shouldEqual(element);
    store.get("bar").shouldBeNull;
}
