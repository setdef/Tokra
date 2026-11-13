# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "open3"
require "tmpdir"
require "yaml"

# Tests .githooks/pre-push (Plan 061): which pushes run the gate, which it
# refuses, and that it runs the gate as ci.yml does. Each test hands the
# real hook the lines git would, in a real repository, with stand-ins for
# bundle and xvfb-run that log their arguments.
class TestPrePushHook < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  HOOK = File.join(ROOT, ".githooks/pre-push")
  ZERO = "0" * 40

  # A command that logs its name and arguments, one line a call.
  LOGGER = <<~'SH'
    #!/bin/sh
    { printf '%s' "$(basename "$0")"; for a in "$@"; do printf ' %s' "$a"; done; printf '\n'; } >> "$(dirname "$0")/log"
  SH

  # The variables a git hook passes on, which would point the git commands
  # here at the repository whose hook runs these tests.
  GIT_PLACE = %w[GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX].to_h { |name| [name, nil] }.freeze

  def setup
    skip "the hook is a POSIX shell script, and the Windows gate runs no hook yet" if Gem.win_platform?

    @dir = Dir.mktmpdir("pre_push")
    @bin = File.join(@dir, "bin")
    Dir.mkdir(@bin)
    %w[bundle xvfb-run].each do |name|
      File.write(File.join(@bin, name), LOGGER)
      File.chmod(0o755, File.join(@bin, name))
    end
    @repo = File.join(@dir, "repo")
    Dir.mkdir(@repo)
    git("init", "--quiet", "--initial-branch", "trunk")
    @first = commit("one")
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  private def git(*)
    settings = %w[user.name=tokra user.email=tokra@localhost commit.gpgSign=false core.hooksPath=/dev/null]
      .flat_map { |setting| ["-c", setting] }
    printed, status = Open3.capture2e(GIT_PLACE, "git", *settings, *, chdir: @repo)

    assert_predicate status, :success?, printed
    printed.strip
  end

  # Commits a change to the tracked file, and returns the commit.
  private def commit(text)
    File.write(File.join(@repo, "file"), text)
    git("add", "file")
    git("commit", "--quiet", "--message", text)
    git("rev-parse", "HEAD")
  end

  # Runs the hook as git does for a push of +refs+, each a line of
  # <tt>local_ref local_sha remote_ref remote_sha</tt>, and returns what it
  # printed and its status.
  private def push(*refs)
    env = GIT_PLACE.merge("PATH" => "#{@bin}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}")
    Open3.capture2e(env, HOOK, "origin", "git@example.com:tokra.git", stdin_data: refs.map { |ref| "#{ref}\n" }.join, chdir: @repo)
  end

  # What the stand-ins were called with, one line a call.
  private def calls
    log = File.join(@bin, "log")
    File.exist?(log) ? File.readlines(log, chomp: true) : []
  end

  private def gate
    linux = RbConfig::CONFIG["host_os"].include?("linux")
    linux ? ["xvfb-run --auto-servernum dbus-run-session -- bundle exec rake"] : ["bundle exec rake"]
  end

  private def ci_step(name)
    workflow = YAML.safe_load_file(File.join(ROOT, ".github/workflows/ci.yml"))
    workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps") }.find { |step| step["name"] == name }.fetch("run")
  end

  def test_a_push_that_moves_a_branch_to_the_checked_out_commit_runs_the_gate
    output, status = push("refs/heads/trunk #{@first} refs/heads/trunk #{ZERO}")

    assert_predicate status, :success?, output
    assert_equal gate, calls
  end

  # git names the local side as it was typed, HEAD included, so the hook
  # reads the remote side, which is always a full ref.
  def test_a_branch_pushed_by_another_name_runs_the_gate_too
    output, status = push("HEAD #{@first} refs/heads/trunk #{ZERO}")

    assert_predicate status, :success?, output
    assert_equal gate, calls
  end

  def test_the_hook_runs_the_gate_as_ci_runs_it_on_linux_and_elsewhere
    hook = File.read(HOOK)

    assert_includes hook, "  Linux) exec #{ci_step('Run the gate under X11')} ;;\n"
    assert_includes hook, "  *) exec #{ci_step('Run the gate')} ;;\n"
  end

  def test_a_tag_a_deleted_branch_and_no_ref_at_all_run_no_gate
    [
      ["refs/tags/v1 #{@first} refs/tags/v1 #{ZERO}"],
      ["(delete) #{ZERO} refs/heads/old #{@first}"],
      [],
    ].each do |refs|
      output, status = push(*refs)

      assert_predicate status, :success?, output
      assert_empty calls, refs.inspect
    end
  end

  def test_a_commit_that_is_not_the_one_checked_out_is_refused_before_the_gate
    second = commit("two")
    output, status = push("refs/heads/trunk #{@first} refs/heads/trunk #{ZERO}")

    refute_predicate status, :success?
    assert_includes output, "pre-push: refs/heads/trunk would get #{@first}, but the working tree is at #{second}."
    assert_empty calls
  end

  def test_uncommitted_changes_are_refused_before_the_gate
    File.write(File.join(@repo, "file"), "edited, not committed")
    output, status = push("refs/heads/trunk #{@first} refs/heads/trunk #{ZERO}")

    refute_predicate status, :success?
    assert_includes output, "pre-push: the working tree has uncommitted changes"
    assert_empty calls
  end

  # A file git does not track is not part of the commit or of the gate,
  # whose tasks read git ls-files.
  def test_an_untracked_file_does_not_stop_the_push
    File.write(File.join(@repo, "scratch"), "not tracked")
    output, status = push("refs/heads/trunk #{@first} refs/heads/trunk #{ZERO}")

    assert_predicate status, :success?, output
    assert_equal gate, calls
  end

  # git runs a hook only if it is executable, and machines that run the
  # hook on a fresh checkout get the mode git recorded.
  def test_the_hook_is_tracked_as_executable
    listed, status = Open3.capture2(GIT_PLACE, "git", "ls-files", "--stage", "--", ".githooks/pre-push", chdir: ROOT)

    assert_predicate status, :success?
    assert_match(/\A100755 /, listed)
  end
end
