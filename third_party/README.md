# Android execution components

PRoot is a separate GPL-2.0-or-later executable, not linked into Flutter.
`proot/` comes from oonid/pr commit
`d50675bf59d81ca6429dc93077bc82f9313c6521` (src/proot), including its
Android loader, seccomp and subprocess compatibility changes. Its source and
COPYING are distributed here. DevCat's `DEVCAT_NATIVE_ONLY` build switch disables
cross-bitness loaders: each Android ABI has its own native guest environment.
The tracer also sets `PTRACE_O_EXITKILL`, so stopping it terminates traced child
processes, including compiler subprocesses. The corresponding change is in
`src/tracee/event.c`.

`talloc/` is talloc 2.4.3 (LGPL-3.0-or-later), downloaded from
https://download.samba.org/pub/talloc/talloc-2.4.3.tar.gz. The build uses the
standalone replacement header supplied with the PRoot fork.

Build instructions: `scripts/build_android_proot.sh NDK_PATH ABI OUTPUT_DIRECTORY`.
Android NDK r28c, API 24, static executables with 16 KiB ELF segment alignment.
Runtime root filesystem package inventories and licenses are generated separately.
