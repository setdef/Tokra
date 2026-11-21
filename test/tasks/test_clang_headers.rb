# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "digest"
require "open3"
require "tmpdir"

# Tests bin/clang-headers (Plan 061): on Windows, clang's own headers,
# which the libclang wheel leaves out, from LLVM's clang source release,
# checked against its SHA-256 and unpacked as a resource folder in your
# cache. Each test runs a copy of the real script with a stand-in for curl
# that hands over a small archive shaped like LLVM's, and the copy pins
# that archive's SHA-256 in place of the release's.
class TestClangHeaders < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SCRIPT = File.join(ROOT, "bin/clang-headers")
  VERSION = "18.1.1"

  def setup
    skip "Ruby on Windows cannot run bin/clang-headers or its stand-ins as commands" if Gem.win_platform?

    @dir = File.realpath(Dir.mktmpdir("clang_headers"))
    @bin = File.join(@dir, "bin")
    FileUtils.mkdir_p(@bin)
    @cache = File.join(@dir, "cache")
    @archive = build_archive
    @script = File.join(@bin, "clang-headers")
    File.write(@script, File.read(SCRIPT).sub(/^sha256=\h{64}$/, "sha256=#{Digest::SHA256.file(@archive).hexdigest}"))
    File.chmod(0o755, @script)
    stand_in("curl", <<~SH)
      printf '%s\\n' "$*" >> "#{@dir}/curl.log"
      while [ $# -gt 1 ]; do [ "$1" = --output ] && cp "#{@archive}" "$2"; shift; done
    SH
    stand_in("sha256sum", 'exec shasum -a 256 "$@"') unless which("sha256sum")
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  private def which(program)
    ENV.fetch("PATH").split(File::PATH_SEPARATOR).any? { |path| File.executable?(File.join(path, program)) }
  end

  private def stand_in(name, body)
    path = File.join(@bin, name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, path)
  end

  # An archive laid out as LLVM's clang source release is, with a header
  # in lib/Headers, one in a folder under it, and a file outside it.
  private def build_archive
    tree = File.join(@dir, "tree")
    source = File.join(tree, "clang-#{VERSION}.src")
    FileUtils.mkdir_p(File.join(source, "lib/Headers/cuda_wrappers"))
    File.write(File.join(source, "lib/Headers/stddef.h"), "stddef\n")
    File.write(File.join(source, "lib/Headers/cuda_wrappers/new"), "new\n")
    File.write(File.join(source, "README.md"), "readme\n")
    archive = File.join(@dir, "clang-#{VERSION}.src.tar.xz")
    _, status = Open3.capture2e("tar", "-cJf", archive, "-C", tree, "clang-#{VERSION}.src")

    assert_predicate status, :success?
    archive
  end

  private def run_script(script = @script)
    env = { "PATH" => "#{@bin}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}", "XDG_CACHE_HOME" => @cache }
    Open3.capture2e(env, script, chdir: @dir)
  end

  private def resource = File.join(@cache, "tokra/clang-#{VERSION}")

  def test_it_unpacks_only_the_headers_as_a_resource_folder_in_the_cache
    output, status = run_script

    assert_predicate status, :success?, output
    assert_equal "stddef\n", File.read(File.join(resource, "include/stddef.h"))
    assert_equal "new\n", File.read(File.join(resource, "include/cuda_wrappers/new"))
    assert_equal %w[include], Dir.children(resource)
    assert_equal ["clang-#{VERSION}"], Dir.children(File.join(@cache, "tokra"))
  end

  def test_it_downloads_llvm_s_release_of_its_version
    run_script

    assert_includes File.read(File.join(@dir, "curl.log")),
      "https://github.com/llvm/llvm-project/releases/download/llvmorg-#{VERSION}/clang-#{VERSION}.src.tar.xz"
  end

  def test_run_again_it_downloads_nothing
    run_script
    File.delete(File.join(@dir, "curl.log"))
    output, status = run_script

    assert_predicate status, :success?, output
    refute_path_exists File.join(@dir, "curl.log")
  end

  # The real script's own SHA-256 is the release's, which the stand-in's
  # archive does not have.
  def test_an_archive_that_does_not_match_the_pinned_sha256_is_refused
    real = File.join(@bin, "real-clang-headers")
    FileUtils.cp(SCRIPT, real)
    output, status = run_script(real)

    refute_predicate status, :success?
    assert_includes output, "clang-headers: https://github.com/llvm/llvm-project/releases/download/llvmorg-#{VERSION}/clang-#{VERSION}.src.tar.xz does not match its SHA-256"
    refute_path_exists resource
  end

  def test_its_version_is_the_libclang_wheel_s
    assert_match(/^version=#{Regexp.escape(VERSION)}$/, File.read(SCRIPT))
    assert_includes File.read(File.join(ROOT, "bin/setup")), %("libclang==#{VERSION}")
  end

  def test_it_is_tracked_as_executable
    listed, status = Open3.capture2("git", "ls-files", "--stage", "--", "bin/clang-headers", chdir: ROOT)

    assert_predicate status, :success?
    assert_match(/\A100755 /, listed)
  end
end
