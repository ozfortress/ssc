# SSC (Source Server Controller)

A web application that manages source servers.
Also has optional support for server booking.
Developed using [D](https://dlang.org/) and [vibe.d](https://vibed.org/).

Only tested with tf2 servers.

## Dependencies

Requires [D](https://dlang.org/) and [dub](http://code.dlang.org/getting_started) for fetching/building dependencies.

Other Dependencies:
- [expect](http://expect.sourceforge.net/) for running the servers.

Optional Dependencies:
- [steamcmd](https://developer.valvesoftware.com/wiki/SteamCMD) for downloading and updating source servers.

## Building

SSC has 3 build paths: development, test and production

### Development

To Build and Run:

```bash
dub
# or
dub run
```

Built executable can be found in `bin/ssc`.

### Test

To build and run tests you will also need:
* python 3.5+
* pyparsing
* py.test (optional)

`tests/support` contains a mock implementation of a source server written in
python which is used in some tests to avoid running/installing a source
dedicated server.

Run the following to test SSC:

```bash
dub test
```

Run the following to test the source server mock:

```bash
py.test tests/support/*
```

### Production

To Build:

```bash
dub -c production
```

Executable can be found in `bin/ssc`.
