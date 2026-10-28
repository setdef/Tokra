# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "json"
require "open3"
require "rbconfig"
require "fileutils"
require "tmpdir"

# Tokra::Env and Tokra::Process (Plan 039), the counterparts of Tauri's
# Env (tauri-utils lib.rs:262-316) and process module (process.rs).
class TestProcess < Minitest::Test
  LIB = File.expand_path("../lib", __dir__)

  # A script that changes what Ruby says about its command line after it
  # requires Tokra, then prints what Env.default holds.
  SCRIPT = <<~RUBY
    require "tokra"
    require "json"
    ARGV.replace(["--parsed"])
    $PROGRAM_NAME = "renamed"
    print JSON.generate(Tokra::Env.default.args_os)
  RUBY

  def test_env_holds_the_interpreter_the_absolute_script_and_the_arguments_as_tokra_loaded
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "app.rb"), SCRIPT)
      output, status = Open3.capture2(RbConfig.ruby, "-I", LIB, "app.rb", "a", "b c", "../relative", chdir: dir)

      assert status.success?, output
      assert_equal [RbConfig.ruby, File.join(File.realpath(dir), "app.rb"), "a", "b c", "../relative"],
        JSON.parse(output), "ARGV and $PROGRAM_NAME changed after require; the snapshot did not"
    end
  end

  def test_env_default_is_equal_each_time
    assert_equal Tokra::Env.default, Tokra::Env.default
    assert_predicate Tokra::Env.default.args_os, :frozen?
  end

  def test_current_binary_is_the_canonical_interpreter
    assert_equal File.realpath(RbConfig.ruby), Tokra::Process.current_binary(Tokra::Env.default)
  end

  def test_restart_spawns_the_binary_with_every_argument_after_the_first_and_exits_with_zero
    env = Tokra::Env.new(args_os: ["ruby", __FILE__, "a b", "--flag"])
    spawned = []
    exit = Process.stub(:spawn, -> (*command) { spawned << command and 1 }) do
      assert_raises(SystemExit) { Tokra::Process.restart(env) }
    end

    binary = Tokra::Process.current_binary(env)
    assert_equal [[[binary, binary], __FILE__, "a b", "--flag"]], spawned
    assert_equal 0, exit.status
  end

  def test_restart_without_a_current_binary_spawns_nothing_and_exits_with_zero
    spawned = []
    exit = Process.stub(:spawn, -> (*command) { spawned << command and 1 }) do
      Tokra::Process.stub(:current_binary, -> (_) { raise Tokra::Error::Io, "gone" }) do
        exit = nil
        assert_silent { exit = assert_raises(SystemExit) { Tokra::Process.restart(Tokra::Env.default) } }
        exit
      end
    end

    assert_empty spawned, "process.rs:76 restarts only if let Ok(path) = current_binary(env)"
    assert_equal 0, exit.status
  end

  # An app run with ruby -e or from standard input has no script to run
  # again; its first argument is code, or "-" for standard input.
  def test_restart_refuses_a_script_that_is_not_a_file_and_exits_with_zero
    ["-e", "-"].each do |script|
      spawned = []
      exit = nil
      _, stderr = capture_io do
        Process.stub(:spawn, -> (*command) { spawned << command and 1 }) do
          exit = assert_raises(SystemExit) do
            Tokra::Process.restart(Tokra::Env.new(args_os: [RbConfig.ruby, script, "puts 1"]))
          end
        end
      end

      assert_empty spawned, script
      assert_equal "failed to restart app: the app's script is not a file: #{script.inspect}\n", stderr
      assert_equal 0, exit.status
    end
  end

  # macOS refuses a symlink, so there the canonical path shows in a
  # case-insensitive volume's case; elsewhere a symlinked directory
  # resolves. File.expand_path would keep either spelling.
  def test_the_starting_binary_is_canonical
    Dir.mktmpdir do |dir|
      dir = File.realpath(dir)
      FileUtils.mkdir(File.join(dir, "bin"))
      binary = File.join(dir, "bin", "ruby")
      File.write(binary, "")
      spelled = if RbConfig::CONFIG["host_os"].include?("darwin")
        File.join(dir, "BIN", "RUBY")
      else
        File.symlink(File.join(dir, "bin"), File.join(dir, "link"))
        File.join(dir, "link", "ruby")
      end
      skip "#{dir} is case-sensitive" unless File.exist?(spelled)

      assert_equal binary, Tokra::Process::StartingBinary.new(spelled).cloned
    end
  end

  def test_a_starting_binary_that_is_missing_raises_io
    error = assert_raises(Tokra::Error::Io) { Tokra::Process::StartingBinary.new("/no/such/ruby").cloned }
    assert_match(/No such file or directory/, error.message)
  end

  def test_a_starting_binary_reached_through_a_symlink_is_refused_on_macos
    Dir.mktmpdir do |dir|
      dir = File.realpath(dir)
      FileUtils.mkdir(File.join(dir, "real"))
      File.write(File.join(dir, "real", "ruby"), "")
      File.symlink(File.join(dir, "real"), File.join(dir, "link"))
      through_link = File.join(dir, "link", "ruby")
      starting = Tokra::Process::StartingBinary.new(through_link)

      if RbConfig::CONFIG["host_os"].include?("darwin")
        error = assert_raises(Tokra::Error::Io) { starting.cloned }
        assert_equal "StartingBinary found current_exe() that contains a symlink on a non-allowed platform: " \
          "#{File.join(dir, 'link')}", error.message
      else
        assert_equal File.join(dir, "real", "ruby"), starting.cloned, "only macOS checks for symlinks"
      end
    end
  end
end
