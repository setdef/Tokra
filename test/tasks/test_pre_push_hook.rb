# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "open3"
require "stringio"
require "tmpdir"
require "yaml"
require_relative "../../tasks/setup"

# Tests .githooks/pre-push (Plan 061): which pushes run the gate, which it
# refuses, that it sets Tokra up first, and that it runs the gate as
# ci.yml does, with mise's tools. Each test hands the real hook the lines
# git would, in a real repository, or pushes through it with a real git
# push, with stand-ins for tasks/setup.rb, mise, bundle, and xvfb-run that log
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

  # A mise that logs its arguments and runs what mise x is given, as the
  # real one does once its tools are installed.
  MISE = <<~'SH'
    #!/bin/sh
    { printf mise; for a in "$@"; do printf ' %s' "$a"; done; printf '\n'; } >> "$(dirname "$0")/log"
    [ "$1" = x ] && [ "$2" = -- ] || exit 0
    shift 2
    exec "$@"
  SH

  # A tasks/setup.rb that logs its arguments into LOG, says something, and
  # exits with SETUP_STATUS, or 0.
  SETUP = <<~RUBY
    File.open(ENV.fetch("LOG"), "a") { |log| log.puts(["setup", *ARGV].join(" ")) }
    puts "setup's last words"
    exit Integer(ENV.fetch("SETUP_STATUS", "0"))
  RUBY

  # A bin/windows-env, which is a Ruby file that the hook starts through
  # mise x -- ruby, as it does on Windows: it logs its arguments, keeps
  # its environment, and exits with GATE_STATUS, or 0.
  WINDOWS_ENV = <<~'RUBY'
    File.open(ENV.fetch("LOG"), "a") { |log| log.puts(["windows-env", *ARGV].join(" ")) }
    File.write(File.join(File.dirname(ENV.fetch("LOG")), "env"), ENV.map { |name, value| "#{name}=#{value}\n" }.join)
    exit Integer(ENV.fetch("GATE_STATUS", "0"))
  RUBY

  # The variables a git hook passes on, which would point the git commands
  # here at the repository whose hook runs these tests.
  GIT_PLACE = %w[GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX GIT_COMMON_DIR].to_h { |name| [name, nil] }.freeze

  # Git as these tests run it: no one's own configuration or hooks.
  GIT_ALONE = GIT_PLACE.merge("GIT_CONFIG_GLOBAL" => File::NULL, "GIT_CONFIG_NOSYSTEM" => "1").freeze

  LINUX = RbConfig::CONFIG["host_os"].include?("linux")

  def setup
    skip "Ruby on Windows cannot run the hook or its stand-ins as commands; OS=Windows_NT tests its Windows branch elsewhere" if Gem.win_platform?

    @dir = File.realpath(Dir.mktmpdir("pre_push"))
    @bin = File.join(@dir, "bin")
    Dir.mkdir(@bin)
    { "bundle" => LOGGER, "xvfb-run" => LOGGER, "mise" => MISE }.each do |name, script|
      File.write(File.join(@bin, name), script)
      File.chmod(0o755, File.join(@bin, name))
    end
    @repo = File.join(@dir, "repo")
    Dir.mkdir(@repo)
    git("init", "--quiet", "--initial-branch", "trunk")
    FileUtils.mkdir_p(File.join(@repo, "bin"))
    FileUtils.mkdir_p(File.join(@repo, "tasks"))
    { "bin/linux-env" => LINUX_ENV, "tasks/setup.rb" => SETUP }.each do |path, script|
      File.write(File.join(@repo, path), script)
      File.chmod(0o755, File.join(@repo, path))
    end
    # The hook writes what tasks/setup.rb prints under tmp/, which git ignores.
    File.write(File.join(@repo, ".gitignore"), "/tmp/\n")
    git("add", "bin/linux-env", "tasks/setup.rb", ".gitignore")
    @first = commit("one")
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  private def env(extra = {})
    GIT_ALONE.merge("PATH" => "#{@bin}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}", "OS" => nil, "LOG" => File.join(@bin, "log"))
      .merge(extra)
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

  # The environment the gate's command was given. A variable whose value
  # spans lines, as an exported shell function's does, goes on over lines
  # that name no variable; only a line that begins one is read.
  private def gate_env
    File.readlines(File.join(@bin, "env"), chomp: true).grep(/\A[A-Za-z_][A-Za-z0-9_]*=/).to_h { |line| line.split("=", 2) }
  end

  # The calls a push that runs the gate makes: setup, which is bin/setup's
  # two lines with --gate, then the gate through mise, which runs the
  # stand-in that logs it.
  private def gate
    command = LINUX ? "xvfb-run --auto-servernum dbus-run-session -- bundle exec rake" : "bundle exec rake"
    [*setup_calls, "mise x -- #{'bin/linux-env ' if LINUX}#{command}", command]
  end

  private def setup_calls
    ["mise trust -q mise.toml", "mise x -- ruby tasks/setup.rb --gate", "setup --gate"]
  end

  private def ci_step(name)
    workflow = YAML.safe_load_file(File.join(ROOT, ".github/workflows/ci.yml"))
    workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps") }.find { |step| step["name"] == name }.fetch("run")
  end

  private def ci_env(name)
    workflow = YAML.safe_load_file(File.join(ROOT, ".github/workflows/ci.yml"))
    workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps") }.find { |step| step["name"] == name }.fetch("env")
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

  # The hook may be all that runs in a fresh checkout, as on a CI runner, so
  # it sets Tokra up itself, and only once the push is one it will gate.
  def test_it_sets_tokra_up_for_the_gate_before_running_it
    output, status = push("refs/heads/trunk #{@first} refs/heads/trunk #{ZERO}")

    assert_predicate status, :success?, output
    assert_equal setup_calls, calls.first(3)
    assert_includes File.read(File.join(@repo, "tmp/pre-push-setup.log")), "setup's last words"
  end

  # A setup that fails would leave the gate to fail for a reason that is
  # not the push's, so the push stops there, with what setup said last.
  def test_a_setup_that_fails_refuses_the_push_before_the_gate_and_shows_what_it_said
    output, status = push("refs/heads/trunk #{@first} refs/heads/trunk #{ZERO}", extra: { "SETUP_STATUS" => "3" })

    assert_equal 3, status.exitstatus, output
    assert_equal setup_calls, calls
    assert_includes output, "setup's last words"
    assert_includes output, "pre-push: tasks/setup.rb --gate failed with status 3; all it printed is in tmp/pre-push-setup.log."
  end

  # Nothing activates mise where the hook runs from a fresh checkout, so
  # the gate runs with the tools mise.toml pins through mise x.
  def test_the_hook_runs_the_gate_as_ci_runs_it_on_linux_and_elsewhere_with_mise_s_tools
    hook = File.read(HOOK)

    assert_includes hook, "    exec mise x -- bin/linux-env #{ci_step('Run the gate under X11')} ;;\n"
    assert_includes hook, "  *) exec mise x -- #{ci_step('Run the gate')} ;;\n"
  end

  # Windows sets OS for every process, and MSYS2's bash passes it on. There
  # the gate runs as ci.yml's Windows job runs it: through bin/windows-env,
  # which sets what the job's earlier steps set for Rust and bindgen, with
  # the step's own variables for Windows.
  def test_on_windows_the_gate_runs_through_windows_env_with_ci_s_variables
    FileUtils.mkdir_p(File.join(@repo, "bin"))
    File.write(File.join(@repo, "bin/windows-env"), WINDOWS_ENV)
    git("add", "bin/windows-env")
    git("commit", "--quiet", "--message", "windows-env")
    head = git("rev-parse", "HEAD")
    output, status = push("refs/heads/trunk #{head} refs/heads/trunk #{@first}", extra: { "OS" => "Windows_NT" })

    assert_predicate status, :success?, output
    assert_equal [*setup_calls, "mise x -- ruby bin/windows-env bundle exec rake", "windows-env bundle exec rake"], calls
    step = ci_env("Run the gate")

    assert_equal step.fetch("A")[/'Windows' && '(.*?)'/, 1], gate_env["A"]
    assert_equal step.fetch("RUST_BACKTRACE")[/'Windows' && '(.*?)'/, 1], gate_env["RUST_BACKTRACE"]
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
    FileUtils.mkdir_p(File.join(@repo, "tmp"))
    File.write(File.join(@repo, "tmp/built"), "build output")
    output, status = push("refs/heads/trunk #{@first} refs/heads/trunk #{ZERO}")

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

  # tasks/setup.rb writes the stub every worktree's push runs, which hands
  # off to the hook of the worktree that pushes.
  private def write_stub
    Setup.new(root: @repo, env: {}, runner: Setup::Shell.new(env: GIT_ALONE), out: StringIO.new, err: StringIO.new).install_pre_push_stub
  end

  def test_the_stub_setup_writes_runs_the_hook_of_whichever_worktree_pushes
    hook = "#!/bin/sh\nprintf '%s\\n' \"$(pwd -P)\" \"$@\" > \"$(git rev-parse --show-toplevel)/ran\"\n"
    FileUtils.mkdir_p(File.join(@repo, ".githooks"))
    File.write(File.join(@repo, ".githooks/pre-push"), hook)
    File.chmod(0o755, File.join(@repo, ".githooks/pre-push"))
    git("add", ".githooks/pre-push")
    git("commit", "--quiet", "--message", "the hook")
    stub = write_stub
    worktree = File.join(@dir, "worktree")
    git("worktree", "add", "--quiet", worktree)

    [@repo, worktree].each do |pushing|
      output, status = Open3.capture2e(env, stub, "origin", "git@example.com:tokra.git", chdir: pushing)

      assert_predicate status, :success?, output
      assert_equal [File.realpath(pushing), "origin", "git@example.com:tokra.git"], File.readlines(File.join(pushing, "ran"), chomp: true)
    end
  end

  def test_the_stub_passes_a_push_from_a_commit_that_has_no_hook
    stub = write_stub
    output, status = Open3.capture2e(env, stub, "origin", "git@example.com:tokra.git", chdir: @repo)

    assert_predicate status, :success?, output
    assert_empty calls
  end

  # The whole path, for real: setup's stub, the hook this repository ships,
  # and a git push, which hands the hook its refs on standard input.
  # Without them the hook sees nothing to gate and lets the push through.
  def test_a_real_push_through_setups_stub_runs_the_shipped_hook_its_setup_and_the_gate
    FileUtils.mkdir_p(File.join(@repo, ".githooks"))
    FileUtils.cp(HOOK, File.join(@repo, ".githooks/pre-push"))
    git("add", ".githooks/pre-push")
    git("commit", "--quiet", "--message", "the shipped hook")
    write_stub
    remote = File.join(@dir, "remote.git")
    git("init", "--quiet", "--bare", remote, chdir: @dir)
    git("push", "--quiet", remote, "HEAD:refs/heads/trunk", hooks: File.join(@repo, ".git/hooks"))

    assert_equal gate, calls
    assert_equal git("rev-parse", "HEAD"), git("rev-parse", "refs/heads/trunk", chdir: remote)
  end
end
