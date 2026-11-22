<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Pull request for magnus, drafted and not filed: pass lengths as `rb_len_t`

2026-11-22. The text below is the pull request as it would be opened
against matsadler/magnus. `magnus-rb-len-t.patch` beside it is the
change, made against magnus's main branch at a73a3cc (2026-11-18). It has
not been filed; whether and when is the maintainer's to say. Tokra
carries the same change on magnus 0.9.3 in `vendor/magnus` (Plan 071).

---

**Title:** Pass lengths and indices as `rb_len_t` on Ruby 4.1

Ruby 4.1 adds `rb_len_t`, the type of the lengths and indices of String,
Array, and MatchData in the C API (Feature #22400, ruby/ruby 03e3376643).
It is `long`, except where Ruby is configured with `SIZEOF_RB_LEN_T`
wider than `long`, when it is `int64_t`
(`include/ruby/internal/value.h`). 64-bit mswin is configured so, and so
is RubyInstaller's MinGW build of Ruby 4.1
(`CPPFLAGS+=" -DSIZEOF_RB_LEN_T=8"`, rubyinstaller2-packages,
`mingw-w64-ruby-head/PKGBUILD`), where `long` is 32 bits. There rb-sys
binds `rb_len_t` as `i64`, and every function that takes a length, such
as `rb_str_new`, `rb_ary_entry`, and `rb_range_beg_len`, takes an `i64`.

magnus casts each length and index `as c_long`, which is `i32` on
Windows, so on that Ruby magnus does not compile. On main:

```
error[E0308]: mismatched types
    --> src\debug.rs:940:68
     |
 940 |             Value::new(rb_debug_inspector_frame_self_get(self.ptr, index as c_long))
     |                        ---------------------------------           ^^^^^^^^^^^^^^^ expected `i64`, found `i32`
...
error: could not compile `magnus` (lib) due to 37 previous errors
```

This adds a crate-private alias, `Len`, which is `rb_sys::rb_len_t` on
Ruby 4.1 and newer and `c_long` before it, by the `ruby_gte_4_1` and
`ruby_lt_4_1` cfgs magnus already uses, and casts each length and index
to it where it now casts to `c_long`: `debug.rs`, `r_array.rs`,
`r_hash.rs`, `r_regexp.rs`, `r_string.rs`, `range.rs` (including the
out-parameters of `rb_range_beg_len`), and `value.rs`. The other
`c_long`s are left alone: the Fixnum bounds and comparisons in
`value.rs`, `integer.rs`, and `r_bignum.rs` are about `long` itself.

Where `rb_len_t` is `long`, which is everywhere but those two builds,
`Len` is `c_long` and nothing changes. No public signature changes.

**Tested** on Windows x64 with RubyInstaller's head build of 2026-11-10
(`ruby 4.1.0dev (2026-11-10 master 0e25874222) [x64-mingw-ucrt]`),
with main's locked rb-sys (0.9.128, given
`--features rb-sys/stable-api-compiled-fallback`, which every Ruby 4.1
needs today): `cargo build --all-features` fails with the 37 errors
without this change, and compiles with no warning with it. Through an extension that depends on
magnus 0.9.3 with the same change, built both by plain cargo and by
rb_sys's Makefile with `rb_len_t` bound as `i64`, the extension compiles
with Clippy clean, and its Rust and Ruby tests pass.

**Note.** Today an extension built by `gem install` on that Ruby gets
bindings with `rb_len_t` as `c_long`, because rb_sys's Makefile hands
the build script an empty `CPPFLAGS` on Windows (reported to rb-sys
separately). So magnus compiles there and passes 32-bit lengths to a Ruby
that reads 64. Once rb-sys passes the define, magnus fails to compile on
that Ruby until this change ships, so the two are best released close
together.
