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
require_relative "../../tasks/clang_headers"
require_relative "../../tasks/setup"

# Tests tasks/setup.rb (Plans 061 and 073): what it installs for a person,
# for a CI runner, and for the gate, and the pre-push stub it writes. It
# runs in a real repository with a recorder in place of the command runner,
# so the tests assert on the commands it would run and need no stand-in for
# mise. That is what lets them run on every system, Windows included.
class TestSetup < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SETUP = File.join(ROOT, "tasks/setup.rb")
  REUSE = "reuse[charset-normalizer]==6.2.0"
  LIBCLANG = "libclang==18.1.1"
  MARKER = "# tokra pre-push stub, written by bin/setup"

  # The variables a git hook passes on, which would point the git commands
  # here at the repository whose hook runs these tests.
  GIT_PLACE = %w[GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX GIT_COMMON_DIR].to_h { |name| [name, nil] }.freeze

  # Git as these tests run it: no one's own configuration or hooks,
  # submodules cloned from a folder, which git otherwise refuses, and no
  # background maintenance, which these settings would otherwise replace
  # (test_helper.rb).
  GIT_ALONE = GIT_PLACE.merge(
    "GIT_CONFIG_GLOBAL" => File::NULL,
    "GIT_CONFIG_NOSYSTEM" => "1",
    "GIT_CONFIG_COUNT" => "2",
    "GIT_CONFIG_KEY_0" => "protocol.file.allow",
    "GIT_CONFIG_VALUE_0" => "always",
    "GIT_CONFIG_KEY_1" => "maintenance.auto",
    "GIT_CONFIG_VALUE_1" => "false"
  ).freeze

  # A command runner that records every command but git's, and answers each
  # as it is told, with success and no output where it is told nothing. Git
  # runs for real, in the test's repository, which is where the stub and the
  # submodule are.
  class Recorder
    attr_reader :calls, :envs

    def initialize(git)
      @git = git
      @calls = []
      @envs = {}
      @answers = {}
      @hooks = {}
    end

    # Runs the block when +command+, as one string, is run, before it
    # answers.
    def on(command, &block)
      @hooks[command] = block
    end

    # Makes +command+, as one string, print +output+ and end with +status+.
    def answer(command, output: "", status: 0)
      @answers[command] = Setup::Result.new(output:, status:)
    end

    def capture(*argv, chdir:, env: {})
      return @git.capture(*argv, chdir:, env:) if argv.first == "git"

      reply(argv, env)
    end

    def stream(*argv, chdir:, env: {})
      return @git.stream(*argv, chdir:, env:) if argv.first == "git"

      reply(argv, env).status
    end

    private def reply(argv, env)
      command = argv.join(" ")
      @calls << command
      @envs[command] = env
      @hooks[command]&.call
      @answers.fetch(command) { Setup::Result.new(output: "", status: 0) }
    end
  end

  def setup
    @dir = File.realpath(Dir.mktmpdir("setup"))
    @repo = File.join(@dir, "repo")
    @cache = File.join(@dir, "cache")
    Dir.mkdir(@repo)
    git("init", "--quiet", "--initial-branch", "trunk")
    @stub = File.join(@repo, ".git/hooks/pre-push")
    @git_env = GIT_ALONE
    @pip_missing = true
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  private def git(*, chdir: @repo)
    settings = %w[user.name=tokra user.email=tokra@localhost commit.gpgSign=false].flat_map { |setting| ["-c", setting] }
    printed, status = Open3.capture2e(GIT_ALONE, "git", *settings, *, chdir:)

    assert_predicate status, :success?, printed
    printed.strip
  end

  # The stand-in for what a person's own mise would say about its tools.
  private def recorder
    @recorder ||= Recorder.new(Setup::Shell.new(env: @git_env)).tap do |recorded|
      recorded.answer("mise ls --missing", output: "ruby  4.1.0-preview1  (missing)\n")
      recorded.answer("mise x -- bin/linux-env bundle check", status: 1)
      recorded.answer("mise x -- ruby bin/windows-env bundle check", status: 1)
    end
  end

  # Runs Setup in the repository, and returns its status. What it printed
  # is in @out and @err.
  private def run_setup(env = {}, *, host_os: "linux-gnu", root: @repo)
    @out = StringIO.new
    @err = StringIO.new
    environment = { "HOME" => @dir, "XDG_CACHE_HOME" => @cache }.merge(env)
    Setup.new(root:, env: environment, runner: recorder, out: @out, err: @err, host_os:).call(*)
  end

  # What the recorder was called with, one line a call.
  private def calls
    recorder.calls
  end

  # The commands Setup printed as it ran them, without their "+ ".
  private def printed
    @out.string.lines(chomp: true).filter_map { |line| line.delete_prefix("+ ") if line.start_with?("+ ") }
  end

  private def installed(name, version)
    recorder.answer("mise x -- python -m pip show #{name}", output: "Name: #{name}\nVersion: #{version}\n")
  end

  def test_for_a_person_it_installs_the_tools_the_bundle_the_commit_hook_and_the_docs
    status = run_setup

    assert_equal 0, status, @err.string
    assert_equal [
      "mise ls --missing",
      "mise install",
      "mise x -- python -m pip show reuse",
      "mise x -- python -m pip install --quiet #{REUSE}",
      "mise x -- bin/linux-env bundle check",
      "mise x -- bin/linux-env bundle install",
      "mise x -- pre-commit install",
      "mise x -- bundle exec rake rdoc",
    ], calls
  end

  # A runner keeps vendor/bundle between runs, commits nothing, and reads
  # no documentation.
  def test_for_a_ci_runner_it_installs_the_bundle_as_ci_does_and_skips_the_commit_hook_and_the_docs
    status = run_setup({ "CI" => "true" })

    assert_equal 0, status, @err.string
    assert_equal [
      "mise ls --missing",
      "mise install",
      "mise x -- python -m pip show reuse",
      "mise x -- python -m pip install --quiet #{REUSE}",
      "mise x -- bundle --version",
      "mise x -- bundle config set --local path vendor/bundle",
      "mise x -- bundle config set --local frozen true",
      "mise x -- bin/linux-env bundle check",
      "mise x -- bin/linux-env bundle install",
    ], calls
  end

  # CI is only the string "true", as bin/setup always read it.
  def test_a_ci_that_is_not_true_is_a_person
    run_setup({ "CI" => "false" })

    assert_includes calls, "mise x -- pre-commit install"
    refute_includes calls, "mise x -- bundle --version"
  end

  # A runner's vendor/bundle can hold a gem's specification without its
  # files, as an install cut short leaves it; when that gem is Bundler, no
  # bundle command starts. The folder then goes, for the install to make
  # again.
  def test_for_a_ci_runner_it_removes_a_bundle_that_bundler_cannot_start_from
    recorder.answer("mise x -- bundle --version", status: 1)
    FileUtils.mkdir_p(File.join(@repo, "vendor/bundle/specifications"))

    status = run_setup({ "CI" => "true" })

    assert_equal 0, status, @err.string
    refute_path_exists File.join(@repo, "vendor/bundle")
    assert_includes printed, "rm -rf vendor/bundle"
    assert_equal "mise x -- bin/linux-env bundle install", calls.last
  end

  # A bundle Bundler starts from is the runner's from its last run, and
  # stays.
  def test_for_a_ci_runner_it_keeps_a_bundle_that_bundler_starts_from
    FileUtils.mkdir_p(File.join(@repo, "vendor/bundle/specifications"))

    status = run_setup({ "CI" => "true" })

    assert_equal 0, status, @err.string
    assert_path_exists File.join(@repo, "vendor/bundle/specifications")
  end

  # A runner with no bundle yet has nothing to remove, and says nothing.
  def test_for_a_ci_runner_with_no_bundle_it_removes_nothing_and_says_so_to_no_one
    recorder.answer("mise x -- bundle --version", status: 1)

    run_setup({ "CI" => "true" })

    refute_includes printed, "rm -rf vendor/bundle"
  end

  # The settings go in .bundle/config, where a runner's own from its last
  # run holds them already.
  def test_for_a_ci_runner_it_leaves_a_bundle_configured_as_ci_does_alone
    FileUtils.mkdir_p(File.join(@repo, ".bundle"))
    File.write(File.join(@repo, ".bundle/config"), %(---\nBUNDLE_FROZEN: "true"\nBUNDLE_PATH: "vendor/bundle"\n))

    run_setup({ "CI" => "true" })

    refute(calls.any? { |call| call.include?("bundle config") })
  end

  # .githooks/pre-push runs tasks/setup.rb --gate before every push. It
  # installs what the gate needs and nothing only a person's clone wants,
  # so a push writes no hook and spends no time on the documentation.
  def test_for_the_gate_it_installs_the_tools_and_the_bundle_and_leaves_the_hooks_and_the_docs
    status = run_setup({}, "--gate")

    assert_equal 0, status, @err.string
    assert_equal [
      "mise ls --missing",
      "mise install",
      "mise x -- python -m pip show reuse",
      "mise x -- python -m pip install --quiet #{REUSE}",
      "mise x -- bin/linux-env bundle check",
      "mise x -- bin/linux-env bundle install",
    ], calls
    refute_path_exists @stub
  end

  def test_for_the_gate_on_a_ci_runner_it_installs_the_bundle_as_ci_does
    status = run_setup({ "CI" => "true" }, "--gate")

    assert_equal 0, status, @err.string
    assert_equal [
      "mise ls --missing",
      "mise install",
      "mise x -- python -m pip show reuse",
      "mise x -- python -m pip install --quiet #{REUSE}",
      "mise x -- bundle --version",
      "mise x -- bundle config set --local path vendor/bundle",
      "mise x -- bundle config set --local frozen true",
      "mise x -- bin/linux-env bundle check",
      "mise x -- bin/linux-env bundle install",
    ], calls
    refute_path_exists @stub
  end

  def test_an_argument_it_does_not_know_stops_it_before_it_installs_anything
    status = run_setup({}, "--gtae")

    assert_equal 2, status
    assert_includes @err.string.lines(chomp: true), "usage: bin/setup [--gate]"
    assert_empty calls
  end

  # Nothing is missing on a machine that has been set up, and then it asks
  # what it needs to know and runs, and prints, nothing.
  def test_where_nothing_is_missing_it_runs_and_prints_nothing
    recorder.answer("mise ls --missing")
    installed("reuse", "6.2.0")
    recorder.answer("mise x -- bin/linux-env bundle check")

    status = run_setup({}, "--gate")

    assert_equal 0, status, @err.string
    assert_equal ["mise ls --missing", "mise x -- python -m pip show reuse", "mise x -- bin/linux-env bundle check"], calls
    assert_empty @out.string
    assert_empty @err.string
  end

  # A bundle that is not complete is installed, which a changed
  # Gemfile.lock makes work.
  def test_a_bundle_that_is_not_complete_is_installed_and_the_command_printed
    recorder.answer("mise ls --missing")
    installed("reuse", "6.2.0")

    run_setup({}, "--gate")

    assert_equal ["+ mise x -- bin/linux-env bundle install"], @out.string.lines(chomp: true)
  end

  # What it installs it prints, as the command, before it runs it.
  def test_it_prints_each_command_that_changes_something_before_running_it
    run_setup({}, "--gate")

    assert_equal [
      "mise install",
      "mise x -- python -m pip install --quiet #{REUSE}",
      "mise x -- bin/linux-env bundle install",
    ], printed
  end

  # reuse at another version than CI's is installed again.
  def test_the_reuse_tool_at_another_version_is_installed_again
    installed("reuse", "6.1.0")

    run_setup({}, "--gate")

    assert_includes calls, "mise x -- python -m pip install --quiet #{REUSE}"
  end

  # A failure stops it there, with the command, its status, and whatever
  # the command printed, which a command it streams has printed already.
  def test_a_failing_command_stops_it_with_the_command_and_its_status
    recorder.answer("mise install", status: 3)

    status = run_setup

    assert_equal 3, status
    assert_equal ["mise ls --missing", "mise install"], calls
    assert_includes @err.string, "setup: mise install failed with status 3"
  end

  # pre-commit refuses to install under core.hooksPath and would end the
  # script there, before the docs.
  def test_where_core_hooks_path_is_set_it_leaves_the_commit_hook_and_says_so
    hooks = File.join(@dir, "my-hooks")
    @git_env = GIT_ALONE.merge("GIT_CONFIG_KEY_1" => "core.hooksPath", "GIT_CONFIG_VALUE_1" => hooks)

    status = run_setup

    assert_equal 0, status, @err.string
    refute_includes calls, "mise x -- pre-commit install"
    assert_equal "mise x -- bundle exec rake rdoc", calls.last
    said = @err.string.lines(chomp: true)

    assert_includes said, "core.hooksPath is set, so git runs the hooks in #{hooks}, not this clone's:"
    assert_includes said, "git push runs .githooks/pre-push only if the pre-push hook there runs #{@stub},"
    assert_includes said, "and pre-commit's hook is not installed."
  end

  # Windows sets OS for every process. A repository of Windows' gets the
  # pins Setup reads.
  WINDOWS = { "OS" => "Windows_NT" }.freeze

  private def as_windows
    File.write(File.join(@repo, "mise.toml"), %([tools]\r\nruby = "4.0.9"\r\nrust = "1.2.3"\r\n))
  end

  # On Windows, Rust's GNU host toolchain for RubyInstaller's MinGW Ruby,
  # with CI's components, and libclang and clang's own headers for
  # bindgen; the bundle installs with what bin/windows-env sets, and there
  # is no commit hook, since mise installs pre-commit there only through
  # pipx.
  def test_on_windows_it_adds_the_gnu_toolchain_libclang_and_clang_s_headers_and_installs_the_bundle_through_windows_env
    as_windows
    status = run_setup(WINDOWS, host_os: "mingw-ucrt")

    assert_equal 0, status, @err.string
    assert_equal [
      "mise ls --missing",
      "mise install",
      "mise x -- rustup toolchain list",
      "mise x -- rustup toolchain install 1.2.3-x86_64-pc-windows-gnu --profile minimal --component clippy --component rustfmt",
      "mise x -- python -m pip show reuse",
      "mise x -- python -m pip install --quiet #{REUSE}",
      "mise x -- python -m pip show libclang",
      "mise x -- python -m pip install --quiet #{LIBCLANG}",
      "mise x -- ruby bin/clang-headers",
      "mise x -- ruby bin/windows-env bundle check",
      "mise x -- ruby bin/windows-env bundle install",
      "mise x -- bundle exec rake rdoc",
    ], calls
  end

  # Neither ruby file runs through a shell, so a person's cmd.exe or
  # PowerShell, which has no sh on its PATH, runs them as it runs the rest,
  # and setup gives them the environment as it is.
  def test_on_windows_no_command_needs_a_shell_or_an_environment_of_its_own
    as_windows

    run_setup(WINDOWS.merge("PATH" => "C:\\Windows"), "--gate", host_os: "mingw-ucrt")

    refute_includes recorder.calls.flat_map(&:split), "sh"
    assert_equal({}, recorder.envs.values.reduce({}) { |all, env| all.merge(env) })
  end

  def test_on_windows_a_ci_runner_installs_the_bundle_as_ci_does_through_windows_env
    as_windows
    status = run_setup(WINDOWS.merge("CI" => "true"), host_os: "mingw-ucrt")

    assert_equal 0, status, @err.string
    assert_equal [
      "mise ls --missing",
      "mise install",
      "mise x -- rustup toolchain list",
      "mise x -- rustup toolchain install 1.2.3-x86_64-pc-windows-gnu --profile minimal --component clippy --component rustfmt",
      "mise x -- python -m pip show reuse",
      "mise x -- python -m pip install --quiet #{REUSE}",
      "mise x -- python -m pip show libclang",
      "mise x -- python -m pip install --quiet #{LIBCLANG}",
      "mise x -- ruby bin/clang-headers",
      "mise x -- bundle --version",
      "mise x -- bundle config set --local path vendor/bundle",
      "mise x -- bundle config set --local frozen true",
      "mise x -- ruby bin/windows-env bundle check",
      "mise x -- ruby bin/windows-env bundle install",
    ], calls
  end

  # With the toolchain, its components, libclang, and the headers in
  # place, a Windows setup runs the bundle's install and nothing else.
  def test_on_windows_what_is_in_place_is_left_alone
    as_windows
    toolchain = "1.2.3-x86_64-pc-windows-gnu"
    recorder.answer("mise ls --missing")
    recorder.answer("mise x -- rustup toolchain list", output: "stable-x86_64-pc-windows-msvc (default)\n#{toolchain}\n")
    components = %w[cargo clippy rustfmt rustc].map { |name| "#{name}-#{toolchain}\n" }.join
    recorder.answer("mise x -- rustup component list --installed --toolchain #{toolchain}", output: components)
    installed("reuse", "6.2.0")
    installed("libclang", "18.1.1")
    headers = File.join(ClangHeaders.directory({ "XDG_CACHE_HOME" => @cache }), "include")
    FileUtils.mkdir_p(headers)
    FileUtils.touch(File.join(headers, "stddef.h"))

    status = run_setup(WINDOWS, "--gate", host_os: "mingw-ucrt")

    assert_equal 0, status, @err.string
    assert_equal ["mise x -- ruby bin/windows-env bundle install"], printed
  end

  # A toolchain installed without a component CI has is installed again.
  def test_on_windows_a_toolchain_that_lacks_a_component_is_installed_again
    as_windows
    toolchain = "1.2.3-x86_64-pc-windows-gnu"
    recorder.answer("mise x -- rustup toolchain list", output: "#{toolchain}\n")
    recorder.answer("mise x -- rustup component list --installed --toolchain #{toolchain}", output: "cargo-#{toolchain}\nclippy-#{toolchain}\n")

    run_setup(WINDOWS, "--gate", host_os: "mingw-ucrt")

    assert_includes calls, "mise x -- rustup toolchain install #{toolchain} --profile minimal --component clippy --component rustfmt"
  end

  # ci.yml's toolchain step installs these components on every system.
  def test_the_gnu_toolchain_gets_ci_s_components
    workflow = YAML.safe_load_file(File.join(ROOT, ".github/workflows/ci.yml"))
    step = workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps") }
      .find { |each| each["uses"].to_s.start_with?("dtolnay/rust-toolchain@") }
    components = step.fetch("with").fetch("components").split(/,\s*/)

    assert_equal %w[clippy rustfmt], components
    assert_equal components, Setup::COMPONENTS
  end

  def test_the_reuse_tool_is_ci_s
    workflow = YAML.safe_load_file(File.join(ROOT, ".github/workflows/ci.yml"))
    step = workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps") }
      .find { |each| each["name"] == "Install the REUSE tool" }

    assert_includes step.fetch("run"), %("#{REUSE}")
    assert_equal REUSE, Setup::REUSE
  end

  # rake sync:tauri reads vendor/tauri, which a plain clone leaves empty.
  def test_it_checks_out_a_submodule_a_clone_left_empty
    git("commit", "--quiet", "--allow-empty", "--message", "the first")
    library = File.join(@dir, "library")
    Dir.mkdir(library)
    git("init", "--quiet", "--initial-branch", "trunk", chdir: library)
    File.write(File.join(library, "inside"), "the submodule's file")
    git("add", "inside", chdir: library)
    git("commit", "--quiet", "--message", "inside", chdir: library)
    git("submodule", "--quiet", "add", library, "vendor/library")
    git("commit", "--quiet", "--message", "the submodule")
    git("submodule", "--quiet", "deinit", "--force", "vendor/library")

    refute_path_exists File.join(@repo, "vendor/library/inside")
    status = run_setup({}, "--gate")

    assert_equal 0, status, @err.string
    assert_equal "the submodule's file", File.read(File.join(@repo, "vendor/library/inside"))
    assert_includes printed, "git submodule update --init"
  end

  # A checkout with its submodules in place runs nothing for them.
  def test_a_checkout_with_its_submodules_in_place_prints_nothing_for_them
    run_setup({}, "--gate")

    refute_includes printed, "git submodule update --init"
  end

  # What it writes is a stub that hands off to the hook of whichever
  # worktree pushes (test_pre_push_hook.rb runs it).
  def test_the_stub_it_writes_hands_off_to_the_hook_of_the_worktree_that_pushes
    run_setup

    assert_equal <<~STUB, File.binread(@stub)
      #!/bin/sh
      #{MARKER}
      hook="$(git rev-parse --show-toplevel)/.githooks/pre-push"
      [ -x "$hook" ] || exit 0
      exec "$hook" "$@"
    STUB
    assert_predicate File.stat(@stub), :executable? unless Gem.win_platform?
  end

  # Run from a worktree, it still writes the one stub every worktree's
  # push finds: git reads hooks from the clone's shared folder only.
  def test_run_from_a_worktree_it_writes_the_stub_into_the_clones_shared_hooks
    git("commit", "--quiet", "--allow-empty", "--message", "the first")
    worktree = File.join(@dir, "worktree")
    git("worktree", "add", "--quiet", worktree)
    status = run_setup(root: worktree)

    assert_equal 0, status, @err.string
    assert_path_exists @stub
    assert_empty Dir.glob(File.join(@repo, ".git/worktrees/*/hooks/*"))
  end

  def test_running_it_again_leaves_the_same_stub
    run_setup
    first = File.read(@stub)
    status = run_setup

    assert_equal 0, status, @err.string
    assert_equal first, File.read(@stub)
    assert_includes first.lines(chomp: true), MARKER
  end

  # A later setup may change the stub, and has to reach clones that hold
  # an earlier one.
  def test_a_stub_of_its_own_from_an_earlier_version_is_replaced
    run_setup
    current = File.read(@stub)
    File.write(@stub, "#!/bin/sh\n#{MARKER}\nexit 0\n")
    status = run_setup

    assert_equal 0, status, @err.string
    assert_equal current, File.read(@stub)
  end

  # A clone made from an empty template has no hooks folder.
  def test_a_clone_with_no_hooks_folder_gets_one
    FileUtils.rm_rf(File.dirname(@stub))
    status = run_setup

    assert_equal 0, status, @err.string
    assert_path_exists @stub
  end

  # Someone's own hook there, whatever it mentions, is theirs to keep.
  def test_a_hook_that_is_not_its_own_is_left_alone_and_said_so
    own = "#!/bin/sh\necho '#{MARKER}' # this line only quotes the marker\nexit 0\n"
    FileUtils.mkdir_p(File.dirname(@stub))
    File.write(@stub, own)
    status = run_setup

    assert_equal 0, status, @err.string
    assert_equal own, File.read(@stub)
    assert_includes @err.string, "#{@stub} exists and is not Tokra's; leaving it, so git push will not run .githooks/pre-push."
  end

  # Two setups at once in one cache break mise's download store, so what
  # the file installs itself goes under a lock on a file in the cache
  # folder: while mise install runs, nobody else can take it. (mise x
  # installs the missing tools before the file starts, which no lock of
  # the file's covers.)
  def test_the_tools_install_under_a_lock_on_a_file_in_the_cache_folder
    taken = nil
    recorder.on("mise install") do
      File.open(File.join(@cache, "tokra/setup.lock"), File::RDWR | File::CREAT) do |other|
        taken = other.flock(File::LOCK_EX | File::LOCK_NB)
      end
    end

    run_setup({}, "--gate")

    assert_equal false, taken
  end

  # A setup that finds the lock held waits for it, and then installs.
  def test_a_setup_waits_for_a_lock_another_setup_holds
    lock = File.join(@cache, "tokra/setup.lock")
    FileUtils.mkdir_p(File.dirname(lock))
    held = File.open(lock, File::RDWR | File::CREAT)
    held.flock(File::LOCK_EX)
    worker = Thread.new { run_setup({}, "--gate") }
    sleep 1

    assert_empty calls
    held.flock(File::LOCK_UN)

    assert_equal 0, worker.value
    assert_includes calls, "mise install"
  ensure
    held&.close
  end

  # Where XDG_CACHE_HOME is unset, the platform's own cache folder.
  def test_the_lock_is_in_the_platforms_cache_folder_where_xdg_cache_home_is_unset
    {
      "linux-gnu" => [{ "HOME" => @dir }, File.join(@dir, ".cache")],
      "darwin27" => [{ "HOME" => @dir }, File.join(@dir, "Library/Caches")],
      "mingw-ucrt" => [{ "HOME" => @dir, "LOCALAPPDATA" => File.join(@dir, "Local"), "OS" => "Windows_NT" }, File.join(@dir, "Local")],
    }.each do |host_os, (env, cache)|
      @recorder = nil
      @out = StringIO.new
      as_windows
      Setup.new(root: @repo, env:, runner: recorder, out: @out, err: StringIO.new, host_os:).call("--gate")

      assert_path_exists File.join(cache, "tokra/setup.lock"), host_os
    end
  end

  # What a person types is two lines, which bin/setup holds, with the
  # folder it runs in and the arguments it was given.
  def test_bin_setup_holds_the_two_line_command
    lines = File.read(File.join(ROOT, "bin/setup")).lines(chomp: true).reject { |line| line.empty? || line.start_with?("#") }

    assert_equal [
      %(cd "$(dirname "$0")/.." || exit 1),
      "mise trust -q mise.toml",
      %(exec mise x -- ruby tasks/setup.rb "$@"),
    ], lines
  end

  # cmd.exe runs bin/setup.cmd where a person types bin/setup.
  def test_bin_setup_cmd_holds_the_same_two_lines_for_cmd
    lines = File.read(File.join(ROOT, "bin/setup.cmd")).lines(chomp: true).reject { |line| line.empty? || line.downcase.start_with?("rem") }

    assert_equal [
      "@echo off",
      %(cd /d "%~dp0.."),
      "mise trust -q mise.toml",
      "mise x -- ruby tasks/setup.rb %*",
    ], lines
  end

  def test_there_is_no_powershell_twin
    refute_path_exists File.join(ROOT, "bin/setup.ps1")
  end

  # The hook runs bin/setup as git's sh does, and a clone's checkout keeps
  # the mode git recorded.
  def test_bin_setup_is_tracked_as_executable
    skip "Windows records no executable bit" if Gem.win_platform?

    listed, status = Open3.capture2(GIT_PLACE, "git", "ls-files", "--stage", "--", "bin/setup", chdir: ROOT)

    assert_predicate status, :success?
    assert_equal %w[100755], listed.lines.map { |line| line.split.first }
  end

  # Its version is ClangHeaders', which unpacks the headers of the libclang
  # wheel's version.
  def test_the_libclang_it_installs_is_the_version_clang_headers_unpacks
    assert_equal ClangHeaders::VERSION, Setup::LIBCLANG_VERSION
    assert_equal LIBCLANG, "libclang==#{Setup::LIBCLANG_VERSION}"
  end

  # It runs before the bundle exists, so it loads what Ruby ships. The
  # list is pinned: Gem::Specification.default_gem? misleads under Bundler.
  DEFAULT_GEMS = %w[fileutils open3 shellwords].freeze

  def test_it_requires_only_default_gems
    required = File.read(SETUP).scan(/^require "(\w+)"/).flatten

    assert_equal DEFAULT_GEMS, required.sort
  end

  # And it loads in a Ruby with no gems at all, started outside the
  # repository, where no Gemfile and no bundle can help it.
  def test_it_loads_in_a_ruby_with_no_gems_outside_the_repository
    output, status = Open3.capture2e(Gem.ruby, "--disable-gems", "-e", "require ARGV.fetch(0); puts Setup::REUSE", SETUP, chdir: @dir)

    assert_predicate status, :success?, output
    assert_equal "#{REUSE}\n", output
  end

  # The one place a shell could be asked for is a command string, so none
  # of its commands is one.
  def test_its_commands_are_never_given_to_a_shell
    source = File.read(SETUP)

    refute_match(/`|%x|\bexec\(|\bsystem\("|\bspawn\("|Kernel\.system\("/, source)
  end

  # The real runner, with a real command: Ruby itself, which every system
  # has, in the array form.
  def test_the_runner_captures_a_commands_output_and_status
    shell = Setup::Shell.new(env: { "SETUP_TEST" => "seen" })
    result = shell.capture(Gem.ruby, "-e", "print ENV.fetch('SETUP_TEST'); warn 'and this'; exit 4", chdir: @dir)

    assert_equal 4, result.status
    assert_includes result.output, "seen"
    assert_includes result.output, "and this"
    refute_predicate result, :success?
  end

  def test_the_runner_streams_a_command_in_the_folder_it_is_given
    shell = Setup::Shell.new(env: {})
    status = shell.stream(Gem.ruby, "-e", "File.write('here', Dir.pwd); exit 5", chdir: @dir)

    assert_equal 5, status
    assert_equal @dir, File.realpath(File.read(File.join(@dir, "here")))
  end

  def test_the_runner_says_127_of_a_command_that_is_not_there
    shell = Setup::Shell.new(env: {})

    assert_equal 127, shell.capture("tokra-no-such-command", chdir: @dir).status
    assert_equal 127, shell.stream("tokra-no-such-command", chdir: @dir)
  end

  def test_the_runner_keeps_stdout_and_stderr_apart_when_asked
    answer = Setup::Shell.new(env: { "SETUP_TEST" => "seen" }).capture_separately(
      Gem.ruby, "-e", %q(print ENV.fetch("SETUP_TEST"); warn "and this"; exit 3), chdir: @dir
    )

    assert_equal "seen", answer.output
    assert_equal "and this", answer.error.strip
    assert_equal 3, answer.status
  end

  def test_the_runner_says_127_of_a_command_that_is_not_there_when_asked_apart
    answer = Setup::Shell.new(env: {}).capture_separately("tokra-no-such-command", chdir: @dir)

    assert_equal 127, answer.status
    assert_includes answer.error, "tokra-no-such-command"
    assert_empty answer.output
  end
end
