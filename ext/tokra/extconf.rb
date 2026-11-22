# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "mkmf"
require "rb_sys/mkmf"

# --locked: build against the Cargo.lock shipped with the gem, the versions
# the repository tested, and fail rather than resolve newer ones.
#
# rb_sys's Makefile hands every RbConfig::CONFIG entry to rb-sys's build
# script as RBCONFIG_<key> (rb_sys 0.9.130, cargo_builder.rb,
# rb_config_env), which reads one before RbConfig itself. Windows' names for
# environment variables ignore case, so keys that differ only in case, as
# CPPFLAGS and cppflags do, arrive as one variable with either value. There
# bindgen got an empty CPPFLAGS and lost RubyInstaller's
# -DSIZEOF_RB_LEN_T=8, binding Ruby 4.1's 64-bit lengths as 32 bits (Plan
# 071). An entry the Makefile leaves out, rb-sys reads from RbConfig.
if Gem.win_platform?
  ambiguous = RbConfig::CONFIG.keys.group_by(&:downcase).values.select { |keys| keys.size > 1 }.flatten
end
create_rust_makefile("tokra/tokra") do |r|
  r.extra_cargo_args += ["--locked"]
  ambiguous&.each { |key| r.env["RBCONFIG_#{key}"] = nil }
end

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Shipping WebView2Loader.dll with GNU builds adapted from tauri-build/src/lib.rs
#
# On Windows, wry reaches WebView2 through webview2-com-sys, which links the
# loader statically only for MSVC; for the GNU target that RubyInstaller's
# Ruby needs, it imports WebView2Loader.dll (webview2-com-sys 0.38.2
# src/lib.rs:13-24), and its build script copies the DLL from the crate into
# its OUT_DIR/<arch> for the linker (build.rs:39-91). Windows then looks
# for the DLL when it loads the extension, and Tauri copies it beside its
# executable for GNU builds (tauri-build src/lib.rs:660-682). Tokra's
# extension is loaded by ruby.exe, so the DLL goes beside the extension
# instead, installed by the same make install that installs it, and
# lib/tokra.rb adds that directory to the DLL search path before the
# extension loads. Every build of the locked crate holds the same file, so
# whichever build directory a glob finds first serves.
if RbConfig::CONFIG["host_os"].match?(/mingw|mswin/)
  arch = { "x86_64" => "x64", "x64" => "x64", "aarch64" => "arm64", "arm64" => "arm64" }
    .fetch(RbConfig::CONFIG["host_cpu"], "x86")
  File.open("Makefile", "a") do |makefile|
    makefile.puts <<~MAKE

      # WebView2Loader.dll beside the extension (see ext/tokra/extconf.rb).
      install: install-webview2-loader
      install-webview2-loader: $(DLLIB) $(TIMESTAMP_DIR)/.sitearchdir.time
      \t$(Q) $(MAKEDIRS) $(RUBYARCHDIR)
      \t$(INSTALL_PROG) "$$(ls $(subst \\,/,$(RUSTLIBDIR))/build/webview2-com-sys-*/out/#{arch}/WebView2Loader.dll | head -n 1)" $(RUBYARCHDIR)
    MAKE
  end
end
# SPDX-SnippetEnd
