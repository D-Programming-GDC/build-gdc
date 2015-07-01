Cross-Compiler Basics
========

Machine terminology
-------------------
There are at most three kinds of machines involved when **building** cross
compilers:

- The _build_ system: The machine which **generates the compiler** binaries.
- The _host_ system: The system which **runs the compiler** binaries.
- The _target_ system: The system which **runs the application code** compiled
  by the compiler binaries.

The _build_ system is generally not involved when **using** the cross-compiler
binaries.

Machine triplets
----------------
GNU tools describe the _build_, _host_ and _target_ machines using
triplets. This is a textual representation in the form arch-vendor-kernel-system.

- Arch describes the architecture (i586, i686, x86_64, arm, armhf).
- Vendor is free-form text and has usually no special meaning (unknown, gdcproject).
- Kernel describes part 1 of the OS (pc, w64, linux).
- System describes part 2 of the OS (gnu, gnueabi, androideabi, mingw32).

Sometimes Kernel and System are replaced by a single value. Some examples of valid
triplets:

- x86_64-unknown-linux 
- x86_64-unknown-linux-gnu 
- x86_64-gdcproject-linux-gnu
- arm-unknown-linux-gnueabi
- arm-unknown-linux-androideabi
- x86_64-w64-mingw32
- x86_64-pc-mingw32

Compiler types
--------------
Some combinations of _build_, _host_ and _target_ systems have special names:

- **native** compiler: A compiler where _target_ is the same system as _host_.
- **cross** compiler: A compiler where _target_ is not the same system as _host_.
- **cross-native** compiler: A native compiler where _build_ is not the same as _host_.
- **canadian-cross** compiler: A cross compiler where _build_ is not the same as _host_.

Here are some examples:

- **native**: build=x86_64-unknown-linux, host=x86_64-unknown-linux, target=x86_64-unknown-linux
  The compiler was built on **x86_64-unknown-linux**, runs on **x86_64-unknown-linux**
  and generates output for **x86_64-unknown-linux**.
- cross-compiler: build=x86_64-unknown-linux, host=x86_64-unknown-linux, target=arm-unknown-linux-gnueabi
  The compiler was built on **x86_64-unknown-linux**, runs on **x86_64-unknown-linux**
  but generates output for **arm-unknown-linux-gnueabi**.
- cross-native: build=x86_64-unknown-linux, host=arm-unknown-linux-gnueabi, target=arm-unknown-linux-gnueabi
  The compiler was built on **x86_64-unknown-linux** but runs on **arm-unknown-linux-gnueabi**
  and generates output for **arm-unknown-linux-gnueabi**.
- canadian-cross: build=x86_64-unknown-linux, host=x86_64-w64-mingw32, target=arm-unknown-linux-gnueabi
  The compiler was built on **x86_64-unknown-linux** but runs on **x86_64-w64-mingw32** and
  generates output for **arm-unknown-linux-gnueabi**.

Note: When **using** cross-compilers the _build_ system doesn't matter
and **cross-native** compilers behave in the same way as **native** compilers.
This also applies to **canadian-cross** and **cross** compilers.

Additional information is available in the [crosstool-NG documentation][1].

[1]: https://github.com/crosstool-ng/crosstool-ng/blob/master/docs/6%20-%20Toolchain%20types.txt
