# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "clang_headers"
require_relative "setup"

# Runs a command on Windows with what Rust needs to build Tokra for
# RubyInstaller's Ruby, as CI's Windows job sets it
# (.github/workflows/ci.yml): tasks/setup.rb runs bundle install through
# it, and .githooks/pre-push the gate (Plans 061 and 074).
#
# RubyInstaller's Ruby is a MinGW build, and rb-sys refuses to build it
# with Rust's MSVC target, so Cargo runs the GNU host toolchain of
# mise.toml's Rust, which tasks/setup.rb installs. bindgen parses Ruby's
# headers with clang targeting MinGW, against the MSYS2 tree Ruby builds
# gems with, and loads libclang from the PyPI wheel tasks/setup.rb
# installs into mise's Python, with clang's own headers from
# ClangHeaders. The two AVX-512 defines are CI's: they keep clang from
# parsing intrinsics headers bindgen cannot handle (rust-bindgen #2500).
#
# RubyInstaller looks for its MSYS2 in MSYS2_PATH, beside Ruby, at
# C:\msys64, in the registry, and among PATH's entries for an MSYS2's
# root. Under mise, MSYS2_PATH names the MSYS2 mise.toml pins (Plan 071).
# When it is unset, as for a Ruby of your own, and PATH leads to an MSYS2
# (an entry that is its usr/bin or its ucrt64/bin, as in an MSYS2's own
# bash) with the UCRT64 compiler, Ruby builds gems with that one. Git for
# Windows' usr/bin is an MSYS2's too, with no compiler, so there Ruby
# keeps its own lookup.
#
# === Example
#
#   exit WindowsEnv.new(checkout: Dir.pwd).call(%w[bundle exec rake])
class WindowsEnv
  # Why the environment could not be worked out.
  class Failure < StandardError; end

  # Cargo's target, where Rust's own host is the MSVC one.
  TARGET = "x86_64-pc-windows-gnu"

  # Prints where RubyInstaller's MSYS2 is, as it finds it: the MSYS2 and
  # the MinGW prefix inside it.
  SYSROOT = "m = RubyInstaller::Runtime.msys2_installation; print File.join(m.msys_path, m.mingw_prefix)"

  # Prints where the libclang wheel keeps libclang.
  LIBCLANG = 'import clang, os; print(os.path.join(os.path.dirname(clang.__file__), "native"))'

  USAGE = "usage: bin/windows-env COMMAND [ARGUMENT...]"

  # [checkout] The repository's folder, whose mise.toml pins the Rust.
  # [env] The environment to read (PATH, MSYS2_PATH, and ClangHeaders').
  # [runner] What runs ruby, python, and the command: a Setup::Shell, or
  #          whatever answers #capture_separately and #stream.
  # [err] Where it says what is wrong.
  def initialize(checkout:, env: ENV, runner: Setup::Shell.new(env: {}), err: $stderr)
    @checkout = checkout
    @env = env
    @runner = runner
    @err = err
  end

  # Runs +argv+ in the current folder with #environment added, and
  # returns its exit status; 2 for no command, and 1 where #environment
  # fails.
  def call(argv)
    if argv.empty?
      @err.puts USAGE
      return 2
    end

    @runner.stream(*argv, chdir: Dir.pwd, env: environment)
  rescue Failure => e
    @err.puts "windows-env: #{e.message}"
    1
  end

  # The variables to add to the environment of the command: the Rust
  # toolchain, bindgen's clang arguments, and libclang's folder, worked
  # out each time, with MSYS2_PATH where Ruby needs it. Raises Failure
  # where Ruby finds no MSYS2, and where the C headers, libclang, or
  # clang's headers are missing.
  def environment
    added = {}
    msys2 = msys2_path
    added["MSYS2_PATH"] = msys2 if msys2
    sysroot = asked_of("ruby", "-e", SYSROOT, env: added)
    libclang = asked_of("python", "-c", LIBCLANG)
    resource = File.expand_path(ClangHeaders.directory(@env))
    expect(File.join(sysroot, "include", "stdio.h"), "no C headers (stdio.h) in #{sysroot}/include, Ruby's MSYS2; run ridk install.")
    expect(File.join(libclang, "libclang.dll"), "no libclang.dll in #{libclang}; run bin/setup.")
    expect(File.join(resource, "include", "stddef.h"), "no clang headers (stddef.h) in #{resource}/include; run bin/setup.")
    added.merge(
      "RUSTUP_TOOLCHAIN" => "#{rust}-#{TARGET}",
      "BINDGEN_EXTRA_CLANG_ARGS" => "--target=#{TARGET} --sysroot=#{sysroot} -D__AVX512VLFP16INTRIN_H -D__AVX512FP16INTRIN_H -resource-dir=#{resource}",
      "LIBCLANG_PATH" => libclang
    )
  end

  private def rust
    File.read(File.join(@checkout, "mise.toml"))[/^rust = "([^"]*)"/, 1]
  end

  # The MSYS2 for Ruby to find through MSYS2_PATH: none where one is set,
  # or where none that PATH leads to has the UCRT64 compiler.
  private def msys2_path
    return unless @env["MSYS2_PATH"].to_s.empty?

    @env["PATH"].to_s.split(File::PATH_SEPARATOR).filter_map { |entry|
      entry.tr("\\", "/")[%r{\A(.+)/(?:usr|ucrt64)/bin/?\z}i, 1]
    }.find { |root| File.file?(File.join(root, "ucrt64", "bin", "gcc.exe")) }
  end

  # What +argv+ prints, as a path with forward slashes, as ci.yml writes
  # them.
  private def asked_of(*argv, env: {})
    answer = @runner.capture_separately(*argv, chdir: @checkout, env:)
    unless answer.status.zero?
      message = answer.error.strip
      raise Failure, message.empty? ? "#{argv.first} failed with status #{answer.status}" : message
    end

    answer.output.strip.tr("\\", "/")
  end

  private def expect(file, message)
    raise Failure, message unless File.file?(file)
  end
end
