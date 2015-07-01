Advanced Usage
========

Looking around in the container
-------------------------------

It's possible to start a shell in the container. Simply use this docker
command:

```bash
docker run -v ./shared-dir:/home/build/shared -i -t D-Programming-GDC/build-gdc /bin/bash
```

It's then possible to build toolchains by calling `build-gdc` in the shell.
The container has gdb and nano pre-installed to ease debugging. For more
information see the Internals documentation.

Building custom GDC code
------------------------
It's possible to use this container to build GDC code which is not available
in the official repository.

### Building a revision once
If you simply want to build a different revision once, first start a shell
in the container:

```bash
docker run -v ./shared-dir:/home/build/shared -i -t D-Programming-GDC/build-gdc /bin/bash
```

Then change the directory to the `GDC` or `build-gdc-config` folder
and add the remote repo:
```bash
cd GDC
git remote add jpf91 https://github.com/jpf91/GDC.git

cd ../build-gdc-config
git remote add jpf91 https://github.com/jpf91/build-gdc-config.git
```

The `build-gdc` tool always updates all repositories. So if you refer to a branch
in your build command you'll always get the latest revision on that branch.

Now simply call `build-gdc`:
```bash
build-gdc build --toolchain=x86_64-w64-mingw32/gcc-4.9/arm-gdcproject-linux-gnueabihf --config-revision=jpf91/master --revision=V4_9:jpf91/gdc-4.9
```

All changes in the docker container are transient. As soon as you `exit`
from the shell all changes made in the container are lost and you start
with a clean system again.

### Adding a repository for continuous building
If you want to build from one git repository repeatedly, the best way
is to create a derived docker container. Simply save this code to a file
called `Dockerfile` in an empty directory. Make sure to adjust your repositories:
```bash
FROM d-programming-gdc:build-gdc

RUN cd GDC \
    && git remote add jpf91 https://github.com/jpf91/GDC.git \
    && cd ../build-gdc-config \
    && git remote add jpf91 https://github.com/jpf91/build-gdc-config.git
```

Then cd into the directory and build the container:
```bash
docker build  -t jpf91/build-gdc .
```

You can now use your container by specifying `jpf91/build-gdc` instead
of `D-Programming-GDC/build-gdc`:
```bash
docker run -v ./shared-dir:/home/build/shared -t jpf91/build-gdc /usr/bin/build-gdc build --toolchain=x86_64-w64-mingw32/gcc-4.9/arm-gdcproject-linux-gnueabihf --revision=V4_9:jpf91/gdc-4.9
```

Note: we recommend to not use a `git fetch` command in the `Dockerfile`.
`build-gdc` updates all repositories before building, so it's not necessary.
If you use `git fetch` in the `Dockerfile` and rebase your branches
after the container has been built the `build-gdc` command might fail to update
the git repository.
