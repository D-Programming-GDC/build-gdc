Getting started
========

Installing docker
-----------------

Follow the installation instructions for Docker Engine as described on
[docs.docker.com][1].


If you're on linux and using the devicemapper backend docker containers
will have a storage limit of 10GB. This might be too low for some toolchain
configurations. Setup dm.basesize as described [here][2].



Basic build instructions
---------------------------

### Introduction

The base command to build toolchains is
```bash
docker run -v /path/to/shared-dir:/home/build/shared -t D-Programming-GDC/build-gdc /usr/bin/build-gdc --help
```

* `/path/to/shared-dir` is the full path to a local directory. The gdc-build container will store
the final toolchain archives in this folder. It's also used to cache source code
archives between builds. This directory can be empty.
* `-t D-Programming-GDC/build-gdc` specifies that we want to run the
gdc-build container. Docker will automatically download the container if
it's not already cached.
* `/usr/bin/build-gdc` is the build script which is run inside the docker container.
It currently supports two commands: `build` and `update-website`.

### Build example

To build the GCC-4.9 toolchain with target=arm-gdcproject-linux-gnueabihf
and host=x86_64-w64-mingw32 (running on Windows 64bit X86, generating code
for ARM linux, hardfloat variant) use the build command:

```bash
docker run -v /path/to/shared-dir:/home/build/shared -t D-Programming-GDC/build-gdc /usr/bin/build-gdc build --toolchain=x86_64-w64-mingw32/gcc-4.9/arm-gdcproject-linux-gnueabihf
```

The value passed to `--toolchain` is the relative path of the toolchain configuration.
All toolchain configurations can be browsed at [github][3].

### Building multiple toolchains at once

It's possible to build multiple toolchains at once by using multiple `--toolchain`
arguments. build-gdc will avoid rebuilding dependencies.

```bash
docker run -v /path/to/shared-dir:/home/build/shared -t D-Programming-GDC/build-gdc /usr/bin/build-gdc build --toolchain=x86_64-w64-mingw32/gcc-4.9/arm-gdcproject-linux-gnueabihf  --toolchain=x86_64-linux-gnu/gcc-4.9/arm-gdcproject-linux-gnueabihf
```

### Additional options

The `build` command accepts some more options:

* `--verbose` Emit debug output.
* `--update-db` Update the database of successful builds for [gdcproject.org][4]



Building a specific GDC revision
--------------------------------
By default the build-gdc tool always builds the lastest GDC revision in the corresponding
branch. To build a specific revision, use the `--revision` switch. As it's possible to
build different GCC versions at the same time we need a way to specify one revision
per GCC version:
```bash
docker run -v /path/to/shared-dir:/home/build/shared -t D-Programming-GDC/build-gdc /usr/bin/build-gdc build --toolchain=x86_64-w64-mingw32/gcc-4.9/arm-gdcproject-linux-gnueabihf --revision=V4_9:f378f9ab41 --revision=V5:abcdef --revision=snapshot:ascdfe
```

The part after `:` will be passed directly to git checkout. Because of that it's
also possible to specify tags or branches:
```bash
docker run -v /path/to/shared-dir:/home/build/shared -t D-Programming-GDC/build-gdc /usr/bin/build-gdc build --toolchain=x86_64-w64-mingw32/gcc-4.9/arm-gdcproject-linux-gnueabihf --revision=V4_9:origin/some-v9-branch --revision=V5:origin/v2.066.1_gcc5
```

### Specifying build-gdc-config revision
build-gdc also uses the latest version of the configuration files by default.
It's possible to specify a different revision by using `--config-revision`.

```bash
docker run -v /path/to/shared-dir:/home/build/shared -t D-Programming-GDC/build-gdc /usr/bin/build-gdc build --toolchain=x86_64-w64-mingw32/gcc-4.9/arm-gdcproject-linux-gnueabihf --config-revision=abbcccde
```

Building a list of toolchains
-----------------------------

Instead of using many `--toolchain=` arguments it's also possible
to supply a JSON file listing all toolchains. An example JSON file could
look like this:
```json
[
    "arm-linux-gnueabi/gcc-4.9/arm-linux-gnueabi",
    "arm-linux-gnueabihf/gcc-4.9/arm-linux-gnueabihf",
    "i686-linux-gnu/gcc-4.9/arm-gdcproject-linux-gnueabi"
]
```

Use the `--toolchain-list` argument to specify the path to the json file:
```bash
docker run -v /path/to/shared-dir:/home/build/shared -t D-Programming-GDC/build-gdc /usr/bin/build-gdc build --toolchain-list=/home/build/shared/arm.json
```

Note: The json file must be in `/path/to/shared-dir` and the path must be adjusted as shown in the example.

There are some predefined lists in the [build-gdc-config repository][5].
These can be used by simply passing the filename to `--toolchain-list`:
```bash
docker run -v /path/to/shared-dir:/home/build/shared -t D-Programming-GDC/build-gdc /usr/bin/build-gdc build --toolchain-list=all-gcc5
```

[1]: http://docs.docker.com/index.html
[2]: https://github.com/docker/docker/blob/master/daemon/graphdriver/devmapper/README.md
[3]: https://github.com/D-Programming-GDC/build-gdc-config/tree/master/configs
[4]: http://gdcproject.org/downloads
[5]: https://github.com/D-Programming-GDC/build-gdc-config/tree/master/lists
