# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "open3"
require "tmpdir"
require "yaml"

# Tests bin/windows-env (Plan 061): the command it runs gets what CI's
# Windows job sets for Rust and bindgen (.github/workflows/ci.yml), worked
# out from the Ruby, the Python, and the Rust pin of the checkout. Each
# test runs the real script, from a copy beside a mise.toml of its own,
# with stand-ins for ruby and python that print where RubyInstaller's
# MSYS2 and the libclang wheel would be, the way Windows spells a path.
class TestWindowsEnv < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SCRIPT = File.join(ROOT, "bin/windows-env")

  # A command that keeps the environment it was given and its arguments.
  RECORDER = <<~'SH'
    #!/bin/sh
    env > "$(dirname "$0")/env"
    printf '%s\n' "$@" > "$(dirname "$0")/args"
  SH

  def setup
    skip "Ruby on Windows cannot run bin/windows-env or its stand-ins as commands; these tests stand in for Windows elsewhere" if Gem.win_platform?

    @dir = File.realpath(Dir.mktmpdir("windows_env"))
    @bin = File.join(@dir, "bin")
    FileUtils.mkdir_p(@bin)
    FileUtils.cp(SCRIPT, @bin)
    File.write(File.join(@dir, "mise.toml"), %([tools]\nruby = "4.0.9"\nrust = "1.2.3"\n))
    @sysroot = File.join(@dir, "msys64/ucrt64")
    FileUtils.mkdir_p(File.join(@sysroot, "include"))
    File.write(File.join(@sysroot, "include/stdio.h"), "")
    @libclang = File.join(@dir, "site-packages/clang/native")
    FileUtils.mkdir_p(@libclang)
    File.write(File.join(@libclang, "libclang.dll"), "")
    stand_in("ruby", "printf '%s' '#{windows(@sysroot)}'")
    stand_in("python", "printf '%s\\r\\n' '#{windows(@libclang)}'")
    stand_in("recorder", RECORDER.lines.drop(1).join)
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  # How RubyInstaller and Python print a path on Windows: backslashes.
  private def windows(path) = path.tr("/", "\\")

  private def stand_in(name, body)
    path = File.join(@bin, name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, path)
  end

  private def run_script(*, extra: {})
    env = { "PATH" => "#{@bin}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}" }.merge(extra)
    Open3.capture2e(env, File.join(@bin, "windows-env"), *, chdir: @dir)
  end

  private def recorded_env
    File.readlines(File.join(@bin, "env"), chomp: true).to_h { |line| line.split("=", 2) }
  end

  private def ci_step(name)
    workflow = YAML.safe_load_file(File.join(ROOT, ".github/workflows/ci.yml"))
    workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps") }.find { |step| step["name"] == name }.fetch("run")
  end

  def test_the_command_runs_with_its_arguments_and_the_rust_pin_on_the_gnu_host
    output, status = run_script("recorder", "exec", "rake", "two words")

    assert_predicate status, :success?, output
    assert_equal ["exec", "rake", "two words"], File.readlines(File.join(@bin, "args"), chomp: true)
    assert_equal "1.2.3-x86_64-pc-windows-gnu", recorded_env["RUSTUP_TOOLCHAIN"]
  end

  # The same clang arguments ci.yml's step writes, at Ruby's own MSYS2,
  # and libclang from the wheel bin/setup installs, with forward slashes
  # as ci.yml writes them.
  def test_bindgen_gets_ci_s_arguments_at_ruby_s_msys2_and_the_wheel_s_libclang
    output, status = run_script("recorder")

    assert_predicate status, :success?, output
    ci = ci_step("Point bindgen at Ruby's MSYS2 headers")[/BINDGEN_EXTRA_CLANG_ARGS=(.*)" >>/, 1]

    assert_equal ci.sub("$sysroot", @sysroot), recorded_env["BINDGEN_EXTRA_CLANG_ARGS"]
    assert_equal @libclang, recorded_env["LIBCLANG_PATH"]
  end

  # A Ruby with no MSYS2 beside it, or a Python without the wheel, would
  # fail deep in a build script; this says which.
  def test_missing_c_headers_or_libclang_stop_it_before_the_command
    File.delete(File.join(@sysroot, "include/stdio.h"))
    output, status = run_script("recorder")

    refute_predicate status, :success?
    assert_includes output, "windows-env: no C headers (stdio.h) in #{@sysroot}/include"
    refute_path_exists File.join(@bin, "env")

    File.write(File.join(@sysroot, "include/stdio.h"), "")
    File.delete(File.join(@libclang, "libclang.dll"))
    output, status = run_script("recorder")

    refute_predicate status, :success?
    assert_includes output, "windows-env: no libclang.dll in #{@libclang}"
    refute_path_exists File.join(@bin, "env")
  end

  def test_the_command_s_status_is_its_own
    stand_in("failing", "exit 5")
    _, status = run_script("failing")

    assert_equal 5, status.exitstatus
  end

  def test_it_is_tracked_as_executable
    listed, status = Open3.capture2("git", "ls-files", "--stage", "--", "bin/windows-env", chdir: ROOT)

    assert_predicate status, :success?
    assert_match(/\A100755 /, listed)
  end
end
