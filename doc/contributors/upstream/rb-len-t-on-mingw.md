<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Ruby 4.1's `rb_len_t` on MinGW: what Tokra would send upstream

This folder holds what Tokra would send upstream: for each change, the
pull-request text as a Markdown file and beside it a `.patch` an upstream
maintainer could accept as it stands. Nothing here has been filed;
whether and when to file is the maintainer's to say. The maintainer
decided on 2026-11-21 that Tokra moves to Ruby 4.1 on Windows without
waiting for upstream, carrying a patched magnus meanwhile and no fork;
Plan 071 says how.

Two changes, one in each project, lift the fault:

- `magnus-rb-len-t.md` and `.patch`: magnus passes lengths and indices as
  `rb_len_t`, so it compiles where Ruby's lengths are wider than `long`.
- `rb-sys-rbconfig-env-on-windows.md` and `.patch`: rb_sys's Makefile no
  longer hands the build script an empty `CPPFLAGS` on Windows, so
  bindgen sees `-DSIZEOF_RB_LEN_T=8` under `gem install` too.

## What is established, and how

- **Ruby 4.1 adds `rb_len_t`** (Feature #22400, ruby/ruby 03e3376643,
  2026-10-09, in 4.1.0-preview1 and in RubyInstaller's head build of
  2026-11-10). It is `int64_t` when `SIZEOF_RB_LEN_T` is defined wider
  than `long`, and `long` otherwise (`include/ruby/internal/value.h`).
  Read in ruby/ruby's source.
- **RubyInstaller's head build defines it in `CPPFLAGS`, not in
  `config.h`.** On that build `RbConfig::CONFIG["CPPFLAGS"]` is
  `" -DSIZEOF_RB_LEN_T=8 -D_WIN32_WINNT=0x0600 -D__MINGW_USE_VC2005_COMPAT -D_FILE_OFFSET_BITS=64 "`,
  `cppflags` is empty, and `config.h` defines `SIZEOF_LONG 4` and no
  `SIZEOF_RB_LEN_T` (rubyinstaller2-packages,
  `mingw-w64-ruby-head/PKGBUILD`, line 62). Seen on the Windows build
  machine.
- **Under plain cargo, bindgen sees the define**, binds `rb_len_t` as
  `i64`, and magnus does not compile: on main at a73a3cc, 37 errors at
  its `as c_long` casts. 0.9.3 and 0.9.4 cast the same way.
- **Under rb_sys's Makefile, bindgen sees no `CPPFLAGS` at all.** The
  Makefile exports `RBCONFIG_CPPFLAGS` with the flags and then an empty
  `RBCONFIG_cppflags`; Windows' variable names ignore case, and the
  build script receives `RBCONFIG_CPPFLAGS` empty (its
  `RB_SYS_DEBUG_BUILD` dump), so it binds `rb_len_t` as `c_long`, 32
  bits. Every magnus gem built by `gem install` on that Ruby compiles,
  and passes lengths and indices of the wrong width.
- **The stable API's C fallback is compiled without `CPPFLAGS`** on
  either path (rb-sys-build `src/cc.rs`). It returns `long`, and the
  structs it reads lay out the same either way, so this is noted in the
  rb-sys text and not changed.

## What a mistyped binding does

A length passed as 32 bits where Ruby reads 64 relies on the upper half
of the register, which the Windows x64 calling convention leaves
undefined, and `rb_range_beg_len` writes its two 64-bit results into
32-bit locals, overwriting what lies beside them. A negative index
whose upper half is zero reads as a large positive one. No Tokra test
failed for it, which shows only that its tests do not reach those cases.
