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
# real hook the lines git would, in a real repository, or pushes through
# it with a real git push, with stand-ins for bundle and xvfb-run that log
# their arguments and their environment.
class TestPrePushHook < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  HOOK = File.join(ROOT, ".githooks/pre-push")
  ZERO = "0" * 40

  # A command that logs its name and arguments, one line a call, keeps the
  # environment it was given, and exits with GATE_STATUS, or 0.
  LOGGER = <<~'SH'
    #!/bin/sh
    { printf '%s' "$(basename "$0")"; for a in "$@"; do printf ' %s' "$a"; done; printf '\n'; } >> "$(dirname "$0")/log"
    env > "$(dirname "$0")/env"
    exit "${GATE_STATUS:-0}"
  SH

  # A bin/linux-env that marks the environment it hands on and runs the
  # command, as the real one does where nothing is missing.
  LINUX_ENV = <<~SH
    #!/bin/sh
    LINUX_ENV_RAN=1 exec "$@"
  SH

  # The variables a git hook passes on, which would point the git commands
  # here at the repository whose hook runs these tests.
  GIT_PLACE = %w[GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX GIT_COMMON_DIR].to_h { |name| [name, nil] }.freeze

  # Git as these tests run it: no one's own configuration or hooks.
  GIT_ALONE = GIT_PLACE.merge("GIT_CONFIG_GLOBAL" => File::NULL, "GIT_CONFIG_NOSYSTEM" => "1").freeze

  LINUX = RbConfig::CONFIG["host_os"].include?("linux")

  def setup
    skip "the hook is a POSIX shell script, untested on Windows" if Gem.win_platform?

    @dir = File.realpath(Dir.mktmpdir("pre_push"))
    @bin = File.join(@dir, "bin")
    Dir.mkdir(@bin)
    %w[bundle xvfb-run].each do |name|
      File.write(File.join(@bin, name), LOGGER)
      File.chmod(0o755, File.join(@bin, name))
    end
    @repo = File.join(@dir, "repo")
    Dir.mkdir(@repo)
    git("init", "--quiet", "--initial-branch", "trunk")
    FileUtils.mkdir_p(File.join(@repo, "bin"))
    File.write(File.join(@repo, "bin/linux-env"), LINUX_ENV)
    File.chmod(0o755, File.join(@repo, "bin/linux-env"))
    git("add", "bin/linux-env")
    @first = commit("one")
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  private def env(extra = {})
    GIT_ALONE.merge("PATH" => "#{@bin}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}").merge(extra)
  end

  private def git(*, chdir: @repo, hooks: File::NULL)
    settings = %W[user.name=tokra user.email=tokra@localhost commit.gpgSign=false core.hooksPath=#{hooks}]
      .flat_map { |setting| ["-c", setting] }
    printed, status = Open3.capture2e(env, "git", *settings, *, chdir:)

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
  private def push(*refs, extra: {})
    Open3.capture2e(env(extra), HOOK, "origin", "git@example.com:tokra.git", stdin_data: refs.map { |ref| "#{ref}\n" }.join, chdir: @repo)
  end

  # What the stand-ins were called with, one line a call.
  private def calls
    log = File.join(@bin, "log")
    File.exist?(log) ? File.readlines(log, chomp: true) : []
  end

  # The environment the gate's command was given.
  private def gate_env
    File.readlines(File.join(@bin, "env"), chomp: true).to_h { |line| line.split("=", 2) }
  end

  private def gate = LINUX ? ["xvfb-run --auto-servernum dbus-run-session -- bundle exec rake"] : ["bundle exec rake"]

  private def ci_step(name)
    workflow = YAML.safe_load_file(File.join(ROOT, ".github/workflows/ci.yml"))
    workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps") }.find { |step| step["name"] == name }.fetch("run")
  end

  def test_a_push_that_moves_a_branch_to_the_checked_out_commit_runs_the_gate
    output, status = push("refs/heads/trunk #{@first} refs/heads/trunk #{ZERO}")

    assert_predicate status, :success?, output
    assert_equal gate, calls
  end

  # The hook exists to stop a push whose gate fails.
  def test_a_gate_that_fails_refuses_the_push_with_its_status
    output, status = push("refs/heads/trunk #{@first} refs/heads/trunk #{ZERO}", extra: { "GATE_STATUS" => "7" })

    assert_equal 7, status.exitstatus, output
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

    assert_includes hook, "    exec bin/linux-env #{ci_step('Run the gate under X11')} ;;\n"
    assert_includes hook, "  *) exec #{ci_step('Run the gate')} ;;\n"
  end

  # GTK takes a Wayland desktop before an X display, and connects to the
  # desktop's default socket even with WAYLAND_DISPLAY unset, so on a
  # Wayland desktop the gate's windows would open on it, not on Xvfb.
  def test_on_linux_the_gate_is_kept_off_a_wayland_desktop
    skip "the hook starts Xvfb only on Linux" unless LINUX

    output, status = push("refs/heads/trunk #{@first} refs/heads/trunk #{ZERO}", extra: { "WAYLAND_DISPLAY" => "wayland-0" })

    assert_predicate status, :success?, output
    refute_includes gate_env.keys, "WAYLAND_DISPLAY"
    assert_equal "x11", gate_env["GDK_BACKEND"]
  end

  # bin/linux-env brings ci.yml's packages where the system lacks them.
  def test_on_linux_the_gate_runs_through_bin_linux_env
    skip "the hook runs bin/linux-env only on Linux" unless LINUX

    output, status = push("refs/heads/trunk #{@first} refs/heads/trunk #{ZERO}")

    assert_predicate status, :success?, output
    assert_equal "1", gate_env["LINUX_ENV_RAN"]
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

  # One push may move several branches; each has to be the commit the gate
  # will test, the later ones too.
  def test_every_branch_in_a_push_is_checked_not_only_the_first
    second = commit("two")
    output, status = push(
      "refs/heads/trunk #{second} refs/heads/trunk #{@first}",
      "refs/heads/other #{@first} refs/heads/other #{ZERO}"
    )

    refute_predicate status, :success?
    assert_includes output, "pre-push: refs/heads/other would get #{@first}, but the working tree is at #{second}."
    assert_empty calls
  end

  def test_uncommitted_changes_are_refused_before_the_gate_staged_or_not
    [false, true].each do |staged|
      File.write(File.join(@repo, "file"), "edited, not committed")
      git("add", "file") if staged
      output, status = push("refs/heads/trunk #{@first} refs/heads/trunk #{ZERO}")

      refute_predicate status, :success?, "staged: #{staged}"
      assert_includes output, "pre-push: the working tree has uncommitted changes"
      assert_empty calls
    end
  end

  # The tests and the compiler read files git does not track, so a file
  # someone forgot to add would pass the gate here and be missing on CI.
  def test_an_untracked_file_is_refused_before_the_gate_and_named
    File.write(File.join(@repo, "forgotten.rb"), "not tracked")
    output, status = push("refs/heads/trunk #{@first} refs/heads/trunk #{ZERO}")

    refute_predicate status, :success?
    assert_includes output, "pre-push: the working tree has files git does not track"
    assert_includes output.lines(chomp: true), "forgotten.rb"
    assert_empty calls
  end

  def test_an_ignored_file_does_not_stop_the_push
    File.write(File.join(@repo, ".gitignore"), "/tmp/\n")
    git("add", ".gitignore")
    git("commit", "--quiet", "--message", "ignore tmp")
    head = git("rev-parse", "HEAD")
    FileUtils.mkdir_p(File.join(@repo, "tmp"))
    File.write(File.join(@repo, "tmp/built"), "build output")
    output, status = push("refs/heads/trunk #{head} refs/heads/trunk #{@first}")

    assert_predicate status, :success?, output
    assert_equal gate, calls
  end

  # From a worktree git hands a hook GIT_DIR, and with it every git the
  # gate runs would act on that worktree, whichever folder it ran in: the
  # packaging tests make repositories of their own. This pushes for real,
  # so the hook gets the environment git gives one.
  def test_a_real_push_from_a_worktree_runs_the_gate_with_no_repository_named
    remote = File.join(@dir, "remote.git")
    git("init", "--quiet", "--bare", remote, chdir: @dir)
    worktree = File.join(@dir, "worktree")
    git("worktree", "add", "--quiet", worktree)
    hooks = File.join(@dir, "hooks")
    Dir.mkdir(hooks)
    File.write(File.join(hooks, "pre-push"), "#!/bin/sh\nexec #{HOOK} \"$@\"\n")
    File.chmod(0o755, File.join(hooks, "pre-push"))
    git("push", "--quiet", remote, "HEAD:refs/heads/trunk", chdir: worktree, hooks:)

    assert_equal gate, calls
    assert_empty gate_env.keys & GIT_PLACE.keys
    assert_equal @first, git("rev-parse", "refs/heads/trunk", chdir: remote)
  end

  # git runs a hook only if it is executable, and machines that run the
  # hook on a fresh checkout get the mode git recorded.
  def test_the_hook_is_tracked_as_executable
    listed, status = Open3.capture2(GIT_PLACE, "git", "ls-files", "--stage", "--", ".githooks/pre-push", chdir: ROOT)

    assert_predicate status, :success?
    assert_match(/\A100755 /, listed)
  end
end
