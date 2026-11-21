<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Upstream reports, drafted and not filed: Ruby 4.1's `rb_len_t` on MinGW

2026-11-21. Two bug reports, written as they would be filed, one for
rb-sys and one for magnus. Neither has been filed. Whether and when to
file them is the maintainer's to say. Plan 069 ("Why Windows stays on
4.0") records how Tokra met the fault; this note is the report itself.

The maintainer decided on 2026-11-21 that Tokra moves to Ruby 4.1 on
Windows without waiting for these fixes. How it does so, a patched
magnus and a corrected binding among the options, is the next plan's to
say, and that plan replaces plan 069's "Tokra builds nothing on a
Windows Ruby 4.1".

## What is established, and how

- **Ruby 4.1 adds `rb_len_t`**, the type of the lengths and indices of
  String, Array, and MatchData. It is `long`, "except on 64-bit mswin,
  where they are 64 bits" (ruby/ruby `NEWS.md`, "Type for lengths and
  indices", Feature #22400). The header makes it `int64_t` whenever
  `SIZEOF_RB_LEN_T` is defined wider than `long`, and otherwise defines
  `SIZEOF_RB_LEN_T` as `SIZEOF_LONG` (`include/ruby/internal/value.h`,
  lines 127 to 150). Read in ruby/ruby's source.
- **RubyInstaller's head build defines it on MinGW too**:
  `CPPFLAGS+=" -DSIZEOF_RB_LEN_T=8"` (rubyinstaller2-packages,
  `mingw-w64-ruby-head/PKGBUILD`, line 62). So on that Ruby `long` is 32
  bits, every length is 64, and `RbConfig::CONFIG["CPPFLAGS"]` carries
  the define. Read in the package's source, and seen in the bindings
  below; the line number was not re-read for this note.
- **rb-sys-build passes RbConfig's CPPFLAGS to bindgen**
  (`crates/rb-sys-build/src/bindings.rs`, `clang_args.extend(rbconfig.cppflags())`;
  `src/rb_config.rs`, `cppflags`), at 0.9.130. Read in rb-sys's source.
- **Two builds of one crate on one Ruby gave two bindings.** Under plain
  cargo (`cargo test --locked`), the generated bindings say
  `pub type rb_len_t = i64`. Under rake-compiler, through the rb_sys
  gem's Makefile, they say `rb_len_t` is `c_long`, 32 bits. Seen by
  printing both generated files on a Windows machine with the
  RubyInstaller head build of 2026-11-10 (x64-mingw-ucrt), rb-sys
  0.9.130, and its `stable-api-compiled-fallback` feature.
- **magnus does not compile against the 64-bit binding**: 38 errors,
  E0308 mismatched types and E0606 "casting `&mut i32` as `*mut i64` is
  invalid", the first at `src/debug.rs:936`, `index as c_long`. Seen
  with magnus 0.9.3; magnus 0.9.4 and its main branch name no
  `rb_len_t` in `src/` (read, not built).
- **Against the 32-bit binding the extension compiles and its tests
  pass**: Tokra's extension, six gems that bind crates through magnus,
  and about 2,400 Ruby tests over them. Seen on the same machine.

Not established: where the define is lost on the Makefile path; whether
a released RubyInstaller 4.1.0 keeps the define; and any wrong result at
run time from the 32-bit binding. No test failed because of it. The
case against it is the ABI: a length the C API takes or returns as a
64-bit integer is declared 32 bits, so the upper half of an argument is
whatever the register held, and an out-parameter is written eight bytes
wide into four.

## Report for rb-sys

**Title:** On RubyInstaller's Ruby 4.1 (MinGW), bindings built through
the Makefile bind `rb_len_t` as 32 bits while Ruby's is 64

**Environment.** Windows x64, RubyInstaller head build of 2026-11-10
(`ruby 4.1.0dev`, x64-mingw-ucrt), rb-sys and rb_sys 0.9.130 with
`stable-api-compiled-fallback`, bindgen as rb-sys-build pins it.

**What happens.** Ruby 4.1 adds `rb_len_t` (Feature #22400).
RubyInstaller builds its MinGW Ruby with `-DSIZEOF_RB_LEN_T=8`, so
`rb_len_t` is `int64_t` there although `long` is 32 bits, and
`RbConfig::CONFIG["CPPFLAGS"]` carries the define. The same crate, on
the same Ruby, gets different bindings by how it is built:

- `cargo build` or `cargo test`: `pub type rb_len_t = i64`. This matches
  Ruby.
- `rake compile` (rake-compiler with `create_rust_makefile`), and so
  `gem install`: `rb_len_t` is `::std::os::raw::c_long`, 32 bits. This
  does not match Ruby, and nothing says so: the build succeeds.

**To reproduce.** With that Ruby first on `PATH`, in any gem built with
`create_rust_makefile`:

1. `ruby -e 'puts RbConfig::CONFIG["CPPFLAGS"]'` prints a line holding
   `-DSIZEOF_RB_LEN_T=8`.
2. `cargo build`, then search the generated bindings under
   `target/**/out/` for `rb_len_t`: `i64`.
3. `rake compile`, then search the bindings under the Makefile's target
   directory: `c_long`.

**Expected.** Both builds bind `rb_len_t` as Ruby's headers define it
for that Ruby, 64 bits here.

**Where we looked.** `rb-sys-build` gives bindgen `rbconfig.cppflags()`
(`src/bindings.rs`), and under the Makefile the build script reads
RbConfig from `RBCONFIG_*` variables that the rb_sys gem's `mkmf.rb`
writes (`env_vars`). We did not trace where the define is dropped
between them.

**Why it matters.** Extensions installed as gems on this Ruby pass and
read every String, Array, and MatchData length with the wrong width,
silently. A released RubyInstaller 4.1.0 may carry the same flag.

**A further ask.** A build-time assertion that the bound `rb_len_t` has
`RbConfig::SIZEOF["rb_len_t"]` bytes would turn this, and any later
drift of its kind, into a build error.

## Report for magnus

**Title:** magnus does not compile where Ruby 4.1's `rb_len_t` is wider
than `long` (RubyInstaller's MinGW build, and 64-bit mswin)

**Environment.** As above, with magnus 0.9.3, built with
`cargo test --locked`.

**What happens.** Ruby 4.1 adds `rb_len_t` for lengths and indices
(Feature #22400). It is `long` on most platforms, 64 bits on 64-bit
mswin by Ruby's own configuration, and 64 bits on RubyInstaller's MinGW
build, which defines `SIZEOF_RB_LEN_T=8`. There rb-sys binds the C API's
lengths as `i64`, and magnus casts them with `as c_long`, which is
`i32` on Windows:

```
error[E0308]: mismatched types
   expected `i64`, found `i32`     (src/debug.rs:936, `index as c_long`)
error[E0606]: casting `&mut i32` as `*mut i64` is invalid
error: could not compile `magnus` (lib) due to 38 previous errors
```

The sites are the length and index arguments and out-parameters in
`debug.rs`, `r_array.rs`, `r_string.rs`, and their neighbors. magnus
0.9.4 and the main branch have no mention of `rb_len_t`.

**To reproduce.** On Windows with RubyInstaller's head Ruby, in a crate
that depends on magnus: `cargo build`.

**Expected.** magnus compiles on every platform Ruby 4.1 supports, and
passes lengths in the type Ruby's API declares.

**A possible fix.** Use `rb_sys::rb_len_t` (falling back to `c_long`
where rb-sys does not define it, on Ruby 4.0 and earlier) at each site
that now casts a length or index to `c_long`, and for the
out-parameters of calls such as `rb_range_beg_len`.

**Note.** Today the failure shows only under plain cargo. Through
rake-compiler, rb-sys binds `rb_len_t` as 32 bits on this Ruby (the
rb-sys report above), so magnus compiles there and runs against a Ruby
whose lengths are 64 bits. When rb-sys corrects its binding, every
magnus gem on this Ruby stops compiling until magnus follows, so the two
fixes are best released together.
