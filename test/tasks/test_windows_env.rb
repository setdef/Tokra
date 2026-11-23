# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "fileutils"
require "open3"
require "stringio"
require "tmpdir"
require "yaml"
require_relative "../../tasks/windows_env"

# Tests tasks/windows_env.rb (Plans 061 and 074): the command it runs gets
# what CI's Windows job sets for Rust and bindgen
# (.github/workflows/ci.yml), worked out from the Ruby, the Python, and the
# Rust pin of the checkout. WindowsEnv runs in folders of its own, beside a
# mise.toml of its own, with a runner that answers ruby and python by
# printing where RubyInstaller's MSYS2 and the libclang wheel would be, the
# way Windows spells a path, and records the command, so the tests run on
# every system and start nothing.
class TestWindowsEnv < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  # Answers ruby and python as told, and records every command with the
  # environment it was given.
  class Runner
    attr_reader :asked, :streamed
    attr_accessor :status

    def initialize
      @asked = []
      @streamed = []
      @answers = {}
      @status = 0
    end

    # Makes the command that starts with +program+ print +output+, or fail
    # with +error+ and +status+.
    def answer(program, output: "", error: "", status: 0)
      @answers[program] = Setup::Answer.new(output:, error:, status:)
    end

    def capture_separately(*argv, chdir:, env: {})
      @asked << [argv, chdir, env]
      @answers.fetch(argv.first)
    end

    def stream(*argv, chdir:, env: {})
      @streamed << [argv, chdir, env]
      @status
    end
  end

  def setup
    @dir = File.realpath(Dir.mktmpdir("windows_env"))
    @cache = File.join(@dir, "cache")
    @resource = File.join(@cache, "tokra/clang-18.1.1")
    FileUtils.mkdir_p(File.join(@resource, "include"))
    File.write(File.join(@resource, "include/stddef.h"), "")
    File.write(File.join(@dir, "mise.toml"), %([tools]\nruby = "4.0.9"\nrust = "1.2.3"\n))
    @sysroot = File.join(@dir, "msys64/ucrt64")
    FileUtils.mkdir_p(File.join(@sysroot, "include"))
    File.write(File.join(@sysroot, "include/stdio.h"), "")
    @libclang = File.join(@dir, "site-packages/clang/native")
    FileUtils.mkdir_p(@libclang)
    File.write(File.join(@libclang, "libclang.dll"), "")
    @msys = File.join(@dir, "msys64")
    FileUtils.mkdir_p(File.join(@msys, "ucrt64/bin"))
    FileUtils.mkdir_p(File.join(@msys, "usr/bin"))
    File.write(File.join(@msys, "ucrt64/bin/gcc.exe"), "")
    @runner = Runner.new
    @runner.answer("ruby", output: windows(@sysroot))
    @runner.answer("python", output: "#{windows(@libclang)}\r\n")
    @env = { "XDG_CACHE_HOME" => @cache, "PATH" => File.join(@msys, "usr/bin") }
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  # How RubyInstaller and Python print a path on Windows: backslashes.
  private def windows(path) = path.tr("/", "\\")

  private def windows_env
    @err = StringIO.new
    WindowsEnv.new(checkout: @dir, env: @env, runner: @runner, err: @err)
  end

  private def run_env(*argv)
    windows_env.call(argv)
  end

  private def added = @runner.streamed.last[2]

  private def ci_step(name)
    workflow = YAML.safe_load_file(File.join(ROOT, ".github/workflows/ci.yml"))
    workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps") }.find { |step| step["name"] == name }.fetch("run")
  end

  def test_the_command_runs_with_its_arguments_and_the_rust_pin_on_the_gnu_host
    status = run_env("bundle", "exec", "rake", "two words")

    assert_equal 0, status, @err.string
    assert_equal [["bundle", "exec", "rake", "two words"]], @runner.streamed.map(&:first)
    assert_equal Dir.pwd, @runner.streamed.last[1]
    assert_equal "1.2.3-x86_64-pc-windows-gnu", added["RUSTUP_TOOLCHAIN"]
  end

  # The same clang arguments ci.yml's step writes, at Ruby's own MSYS2,
  # and libclang from the wheel setup installs, with forward slashes as
  # ci.yml writes them. The wheel has none of the headers a full LLVM has
  # beside libclang, so clang also gets the resource folder ClangHeaders
  # unpacks.
  def test_bindgen_gets_ci_s_arguments_at_ruby_s_msys2_and_the_wheel_s_libclang
    status = run_env("recorder")

    assert_equal 0, status, @err.string
    ci = ci_step("Point bindgen at Ruby's MSYS2 headers")[/BINDGEN_EXTRA_CLANG_ARGS=(.*)" >>/, 1]

    assert_equal "#{ci.sub('$sysroot', @sysroot)} -resource-dir=#{@resource}", added["BINDGEN_EXTRA_CLANG_ARGS"]
    assert_equal @libclang, added["LIBCLANG_PATH"]
  end

  def test_ruby_and_python_are_asked_from_the_checkout
    run_env("recorder")
    ruby, python = @runner.asked

    assert_equal ["ruby", "-e", WindowsEnv::SYSROOT], ruby[0]
    assert_includes ruby[0].last, "msys2_installation"
    assert_equal ["python", "-c", WindowsEnv::LIBCLANG], python[0]
    assert_includes python[0].last, "clang.__file__"
    assert_equal [@dir, @dir], [ruby[1], python[1]]
  end

  # A Ruby with no MSYS2 beside it, or a Python without the wheel, would
  # fail deep in a build script; this says which, in the order a build
  # needs them.
  def test_missing_c_headers_libclang_or_clang_s_headers_stop_it_before_the_command
    File.delete(File.join(@sysroot, "include/stdio.h"))

    refute_equal 0, run_env("recorder")
    assert_includes @err.string, "windows-env: no C headers (stdio.h) in #{@sysroot}/include, Ruby's MSYS2; run ridk install."
    assert_empty @runner.streamed

    File.write(File.join(@sysroot, "include/stdio.h"), "")
    File.delete(File.join(@libclang, "libclang.dll"))

    refute_equal 0, run_env("recorder")
    assert_includes @err.string, "windows-env: no libclang.dll in #{@libclang}; run bin/setup."
    assert_empty @runner.streamed

    File.write(File.join(@libclang, "libclang.dll"), "")
    File.delete(File.join(@resource, "include/stddef.h"))

    refute_equal 0, run_env("recorder")
    assert_includes @err.string, "windows-env: no clang headers (stddef.h) in #{@resource}/include; run bin/setup."
    assert_empty @runner.streamed
  end

  # RubyInstaller finds an MSYS2 by MSYS2_PATH, beside Ruby, at C:\msys64,
  # in the registry, or as a PATH entry that is an MSYS2's root, and mise's
  # Ruby is beside none. Where PATH leads to an MSYS2 with the UCRT64
  # compiler, as an MSYS2's own bash does, Ruby gets it.
  def test_ruby_finds_the_msys2_that_path_leads_to_when_it_has_the_ucrt64_compiler
    status = run_env("recorder")

    assert_equal 0, status, @err.string
    assert_equal({ "MSYS2_PATH" => @msys }, @runner.asked.first.last)
    assert_equal @msys, added["MSYS2_PATH"]
  end

  def test_the_msys2_may_be_found_by_its_ucrt64_folder_or_a_windows_spelling_and_the_first_with_the_compiler_wins
    git = File.join(@dir, "Git")
    FileUtils.mkdir_p(File.join(git, "usr/bin"))
    @env["PATH"] = [File.join(git, "usr/bin"), windows(File.join(@msys, "ucrt64/bin"))].join(File::PATH_SEPARATOR)
    run_env("recorder")

    assert_equal @msys, added["MSYS2_PATH"]
  end

  # Git for Windows' usr/bin is an MSYS2's with no compiler, and an
  # MSYS2_PATH of your own names the MSYS2 you chose.
  def test_ruby_keeps_its_own_lookup_without_that_compiler_or_with_msys2_path_set
    File.delete(File.join(@msys, "ucrt64/bin/gcc.exe"))
    status = run_env("recorder")

    assert_equal 0, status, @err.string
    assert_empty @runner.asked.first.last
    refute added.key?("MSYS2_PATH")

    @env["MSYS2_PATH"] = "D:/msys64"
    File.write(File.join(@msys, "ucrt64/bin/gcc.exe"), "")
    run_env("recorder")

    assert_empty @runner.asked.last.last
    refute added.key?("MSYS2_PATH")
  end

  # mise.toml's [env] sets MSYS2_PATH to nothing off Windows (Plan 071),
  # which is as good as unset.
  def test_an_empty_msys2_path_is_unset
    @env["MSYS2_PATH"] = ""
    run_env("recorder")

    assert_equal @msys, added["MSYS2_PATH"]
  end

  # A Ruby that finds no MSYS2 says so itself, and nothing runs after it.
  def test_a_ruby_that_finds_no_msys2_stops_it_before_the_command
    @runner.answer("ruby", error: "MSYS2 could not be found\n", status: 1)
    status = run_env("recorder")

    assert_equal 1, status
    assert_includes @err.string, "windows-env: MSYS2 could not be found"
    refute_includes @err.string, "no C headers"
    assert_empty @runner.streamed
  end

  def test_a_python_that_fails_with_no_message_says_which_program_and_status
    @runner.answer("python", status: 9)
    status = run_env("recorder")

    assert_equal 1, status
    assert_includes @err.string, "windows-env: python failed with status 9"
    assert_empty @runner.streamed
  end

  def test_the_command_s_status_is_its_own
    @runner.status = 5

    assert_equal 5, run_env("failing")
  end

  def test_with_no_command_it_says_how_to_use_it_and_runs_nothing
    status = run_env

    assert_equal 2, status
    assert_equal "usage: bin/windows-env COMMAND [ARGUMENT...]\n", @err.string
    assert_empty @runner.asked
    assert_empty @runner.streamed
  end

  # The mode the commit records, since a Windows checkout records none.
  def test_it_is_tracked_as_executable
    listed, status = Open3.capture2("git", "ls-tree", "HEAD", "--", "bin/windows-env", chdir: ROOT)

    assert_predicate status, :success?
    assert_match(/\A100755 /, listed)
  end
end
