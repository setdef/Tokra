# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "fileutils"
require "tmpdir"
require_relative "setup"

# Puts clang's own headers (stddef.h, mm_malloc.h, the intrinsics) in
# Tokra's folder of your cache, for bindgen on Windows (Plans 061 and
# 074). tasks/setup.rb runs it there, as bin/clang-headers, and
# WindowsEnv points bindgen at what it unpacks.
#
# bindgen loads libclang from PyPI's libclang wheel, which holds the
# library and none of the headers clang finds beside a full LLVM, so
# parsing Ruby's MinGW headers stops at the first of them. These come from
# LLVM's clang source release of the wheel's version, whose lib/Headers is
# clang's resource include folder as it ships, checked against the SHA-256
# below and unpacked once. It needs curl and a tar that reads xz, which
# Windows 10 and MSYS2 both have; the checksum is Ruby's.
#
# === Example
#
#   ClangHeaders.new(env: ENV.to_h).call # => 0
class ClangHeaders
  # Why the headers could not be brought.
  class Failure < StandardError
    attr_reader :status

    def initialize(message, status = 1)
      super(message)
      @status = status
    end
  end

  # The libclang wheel's version, and so the release's.
  VERSION = "18.1.1"

  # The SHA-256 of the release's clang-VERSION.src.tar.xz.
  SHA256 = "412a482b81a969846b127552f8fa2251c7d57a82337f848fe7fea8e6ce614836"

  # The folder +env+'s cache holds the headers in: XDG_CACHE_HOME when set,
  # else .cache in the home.
  def self.directory(env, version: VERSION)
    cache = env["XDG_CACHE_HOME"].to_s
    cache = File.join(env["HOME"] || env["USERPROFILE"], ".cache") if cache.empty?
    File.join(cache, "tokra", "clang-#{version}")
  end

  # [env] The environment to read (XDG_CACHE_HOME, HOME, USERPROFILE).
  # [runner] What runs curl and tar: a Setup::Shell, or whatever answers
  #          #stream.
  # [sha256] The release's checksum, which tests replace.
  # [out] and [err] Where it says what it does and what is wrong.
  def initialize(env: ENV, runner: Setup::Shell.new(env: {}), sha256: SHA256, out: $stdout, err: $stderr)
    @env = env
    @runner = runner
    @sha256 = sha256
    @out = out
    @err = err
  end

  # The folder the headers are in, with an include folder.
  def directory = self.class.directory(@env)

  # The release's address.
  def url = "https://github.com/llvm/llvm-project/releases/download/llvmorg-#{VERSION}/clang-#{VERSION}.src.tar.xz"

  # Unpacks the headers unless they are there, and returns the exit
  # status: 0, or the status of the command that failed, or 1.
  def call
    return 0 if unpacked?(directory)

    unpack
    0
  rescue Failure => e
    @err.puts "clang-headers: #{e.message}"
    e.status
  end

  private def unpacked?(folder) = File.file?(File.join(folder, "include", "stddef.h"))

  private def unpack
    FileUtils.mkdir_p(File.dirname(directory))
    work = Dir.mktmpdir("clang-#{VERSION}.", File.dirname(directory))
    download(work)
    verify(File.join(work, "src.tar.xz"))
    FileUtils.mkdir_p(File.join(work, "resource", "include"))
    extract(work)
    # Another setup may have unpacked the same headers meanwhile.
    return if unpacked?(directory)

    FileUtils.rm_rf(directory)
    File.rename(File.join(work, "resource"), directory)
  ensure
    FileUtils.rm_rf(work) if work
  end

  private def download(work)
    run(work, "curl", "--fail", "--silent", "--show-error", "--location", "--retry", "3",
      "--output", File.join(work, "src.tar.xz"), url)
  end

  private def verify(archive)
    return if Digest::SHA256.file(archive).hexdigest == @sha256

    raise Failure, "#{url} does not match its SHA-256, #{@sha256}."
  end

  # GNU tar reads a name like C:/... as another host's file, so it is given
  # names relative to the folder it runs in.
  private def extract(work)
    run(work, "tar", "-xJf", "src.tar.xz", "-C", "resource/include", "--strip-components=3",
      "clang-#{VERSION}.src/lib/Headers")
  end

  private def run(work, *argv)
    status = @runner.stream(*argv, chdir: work)
    raise Failure.new("#{argv.first} failed with status #{status}", status) unless status.zero?
  end
end
