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

  # A mise that logs its arguments, one line a call, and runs nothing.
  MISE = <<~'SH'
    #!/bin/sh
    { printf '%s' mise; for a in "$@"; do printf ' %s' "$a"; done; printf '\n'; } >> "$(dirname "$0")/log"
  SH

  # A hook that records the folder it ran in and its arguments.
  HOOK = <<~'SH'
    #!/bin/sh
    printf '%s\n' "$(pwd -P)" "$@" > "$(git rev-parse --show-toplevel)/ran"
  SH

  # The variables a git hook passes on, which would point the git commands
  # here at the repository whose hook runs these tests.
  GIT_PLACE = %w[GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX].to_h { |name| [name, nil] }.freeze

  def setup
    skip "bin/setup is a bash script; Windows has no setup script yet" if Gem.win_platform?

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

  private def env(ci: nil)
    GIT_PLACE.merge("PATH" => "#{@bin}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}", "CI" => ci)
  end

  private def git(*, chdir: @repo)
    settings = %w[user.name=tokra user.email=tokra@localhost commit.gpgSign=false core.hooksPath=/dev/null]
      .flat_map { |setting| ["-c", setting] }
    printed, status = Open3.capture2e(GIT_PLACE, "git", *settings, *, chdir:)

    assert_predicate status, :success?, printed
    printed.strip
  end

  # Runs bin/setup in the repository, and returns what it printed and its
  # status.
  private def run_setup(ci: nil) = Open3.capture2e(env(ci:), SETUP, chdir: @repo)

  # What mise was called with, one line a call.
  private def calls = File.readlines(File.join(@bin, "log"), chomp: true)

  def test_for_a_person_it_installs_the_tools_the_bundle_the_commit_hook_and_the_docs
    output, status = run_setup

    assert_predicate status, :success?, output
    assert_equal [
      "mise install",
      "mise x -- python -m pip install --quiet #{REUSE}",
      "mise x -- bundle install",
      "mise x -- pre-commit install",
      "mise x -- bundle exec rake rdoc",
    ], calls
  end

  # A runner keeps vendor/bundle between runs, commits nothing, and reads
  # no documentation.
  def test_for_a_ci_runner_it_installs_the_bundle_as_ci_does_and_skips_the_commit_hook_and_the_docs
    output, status = run_setup(ci: "true")

    assert_predicate status, :success?, output
    assert_equal [
      "mise install",
      "mise x -- python -m pip install --quiet #{REUSE}",
      "mise x -- bundle config set --local path vendor/bundle",
      "mise x -- bundle config set --local frozen true",
      "mise x -- bundle install",
    ], calls
  end

  def test_the_reuse_tool_is_ci_s
    workflow = YAML.safe_load_file(File.join(ROOT, ".github/workflows/ci.yml"))
    step = workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps") }
      .find { |each| each["name"] == "Install the REUSE tool" }

    assert_includes step.fetch("run"), %("#{REUSE}")
    assert_includes File.read(SETUP), %("#{REUSE}")
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
    assert_includes first.lines(chomp: true), "# tokra pre-push stub, written by bin/setup"
  end

  # Someone's own hook there, whatever it mentions, is theirs to keep.
  def test_a_hook_that_is_not_its_own_is_left_alone_and_said_so
    own = "#!/bin/sh\n# my own hook, which once read: tokra pre-push stub, written by bin/setup\nexit 0\n"
    FileUtils.mkdir_p(File.dirname(@stub))
    File.write(@stub, own)
    output, status = run_setup

    assert_predicate status, :success?, output
    assert_equal own, File.read(@stub)
    assert_includes output, "#{@stub} exists and is not Tokra's; leaving it, so git push will not run .githooks/pre-push."
  end
end
