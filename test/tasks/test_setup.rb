# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "open3"
require "tmpdir"
require "yaml"

# Tests bin/setup (Plan 061): what it installs for a person and for a CI
# runner, and the pre-push stub it writes. Each test runs the real script
# in a real repository, with a stand-in for mise that logs its arguments.
class TestSetup < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SETUP = File.join(ROOT, "bin/setup")
  REUSE = "reuse[charset-normalizer]==6.2.0"
  LIBCLANG = "libclang==18.1.1"
  MARKER = "# tokra pre-push stub, written by bin/setup"

  # A mise that logs its arguments, one line a call, and runs nothing.
  MISE = <<~'SH'
    #!/bin/sh
    { printf '%s' mise; for a in "$@"; do printf ' %s' "$a"; done; printf '\n'; } >> "$(dirname "$0")/log"
  SH

  # The real hook, and the gate a stand-in for bundle or xvfb-run logs.
  REAL_HOOK = File.join(ROOT, ".githooks/pre-push")
  GATE = <<~'SH'
    #!/bin/sh
    { printf '%s' "$(basename "$0")"; for a in "$@"; do printf ' %s' "$a"; done; printf '\n'; } >> "$(dirname "$0")/log"
  SH

  # A hook that records the folder it ran in and its arguments.
  HOOK = <<~'SH'
    #!/bin/sh
    printf '%s\n' "$(pwd -P)" "$@" > "$(git rev-parse --show-toplevel)/ran"
  SH

  # The variables a git hook passes on, which would point the git commands
  # here at the repository whose hook runs these tests.
  GIT_PLACE = %w[GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX GIT_COMMON_DIR].to_h { |name| [name, nil] }.freeze

  # Git as these tests run it: no one's own configuration or hooks, and
  # submodules cloned from a folder, which git otherwise refuses.
  GIT_ALONE = GIT_PLACE.merge(
    "GIT_CONFIG_GLOBAL" => File::NULL,
    "GIT_CONFIG_NOSYSTEM" => "1",
    "GIT_CONFIG_COUNT" => "1",
    "GIT_CONFIG_KEY_0" => "protocol.file.allow",
    "GIT_CONFIG_VALUE_0" => "always"
  ).freeze

  def setup
    skip "Ruby on Windows cannot run bin/setup or its stand-ins as commands; OS=Windows_NT tests its Windows branch elsewhere" if Gem.win_platform?

    @dir = File.realpath(Dir.mktmpdir("setup"))
    @bin = File.join(@dir, "bin")
    Dir.mkdir(@bin)
    File.write(File.join(@bin, "mise"), MISE)
    File.chmod(0o755, File.join(@bin, "mise"))
    @repo = File.join(@dir, "repo")
    Dir.mkdir(@repo)
    git("init", "--quiet", "--initial-branch", "trunk")
    FileUtils.mkdir_p(File.join(@repo, ".githooks"))
    File.write(File.join(@repo, ".githooks/pre-push"), HOOK)
    File.chmod(0o755, File.join(@repo, ".githooks/pre-push"))
    git("add", ".githooks/pre-push")
    git("commit", "--quiet", "--message", "the hook")
    @stub = File.join(@repo, ".git/hooks/pre-push")
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  private def env(extra = {})
    GIT_ALONE.merge("PATH" => "#{@bin}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}", "CI" => nil, "OS" => nil).merge(extra)
  end

  private def git(*, chdir: @repo)
    settings = %w[user.name=tokra user.email=tokra@localhost commit.gpgSign=false].flat_map { |setting| ["-c", setting] }
    printed, status = Open3.capture2e(env, "git", *settings, *, chdir:)

    assert_predicate status, :success?, printed
    printed.strip
  end

  # Runs bin/setup in the repository, and returns what it printed and its
  # status.
  private def run_setup(extra = {}, chdir: @repo) = Open3.capture2e(env(extra), SETUP, chdir:)

  # What mise was called with, one line a call.
  private def calls = File.readlines(File.join(@bin, "log"), chomp: true)

  def test_for_a_person_it_installs_the_tools_the_bundle_the_commit_hook_and_the_docs
    output, status = run_setup

    assert_predicate status, :success?, output
    assert_equal [
      "mise install",
      "mise x -- python -m pip install --quiet #{REUSE}",
      "mise x -- bin/linux-env bundle install",
      "mise x -- pre-commit install",
      "mise x -- bundle exec rake rdoc",
    ], calls
  end

  # A runner keeps vendor/bundle between runs, commits nothing, and reads
  # no documentation.
  def test_for_a_ci_runner_it_installs_the_bundle_as_ci_does_and_skips_the_commit_hook_and_the_docs
    output, status = run_setup({ "CI" => "true" })

    assert_predicate status, :success?, output
    assert_equal [
      "mise install",
      "mise x -- python -m pip install --quiet #{REUSE}",
      "mise x -- bundle config set --local path vendor/bundle",
      "mise x -- bundle config set --local frozen true",
      "mise x -- bin/linux-env bundle install",
    ], calls
  end

  # pre-commit refuses to install under core.hooksPath and would end the
  # script there, before the docs.
  def test_where_core_hooks_path_is_set_it_leaves_the_commit_hook_and_says_so
    output, status = run_setup(
      { "GIT_CONFIG_COUNT" => "2", "GIT_CONFIG_KEY_1" => "core.hooksPath", "GIT_CONFIG_VALUE_1" => File.join(@dir, "my-hooks") }
    )

    assert_predicate status, :success?, output
    refute_includes calls, "mise x -- pre-commit install"
    assert_equal "mise x -- bundle exec rake rdoc", calls.last
    said = output.lines(chomp: true)

    assert_includes said, "core.hooksPath is set, so git runs the hooks in #{File.join(@dir, 'my-hooks')}, not this clone's:"
    assert_includes said, "git push runs .githooks/pre-push only if the pre-push hook there runs #{@stub},"
    assert_includes said, "and pre-commit's hook is not installed."
  end

  # Windows sets OS for every process, which MSYS2's bash passes on. A
  # repository of Windows' gets the pins bin/setup reads.
  WINDOWS = { "OS" => "Windows_NT" }.freeze

  private def as_windows
    File.write(File.join(@repo, "mise.toml"), %([tools]\nruby = "4.0.9"\nrust = "1.2.3"\n))
    git("add", "mise.toml")
    git("commit", "--quiet", "--message", "the pins")
  end

  # On Windows, Rust's GNU host toolchain for RubyInstaller's MinGW Ruby,
  # with CI's components, and libclang and clang's own headers for
  # bindgen; the bundle installs
  # with what bin/windows-env sets, and there is no commit hook, since
  # mise installs pre-commit there only through pipx.
  def test_on_windows_it_adds_the_gnu_toolchain_libclang_and_clang_s_headers_and_installs_the_bundle_through_windows_env
    as_windows
    output, status = run_setup(WINDOWS)

    assert_predicate status, :success?, output
    assert_equal [
      "mise install",
      "mise x -- rustup toolchain install 1.2.3-x86_64-pc-windows-gnu --profile minimal --component clippy --component rustfmt",
      "mise x -- python -m pip install --quiet #{REUSE}",
      "mise x -- python -m pip install --quiet #{LIBCLANG}",
      "mise x -- sh bin/clang-headers",
      "mise x -- sh bin/windows-env bundle install",
      "mise x -- bundle exec rake rdoc",
    ], calls
  end

  def test_on_windows_a_ci_runner_installs_the_bundle_as_ci_does_through_windows_env
    as_windows
    output, status = run_setup(WINDOWS.merge("CI" => "true"))

    assert_predicate status, :success?, output
    assert_equal [
      "mise install",
      "mise x -- rustup toolchain install 1.2.3-x86_64-pc-windows-gnu --profile minimal --component clippy --component rustfmt",
      "mise x -- python -m pip install --quiet #{REUSE}",
      "mise x -- python -m pip install --quiet #{LIBCLANG}",
      "mise x -- sh bin/clang-headers",
      "mise x -- bundle config set --local path vendor/bundle",
      "mise x -- bundle config set --local frozen true",
      "mise x -- sh bin/windows-env bundle install",
    ], calls
  end

  # ci.yml's toolchain step installs these components on every system.
  def test_the_gnu_toolchain_gets_ci_s_components
    workflow = YAML.safe_load_file(File.join(ROOT, ".github/workflows/ci.yml"))
    step = workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps") }
      .find { |each| each["uses"].to_s.start_with?("dtolnay/rust-toolchain@") }
    components = step.fetch("with").fetch("components").split(/,\s*/)

    assert_equal %w[clippy rustfmt], components
    assert_includes File.read(SETUP), components.map { |component| "--component #{component}" }.join(" ")
  end

  def test_the_reuse_tool_is_ci_s
    workflow = YAML.safe_load_file(File.join(ROOT, ".github/workflows/ci.yml"))
    step = workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps") }
      .find { |each| each["name"] == "Install the REUSE tool" }

    assert_includes step.fetch("run"), %("#{REUSE}")
    assert_includes File.read(SETUP), %("#{REUSE}")
  end

  # rake sync:tauri reads vendor/tauri, which a plain clone leaves empty.
  def test_it_checks_out_a_submodule_a_clone_left_empty
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
    output, status = run_setup

    assert_predicate status, :success?, output
    assert_equal "the submodule's file", File.read(File.join(@repo, "vendor/library/inside"))
  end

  def test_the_stub_it_writes_runs_the_hook_of_whichever_worktree_pushes
    run_setup
    worktree = File.join(@dir, "worktree")
    git("worktree", "add", "--quiet", worktree)

    assert_predicate File.stat(@stub), :executable?
    [@repo, worktree].each do |pushing|
      output, status = Open3.capture2e(env, @stub, "origin", "git@example.com:tokra.git", chdir: pushing)

      assert_predicate status, :success?, output
      assert_equal [pushing, "origin", "git@example.com:tokra.git"], File.readlines(File.join(pushing, "ran"), chomp: true)
    end
  end

  # Run from a worktree, it still writes the one stub every worktree's
  # push finds: git reads hooks from the clone's shared folder only.
  def test_run_from_a_worktree_it_writes_the_stub_into_the_clones_shared_hooks
    worktree = File.join(@dir, "worktree")
    git("worktree", "add", "--quiet", worktree)
    output, status = run_setup(chdir: worktree)

    assert_predicate status, :success?, output
    assert_predicate File.stat(@stub), :executable?
    assert_empty Dir.glob(File.join(@repo, ".git/worktrees/*/hooks/*"))
  end

  # The whole path, for real: bin/setup's stub, the hook this repository
  # ships, and a git push, which hands the hook its refs on standard input.
  # Without them the hook sees nothing to gate and lets the push through.
  def test_a_real_push_through_its_stub_runs_the_shipped_hook_and_the_gate
    %w[bundle xvfb-run].each do |name|
      File.write(File.join(@bin, name), GATE)
      File.chmod(0o755, File.join(@bin, name))
    end
    File.write(File.join(@repo, ".githooks/pre-push"), File.read(REAL_HOOK))
    # On Linux the hook runs the gate through bin/linux-env.
    FileUtils.mkdir_p(File.join(@repo, "bin"))
    File.write(File.join(@repo, "bin/linux-env"), "#!/bin/sh\nexec \"$@\"\n")
    File.chmod(0o755, File.join(@repo, "bin/linux-env"))
    git("add", "bin/linux-env")
    git("commit", "--quiet", "--all", "--message", "the shipped hook")
    remote = File.join(@dir, "remote.git")
    git("init", "--quiet", "--bare", remote, chdir: @dir)
    run_setup
    git("push", "--quiet", remote, "HEAD:refs/heads/trunk")

    gate = calls.reject { |call| call.start_with?("mise") }

    assert_equal 1, gate.size, calls.inspect
    assert_match(/\A(xvfb-run .* )?bundle exec rake\z/, gate.first)
    assert_equal git("rev-parse", "HEAD"), git("rev-parse", "refs/heads/trunk", chdir: remote)
  end

  def test_the_stub_passes_a_push_from_a_commit_that_has_no_hook
    run_setup
    File.delete(File.join(@repo, ".githooks/pre-push"))
    output, status = Open3.capture2e(env, @stub, "origin", "git@example.com:tokra.git", chdir: @repo)

    assert_predicate status, :success?, output
    refute_path_exists File.join(@repo, "ran")
  end

  def test_running_it_again_leaves_the_same_stub
    run_setup
    first = File.read(@stub)
    output, status = run_setup

    assert_predicate status, :success?, output
    assert_equal first, File.read(@stub)
    assert_includes first.lines(chomp: true), MARKER
  end

  # A later bin/setup may change the stub, and has to reach clones that
  # hold an earlier one.
  def test_a_stub_of_its_own_from_an_earlier_version_is_replaced
    run_setup
    current = File.read(@stub)
    File.write(@stub, "#!/bin/sh\n#{MARKER}\nexit 0\n")
    output, status = run_setup

    assert_predicate status, :success?, output
    assert_equal current, File.read(@stub)
  end

  # A clone made from an empty template has no hooks folder.
  def test_a_clone_with_no_hooks_folder_gets_one
    FileUtils.rm_rf(File.dirname(@stub))
    output, status = run_setup

    assert_predicate status, :success?, output
    assert_predicate File.stat(@stub), :executable?
  end

  # Someone's own hook there, whatever it mentions, is theirs to keep.
  def test_a_hook_that_is_not_its_own_is_left_alone_and_said_so
    own = "#!/bin/sh\necho '#{MARKER}' # this line only quotes the marker\nexit 0\n"
    File.write(@stub, own)
    output, status = run_setup

    assert_predicate status, :success?, output
    assert_equal own, File.read(@stub)
    assert_includes output, "#{@stub} exists and is not Tokra's; leaving it, so git push will not run .githooks/pre-push."
  end

  # A runner that checks Tokra out runs bin/setup.ps1 before the hook on
  # Windows only if git recorded it as executable, as it does bin/setup.
  def test_both_setup_scripts_are_tracked_as_executable
    listed, status = Open3.capture2(GIT_PLACE, "git", "ls-files", "--stage", "--", "bin/setup", "bin/setup.ps1", chdir: ROOT)

    assert_predicate status, :success?
    assert_equal %w[100755 100755], listed.lines.map { |line| line.split.first }
  end
end
