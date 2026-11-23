# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "digest"
require "fileutils"
require "open3"
require "stringio"
require "tmpdir"
require_relative "../../tasks/clang_headers"

# Tests tasks/clang_headers.rb (Plans 061 and 074): on Windows, clang's own
# headers, which the libclang wheel leaves out, from LLVM's clang source
# release, checked against its SHA-256 and unpacked as a resource folder in
# your cache. Each test runs ClangHeaders in folders of its own with a
# runner that answers curl by copying a small archive shaped like LLVM's,
# and runs everything else, tar above all, for real, so they run on every
# system and download nothing. The class pins that archive's SHA-256 in
# place of the release's.
class TestClangHeaders < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  VERSION = "18.1.1"
  URL = "https://github.com/llvm/llvm-project/releases/download/llvmorg-#{VERSION}/clang-#{VERSION}.src.tar.xz".freeze

  # Stands in for curl: it records each command, and copies the archive to
  # the file named by --output. Any other command runs for real, and what
  # it prints is not shown.
  class Downloader
    attr_reader :calls

    def initialize(archive)
      @archive = archive
      @calls = []
      @shell = Setup::Shell.new(env: {})
    end

    def stream(*argv, chdir:, env: {})
      return @shell.capture(*argv, chdir:, env:).status unless argv.first == "curl"

      @calls << argv
      FileUtils.cp(@archive, argv[argv.index("--output") + 1])
      0
    end
  end

  def setup
    @dir = File.realpath(Dir.mktmpdir("clang_headers"))
    @cache = File.join(@dir, "cache")
    @archive = build_archive
    @sha256 = Digest::SHA256.file(@archive).hexdigest
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  # An archive laid out as LLVM's clang source release is, with a header
  # in lib/Headers, one in a folder under it, and a file outside it. tar
  # gets names relative to the folder it runs in, since GNU tar reads a
  # name like C:/... as another host's file.
  private def build_archive
    tree = File.join(@dir, "tree")
    source = File.join(tree, "clang-#{VERSION}.src")
    FileUtils.mkdir_p(File.join(source, "lib/Headers/cuda_wrappers"))
    File.write(File.join(source, "lib/Headers/stddef.h"), "stddef\n")
    File.write(File.join(source, "lib/Headers/cuda_wrappers/new"), "new\n")
    File.write(File.join(source, "README.md"), "readme\n")
    archive = File.join(@dir, "clang-#{VERSION}.src.tar.xz")
    output, status = Open3.capture2e("tar", "-cJf", "../clang-#{VERSION}.src.tar.xz", "clang-#{VERSION}.src", chdir: tree)

    assert_predicate status, :success?, output
    archive
  end

  private def downloader = @downloader ||= Downloader.new(@archive)

  private def clang_headers(sha256: @sha256)
    @out = StringIO.new
    @err = StringIO.new
    ClangHeaders.new(env: { "XDG_CACHE_HOME" => @cache }, runner: downloader, sha256:, out: @out, err: @err)
  end

  private def resource = File.join(@cache, "tokra/clang-#{VERSION}")

  def test_it_unpacks_only_the_headers_as_a_resource_folder_in_the_cache
    status = clang_headers.call

    assert_equal 0, status, @err.string
    assert_equal "stddef\n", File.read(File.join(resource, "include/stddef.h"))
    assert_equal "new\n", File.read(File.join(resource, "include/cuda_wrappers/new"))
    assert_equal %w[include], Dir.children(resource)
    assert_equal ["clang-#{VERSION}"], Dir.children(File.join(@cache, "tokra"))
  end

  def test_it_downloads_llvm_s_release_of_its_version
    clang_headers.call

    assert_equal 1, downloader.calls.size
    assert_equal URL, downloader.calls.first.last
    assert_includes downloader.calls.first, "--fail"
    assert_equal "3", downloader.calls.first[downloader.calls.first.index("--retry") + 1]
  end

  def test_run_again_it_downloads_nothing
    clang_headers.call
    status = clang_headers.call

    assert_equal 0, status
    assert_equal 1, downloader.calls.size
  end

  # The class's own SHA-256 is the release's, which the stand-in's archive
  # does not have.
  def test_an_archive_that_does_not_match_the_pinned_sha256_is_refused
    status = clang_headers(sha256: ClangHeaders::SHA256).call

    refute_equal 0, status
    assert_includes @err.string, "clang-headers: #{URL} does not match its SHA-256, #{ClangHeaders::SHA256}."
    refute_path_exists resource
    assert_empty Dir.children(File.join(@cache, "tokra"))
  end

  # A tar that fails, as on an archive that is not one, ends it with a
  # message, and leaves nothing behind.
  def test_an_archive_tar_cannot_read_stops_it_and_leaves_nothing
    File.write(@archive, "not an archive")
    status = clang_headers(sha256: Digest::SHA256.file(@archive).hexdigest).call

    refute_equal 0, status
    assert_includes @err.string, "clang-headers: tar"
    refute_path_exists resource
    assert_empty Dir.children(File.join(@cache, "tokra"))
  end

  # A curl that fails says so, and nothing is unpacked.
  def test_a_download_that_fails_stops_it
    failing = Object.new
    def failing.stream(*, **) = 22
    status = ClangHeaders.new(env: { "XDG_CACHE_HOME" => @cache }, runner: failing, out: StringIO.new, err: @err = StringIO.new).call

    assert_equal 22, status
    assert_includes @err.string, "clang-headers: curl"
    refute_path_exists resource
  end

  def test_the_folder_is_in_the_xdg_cache_or_else_the_home_s_dot_cache
    assert_equal File.join(@cache, "tokra/clang-#{VERSION}"), ClangHeaders.directory({ "XDG_CACHE_HOME" => @cache, "HOME" => "/h" })
    assert_equal "/h/.cache/tokra/clang-#{VERSION}", ClangHeaders.directory({ "XDG_CACHE_HOME" => "", "HOME" => "/h" })
    assert_equal "/u/.cache/tokra/clang-#{VERSION}", ClangHeaders.directory({ "USERPROFILE" => "/u" })
  end

  def test_its_version_is_the_libclang_wheel_s
    assert_equal VERSION, ClangHeaders::VERSION
    assert_equal VERSION, Setup::LIBCLANG_VERSION
  end

  # The mode the commit records, since a Windows checkout records none.
  def test_it_is_tracked_as_executable
    listed, status = Open3.capture2("git", "ls-tree", "HEAD", "--", "bin/clang-headers", chdir: ROOT)

    assert_predicate status, :success?
    assert_match(/\A100755 /, listed)
  end
end
