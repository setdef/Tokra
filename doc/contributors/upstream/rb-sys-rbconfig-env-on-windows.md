<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Pull request for rb-sys, drafted and not filed: RbConfig keys that differ only in case

2026-11-22. The text below is the pull request as it would be opened
against oxidize-rb/rb-sys. `rb-sys-rbconfig-env-on-windows.patch` beside
it is the change, made against rb-sys's main branch at 7ade413d (v0.9.130
and two documentation commits). It has not been filed; whether and when
is the maintainer's to say. Tokra works around it in
`ext/tokra/extconf.rb` (Plan 071).

---

**Title:** On Windows, leave out RBCONFIG_ variables whose names differ only in case

`CargoBuilder#build_env` hands every `RbConfig::CONFIG` entry to the
build script as `RBCONFIG_<key>` (`gem/lib/rb_sys/cargo_builder.rb`,
`rb_config_env`), the Makefile exports them (`mkmf.rb`, `env_vars`), and
rb-sys-build's `RbConfig#get` reads such a variable before RbConfig
itself (`crates/rb-sys-build/src/rb_config.rs`, `try_rbconfig_env`).

RbConfig has keys that differ only in case: `CPPFLAGS` and `cppflags`,
`CFLAGS` and `cflags`, `CXXFLAGS` and `cxxflags`, among others. Windows
treats environment variable names case-insensitively, so by the time
cargo starts the build script, `RBCONFIG_CPPFLAGS` and `RBCONFIG_cppflags`
are one variable. On RubyInstaller's Ruby the empty `cppflags` won:

- the generated Makefile says
  `export RBCONFIG_CPPFLAGS := -DSIZEOF_RB_LEN_T=8 -D_WIN32_WINNT=0x0600 -D__MINGW_USE_VC2005_COMPAT -D_FILE_OFFSET_BITS=64`
  and, later, `export RBCONFIG_cppflags := `;
- with `RB_SYS_DEBUG_BUILD=1`, the build script's environment shows
  `"RBCONFIG_CPPFLAGS": ""`, while the RbConfig it read from Ruby holds
  the flags above;
- rb-sys-build's log, `INFO: using bindgen with clang args: [...]`,
  holds none of them.

So under `gem install` and `rake compile`, bindgen parses Ruby's headers
without Ruby's `CPPFLAGS`, while under plain `cargo build`, with no
`RBCONFIG_` variables, it gets them. On RubyInstaller's Ruby 4.1, which
defines `SIZEOF_RB_LEN_T=8` in `CPPFLAGS` and not in `config.h`, that
binds `rb_len_t` as `c_long`, 32 bits, where Ruby's lengths are 64: every
extension built from a gem passes String and Array lengths and indices
with the wrong width, silently. The same loss drops `_WIN32_WINNT` and
`_FILE_OFFSET_BITS=64` on every RubyInstaller Ruby.

This leaves those keys out of `build_env` on Windows (`Gem.win_platform?`,
where the Makefile runs), so the build script reads them from RbConfig,
as it does under plain cargo. Every other key is still passed, so
nothing else changes, and nothing changes off Windows. A test covers
both.

**Tested** on Windows x64 with RubyInstaller's head build of 2026-11-10
(`ruby 4.1.0dev (2026-11-10 master 0e25874222) [x64-mingw-ucrt]`), rb_sys
0.9.130, with the same keys left out by an extension's `extconf.rb`: the
build script then gives bindgen the flags, and `rb_len_t` is bound as
`i64`, as under plain cargo.

**A further gap, not changed here.** The stable API's C fallback
(`crates/rb-sys/src/stable_api/compiled.c`, which Ruby 4.1 builds use)
is compiled with RbConfig's `cflags` but not its `CPPFLAGS`
(`crates/rb-sys-build/src/cc.rs`), so on that Ruby it is compiled with
`rb_len_t` as `long` under either build. `RString` and `RArray` happen to
lay out the same both ways, since the next field is 8-byte aligned, and
the helpers return `long`, so nothing reads wrong for a length under
2^31; but the helpers are compiled for a Ruby configured unlike the one
they run in.

**Note.** Once this ships, magnus releases up to 0.9.4 no longer compile
on RubyInstaller's Ruby 4.1, since they cast lengths to `c_long`; a
magnus change to use `rb_len_t` is proposed alongside, and the two are
best released close together.
