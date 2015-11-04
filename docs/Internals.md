Internals
========

Backends
--------

### GCC ARM Embedded Backend

This backend builds bare metal compilers for ARM. It downloads the GCC
ARM Embedded toolchains sources from the `srcURL` specified in `config.json`.
It also downloads the prebuilt build tools from `nativeTools`. As these build
tools are for i686 machines, we replace the gcc directory in the build tools folder
with a `x86_64-linux-gnu` GDC native build. This also gives access to a gdc
compiler which will be necessary for DDMD. We then also have to rebuild
python for x86_64. nsis and installjammer work fine as 32bit binaries, so
we can keep those. For MinGW builds we also replace the `mingw-w64-gcc`
directory with a `x86_64-w64-mingw32` gdc build.

We then extract the toolchain sources. Before calling the standard GCC
ARM Embedded buildscript we apply `gdc.diff`. This is necessary to add
the `d` option to the languages configure argument. We also add `--disable-libphobos`
and `--disable-werror` flags using this patch. `--disable-werror` is
necessary as we build with a newer mingw GCC which generates more warnings
in binutils.

Note: unlike the original build scripts we do not build for i686 linux,
we build for x86_64 linux. This is caused by a limitation of the build
scripts which always build for the native machine arch.

### devkitPro Backend

This backend builds bare metal compilers based on [devkitpro.org][1]
build scripts. [DevkitPro][1] generates compilers for Nintendo GBA,
Nintendo DS, Nintendo 3DS, Nintendo Gamecube, Nintendo Wii, Nintendo WiiU
as well as Sony PSP. All these toolchains except for the PSP tooclhain are
supported by the GDC docker build container. The GCC version used in the
PSP toolchain is not supported by GDC. The build container builds an addon
which the toolchain user has to install in addition to the
devkitpro.org][1] base toolchains.


[1]: https://devkitpro.org/
