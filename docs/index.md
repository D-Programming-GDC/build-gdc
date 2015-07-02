GDC compiler build infrastructure
========

This project provides tools used to build the official GDC compiler
binaries for [gdcproject.org][1].

Building all kinds of compilers is done in a single, reproducable
[docker][3] environment. Build-gdc outputs tar.xz or 7z archives in
the same format as used by [gdcproject.org][1]. It optionally allows
generating the json based download list used by the [gdcproject.org][1]
downloads webpage.



Features
--------

Hosts:
- Windows
- Linux

Architectures:
- x86
- x86_64
- arm
- armhf

Compiler types:
- native
- cross-native
- cross
- canadian-cross

Backends:
- [crosstool-NG][2]

Contribute
----------
- Issue Tracker: http://bugzilla.gdcproject.org/
- Source Code: https://github.com/D-Programming-GDC/build-gdc

Support
-------
If you are having issues, please let us know.
We have a forum located at: http://forum.dlang.org/group/gdc

License
-------

The project is licensed under the Boost license.



[1]: https://www.gdcproject.org/downloads/
[2]: https://github.com/crosstool-ng/crosstool-ng
[3]: https://docker.io/
