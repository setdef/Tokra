# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "date"
require "fileutils"
require "tmpdir"
require_relative "../../tasks/bump"
require_relative "../../tasks/tokra_gems"

# Tests bump:<gem>:* in a throwaway repository laid out as Tokra is, tokra
# at the root and one plugin under plugins/, with real git. A stand-in
# replaces the gate.
class TestBump < Minitest::Test
  CORE = TokraGem.new(short_name: "tokra", name: "tokra", dir: ".", version_file: "lib/tokra/version.rb", crate: "ext/tokra")
  PLUGIN = TokraGem.plugin("demo")
  REPO = "https://github.com/setdef/Tokra"

  def setup
    @root = Dir.mktmpdir("bump")
    write_core("0.0.1.pre.2", crate: "0.1.0")
    write("CHANGELOG.md", "# Changelog\n\n## [Unreleased]\n\n### Added\n\n- A thing.\n\n[Unreleased]: #{REPO}/compare/v0.0.1.pre.2...HEAD\n")
    write_plugin("0.0.1.pre.1", tokra: "0.0.1.pre.2", floor: "0.0")
    write("plugins/demo/CHANGELOG.md", "# Changelog\n\n## [Unreleased]\n\n### Added\n\n- The plugin.\n\n" \
      "[Unreleased]: #{REPO}/commits/trunk/plugins/demo\n")
    git("init", "--quiet", "--initial-branch", "trunk")
    git("add", ".")
    commit("init")
    @gate_runs = 0
  end

  def teardown
    [@root, @origin].compact.each { |dir| FileUtils.remove_entry(dir) }
  end

  private def write_core(version, crate:)
    write("lib/tokra/version.rb", %(module Tokra\n  VERSION = "#{version}"\nend\n))
    write("ext/tokra/Cargo.toml", "[package]\nname = \"tokra\"\n\nversion = \"#{crate}\"\nedition = \"2021\"\n\n" \
      "[dependencies]\nmagnus = { version = \"0.8.2\" }\n")
    write("Cargo.lock", %([[package]]\nname = "magnus"\nversion = "0.8.2"\n\n[[package]]\nname = "tokra"\nversion = "#{crate}"\n))
    rubygems = GemVersion.parse(version).rubygems
    write("Gemfile.lock", "PATH\n  remote: .\n  specs:\n    tokra (#{rubygems})\n      rb_sys (~> 0.9.129)\n\n" \
      "CHECKSUMS\n  tokra (#{rubygems})\n  tokra-demo (9.9.9)\n")
  end

  private def write_plugin(version, tokra:, floor:)
    write("plugins/demo/lib/tokra/plugins/demo/version.rb",
      %(module Tokra\n  module Plugins\n    # Demo is a module (not class) to allow VERSION in version.rb.\n    module Demo\n      VERSION = "#{version}"\n    end\n  end\nend\n))
    write("plugins/demo/tokra-demo.gemspec", "Gem::Specification.new do |spec|\n  spec.add_dependency \"ferro-url\", \"= 0.1.0\"\n" \
      "  spec.add_dependency \"tokra\", \"~> #{floor}\"\nend\n")
    write("plugins/demo/Gemfile.lock", "PATH\n  remote: ../..\n  specs:\n    tokra (#{tokra})\n      ferro-url (= 0.1.0)\n\n" \
      "PATH\n  remote: .\n  specs:\n    tokra-demo (#{version})\n      ferro-url (= 0.1.0)\n      tokra (~> #{floor})\n\n" \
      "DEPENDENCIES\n  tokra!\n  tokra-demo!\n\nCHECKSUMS\n  tokra (#{tokra})\n  tokra-demo (#{version})\n")
  end

  private def write(path, content)
    FileUtils.mkdir_p(File.dirname(File.join(@root, path)))
    File.write(File.join(@root, path), content)
  end

  private def read(path)
    File.read(File.join(@root, path))
  end

  private def git(*)
    system("git", "-c", "user.name=Test", "-c", "user.email=test@example.com", *, chdir: @root, exception: true,
      out: File::NULL, err: File::NULL)
  end

  private def commit(message)
    git("commit", "--quiet", "--message", message)
  end

  private def commit_all(message)
    git("add", ".")
    commit(message)
  end

  private def log
    IO.popen(["git", "log", "--format=%s", chdir: @root], &:read).lines.map(&:chomp)
  end

  private def last_message
    IO.popen(["git", "log", "-1", "--format=%B", chdir: @root], &:read).chomp
  end

  private def status
    IO.popen(["git", "status", "--porcelain", chdir: @root], &:read)
  end

  private def bump(gem = CORE, gate: true, &)
    with_identity { bumper(gem, gate:).run!(&) }
  end

  private def release_current(gem = PLUGIN)
    with_identity { bumper(gem).release_current! }
  end

  private def bumper(gem, gate: true)
    dependents = gem.core? ? [PLUGIN] : []
    Bump.new(root: @root, gem:, dependents:, gate: -> { @gate_runs += 1; gate }, date: Date.new(2026, 11, 13))
  end

  private def with_identity
    ENV["GIT_AUTHOR_NAME"] = ENV["GIT_COMMITTER_NAME"] = "Test"
    ENV["GIT_AUTHOR_EMAIL"] = ENV["GIT_COMMITTER_EMAIL"] = "test@example.com"
    yield
  ensure
    %w[GIT_AUTHOR_NAME GIT_COMMITTER_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_EMAIL].each { |name| ENV.delete(name) }
  end

  # A bare repository as origin, holding trunk, so the tag check can ask it.
  private def with_origin
    @origin = Dir.mktmpdir("bump-origin")
    system("git", "init", "--quiet", "--bare", @origin, exception: true, out: File::NULL, err: File::NULL)
    git("remote", "add", "origin", @origin)
    git("push", "--quiet", "origin", "trunk")
  end

  # The release Plan 059 hands the maintainer: rake bump:tokra:minor.
  def test_a_minor_tokra_bump_releases_0_1_0_and_raises_every_plugins_floor_with_it
    version = bump { |current| current.next(:minor) }

    assert_equal "0.1.0", version.to_s
    assert_includes read("lib/tokra/version.rb"), %(VERSION = "0.1.0")
    assert_equal 2, read("Gemfile.lock").scan("tokra (0.1.0)").size
    assert_includes read("Gemfile.lock"), "tokra-demo (9.9.9)"
    assert_equal 2, read("plugins/demo/Gemfile.lock").scan(/^ +tokra \(0\.1\.0\)$/).size
    assert_includes read("plugins/demo/Gemfile.lock"), "    tokra-demo (0.0.1.pre.1)\n      ferro-url (= 0.1.0)\n      tokra (~> 0.1)\n"
    assert_includes read("plugins/demo/tokra-demo.gemspec"), %(spec.add_dependency "tokra", "~> 0.1")
    assert_includes read("plugins/demo/tokra-demo.gemspec"), %(spec.add_dependency "ferro-url", "= 0.1.0")
    assert_includes read("plugins/demo/lib/tokra/plugins/demo/version.rb"), %(VERSION = "0.0.1.pre.1")
    assert_includes read("CHANGELOG.md"), "## [Unreleased]\n\n## [0.1.0] - 2026-11-13\n\n### Added\n\n- A thing.\n"
    assert_includes read("CHANGELOG.md"),
      "[Unreleased]: #{REPO}/compare/tokra/v0.1.0...HEAD\n[0.1.0]: #{REPO}/compare/v0.0.1.pre.2...tokra/v0.1.0\n"
    assert_includes read("plugins/demo/CHANGELOG.md"), "## [Unreleased]\n\n### Added\n\n- The plugin.\n"
    assert_equal 1, @gate_runs
    assert_equal ["chore(tokra): release 0.1.0", "init"], log
    assert_equal <<~MESSAGE, last_message
      chore(tokra): release 0.1.0

      Release tokra 0.1.0. The entries that were under Unreleased in its
      CHANGELOG are now the 0.1.0 section, dated 2026-11-13, and version.rb,
      the crate's Cargo.toml, Cargo.lock, and the Gemfile.lock, and each
      plugin's Gemfile.lock, name 0.1.0. Each plugin now requires tokra ~>
      0.1, since a plugin is only ever tested against the tokra beside it. Tag
      it with rake release:tokra:tag.

      Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
    MESSAGE
    assert_empty status
  end

  # An example takes tokra by path, so its lockfile names tokra's version.
  def test_a_tokra_bump_moves_the_examples_lockfiles_that_list_it
    write("examples/app/Gemfile.lock", "PATH\n  remote: ../..\n  specs:\n    tokra (0.0.1.pre.2)\n      rb_sys (~> 0.9.129)\n\n" \
      "CHECKSUMS\n  rack (3.2.4)\n  tokra (0.0.1.pre.2)\n")
    write("examples/other/Gemfile.lock", "GEM\n  specs:\n    rack (3.2.4)\n")
    commit_all("examples")

    bump { |current| current.next(:minor) }

    assert_equal 2, read("examples/app/Gemfile.lock").scan(/^ +tokra \(0\.1\.0\)$/).size
    assert_includes read("examples/app/Gemfile.lock"), "  rack (3.2.4)\n"
    assert_equal "GEM\n  specs:\n    rack (3.2.4)\n", read("examples/other/Gemfile.lock")
    assert_empty status
  end

  def test_the_crate_takes_the_gems_version_whatever_it_held
    bump { GemVersion.parse("0.3.0") }

    assert_includes read("ext/tokra/Cargo.toml"), %(name = "tokra"\n\nversion = "0.3.0"\nedition)
    assert_includes read("ext/tokra/Cargo.toml"), %(magnus = { version = "0.8.2" })
    assert_includes read("Cargo.lock"), %(name = "tokra"\nversion = "0.3.0")
    assert_includes read("Cargo.lock"), %(name = "magnus"\nversion = "0.8.2")
  end

  def test_a_patch_keeps_the_floor_and_says_nothing_of_it
    write_core("0.1.0", crate: "0.1.0")
    write_plugin("0.1.0", tokra: "0.1.0", floor: "0.1")
    commit_all("released")

    bump { |current| current.next(:patch) }

    assert_includes read("plugins/demo/tokra-demo.gemspec"), %("tokra", "~> 0.1")
    assert_equal 2, read("plugins/demo/Gemfile.lock").scan(/^ +tokra \(0\.1\.1\)$/).size
    refute_includes last_message, "requires"
  end

  # A floor of ~> 0.2 would refuse tokra 0.2.0-beta.1 itself.
  def test_a_prerelease_keeps_the_floor_below_it
    version = bump { |current| current.next(:minor, "beta") }

    assert_equal "0.1.0-beta.1", version.to_s
    assert_includes read("lib/tokra/version.rb"), %(VERSION = "0.1.0-beta.1")
    assert_includes read("ext/tokra/Cargo.toml"), %(version = "0.1.0-beta.1")
    assert_equal 2, read("Gemfile.lock").scan("tokra (0.1.0.pre.beta.1)").size
    assert_equal 2, read("plugins/demo/Gemfile.lock").scan(/^ +tokra \(0\.1\.0\.pre\.beta\.1\)$/).size
    assert_includes read("plugins/demo/tokra-demo.gemspec"), %("tokra", "~> 0.0")
    assert_includes read("plugins/demo/Gemfile.lock"), "      tokra (~> 0.0)\n"
    refute_includes last_message, "requires"
  end

  def test_a_plugin_bump_writes_only_the_plugins_files
    version = bump(PLUGIN) { |current| current.next(:minor) }

    assert_equal "0.1.0", version.to_s
    assert_includes read("plugins/demo/lib/tokra/plugins/demo/version.rb"), %(VERSION = "0.1.0")
    assert_equal 2, read("plugins/demo/Gemfile.lock").scan("tokra-demo (0.1.0)").size
    assert_equal 2, read("plugins/demo/Gemfile.lock").scan("tokra (0.0.1.pre.2)").size
    assert_includes read("plugins/demo/CHANGELOG.md"), "## [Unreleased]\n\n## [0.1.0] - 2026-11-13\n\n### Added\n\n- The plugin.\n"
    assert_includes read("plugins/demo/CHANGELOG.md"),
      "[Unreleased]: #{REPO}/compare/tokra-demo/v0.1.0...HEAD\n[0.1.0]: #{REPO}/releases/tag/tokra-demo/v0.1.0\n"
    assert_includes read("lib/tokra/version.rb"), %(VERSION = "0.0.1.pre.2")
    assert_includes read("Gemfile.lock"), "tokra-demo (9.9.9)"
    assert_equal ["chore(demo): release 0.1.0", "init"], log
    assert_equal <<~MESSAGE, last_message
      chore(demo): release 0.1.0

      Release tokra-demo 0.1.0. The entries that were under Unreleased in its
      CHANGELOG are now the 0.1.0 section, dated 2026-11-13, and version.rb
      and its Gemfile.lock name 0.1.0. Tag it with rake release:demo:tag.

      Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
    MESSAGE
    assert_empty status
  end

  def test_a_hyphenated_version_bumps_to_the_next_prerelease
    write_core("0.2.0-pre.1", crate: "0.2.0-pre.1")
    write_plugin("0.1.0", tokra: "0.2.0.pre.pre.1", floor: "0.1")
    commit_all("hyphenated")

    version = bump { |current| current.next(:patch, "pre") }

    assert_equal "0.2.0-pre.2", version.to_s
    assert_includes read("lib/tokra/version.rb"), %(VERSION = "0.2.0-pre.2")
    assert_includes read("Gemfile.lock"), "tokra (0.2.0.pre.pre.2)"
    assert_includes read("plugins/demo/Gemfile.lock"), "tokra (0.2.0.pre.pre.2)"
    assert_includes read("CHANGELOG.md"), "## [0.2.0-pre.2] - 2026-11-13"
  end

  def test_a_prerelease_cannot_follow_a_dotted_one_of_the_same_release_in_hyphens
    error = assert_raises(Bump::Failure) { bump { |current| current.next(:patch, "pre") } }

    assert_includes error.message, "0.0.1-pre.3 would come before 0.0.1.pre.2, and no label changes that"
    assert_equal ["init"], log
  end

  def test_a_failing_gate_leaves_the_bump_uncommitted
    error = assert_raises(Bump::Failure) { bump(gate: false) { |current| current.next(:minor) } }

    assert_includes error.message, "the gate failed"
    assert_equal ["init"], log
    assert_includes read("lib/tokra/version.rb"), %(VERSION = "0.1.0")
    assert_includes read("plugins/demo/tokra-demo.gemspec"), %("tokra", "~> 0.1")
  end

  def test_a_plugin_lockfile_out_of_step_restores_everything
    write_plugin("0.0.1.pre.1", tokra: "0.0.1.pre.1", floor: "0.0")
    commit_all("drift")

    error = assert_raises(Bump::Failure) { bump { |current| current.next(:minor) } }

    assert_equal "plugins/demo/Gemfile.lock does not list tokra 0.0.1.pre.2", error.message
    assert_equal 0, @gate_runs
    assert_empty status
  end

  def test_a_plugin_without_a_tokra_bound_restores_everything
    write("plugins/demo/tokra-demo.gemspec", %(Gem::Specification.new do |spec|\n  spec.add_dependency "tokra", ">= 0"\nend\n))
    commit_all("unbounded")

    error = assert_raises(Bump::Failure) { bump { |current| current.next(:minor) } }

    assert_includes error.message, "plugins/demo/tokra-demo.gemspec has no tokra ~> bound"
    assert_empty status
  end

  def test_an_older_or_equal_version_is_refused
    error = assert_raises(Bump::Failure) { bump { GemVersion.parse("0.0.1.pre.2") } }

    assert_equal "0.0.1.pre.2 does not come after 0.0.1.pre.2", error.message
  end

  def test_a_stable_one_point_oh_waits_for_a_branch_policy
    error = assert_raises(Bump::Failure) { bump { |current| current.next(:major) } }

    assert_includes error.message, "release-branch policy"
  end

  def test_a_bad_label_is_reported
    error = assert_raises(Bump::Failure) { bump { |current| current.next(:minor, "pre-2") } }

    assert_includes error.message, "not a prerelease label"
  end

  def test_another_branch_or_a_dirty_tree_is_refused
    write("stray.txt", "")
    assert_equal "commit or stash your changes first", assert_raises(Bump::Failure) { bump { |c| c.next(:minor) } }.message

    FileUtils.rm(File.join(@root, "stray.txt"))
    git("switch", "--quiet", "--create", "topic")
    assert_equal "bump on trunk, not topic", assert_raises(Bump::Failure) { bump { |c| c.next(:minor) } }.message
  end

  # A future plugin starts at 0.1.0 and releases it with bump:<name>:current.
  private def start_plugin_at_zero_one
    write_plugin("0.1.0", tokra: "0.0.1.pre.2", floor: "0.0")
    commit_all("a new plugin")
    with_origin
  end

  def test_current_releases_the_version_a_new_plugin_starts_at
    start_plugin_at_zero_one

    assert_equal "0.1.0", release_current.to_s
    assert_includes read("plugins/demo/CHANGELOG.md"), "## [0.1.0] - 2026-11-13"
    assert_equal 2, read("plugins/demo/Gemfile.lock").scan("tokra-demo (0.1.0)").size
    assert_equal 1, @gate_runs
    assert_equal ["chore(demo): release 0.1.0", "a new plugin", "init"], log
    assert_empty status
  end

  def test_current_is_refused_once_the_version_is_tagged_here
    start_plugin_at_zero_one
    git("tag", "tokra-demo/v0.1.0")

    error = assert_raises(Bump::Failure) { release_current }

    assert_equal "tokra-demo/v0.1.0 already exists, so 0.1.0 is released; bump past it", error.message
  end

  def test_current_is_refused_once_origin_has_the_tag
    start_plugin_at_zero_one
    git("tag", "tokra-demo/v0.1.0")
    git("push", "--quiet", "origin", "refs/tags/tokra-demo/v0.1.0")
    git("tag", "--delete", "tokra-demo/v0.1.0")

    error = assert_raises(Bump::Failure) { release_current }

    assert_equal "origin already has tokra-demo/v0.1.0, so 0.1.0 is released; bump past it", error.message
    assert_equal 0, @gate_runs
  end

  def test_current_is_refused_when_the_changelog_already_has_the_version
    start_plugin_at_zero_one
    write("plugins/demo/CHANGELOG.md", "# Changelog\n\n## [Unreleased]\n\n- Another.\n\n## [0.1.0] - 2026-11-12\n\n- A thing.\n\n" \
      "[Unreleased]: #{REPO}/commits/trunk/plugins/demo\n")
    commit_all("released by hand")

    error = assert_raises(Bump::Failure) { release_current }

    assert_equal "plugins/demo/CHANGELOG.md already has a 0.1.0 section; bump past it", error.message
  end

  def test_current_is_refused_with_nothing_unreleased
    start_plugin_at_zero_one
    write("plugins/demo/CHANGELOG.md", "# Changelog\n\n## [Unreleased]\n\n[Unreleased]: #{REPO}/commits/trunk/plugins/demo\n")
    commit_all("empty")

    error = assert_raises(Bump::Failure) { release_current }

    assert_includes error.message, "nothing under Unreleased to release"
    assert_equal 0, @gate_runs
    assert_empty status
  end

  def test_current_is_refused_without_an_origin_to_ask
    write_plugin("0.1.0", tokra: "0.0.1.pre.2", floor: "0.0")
    commit_all("a new plugin")

    assert_includes assert_raises(Bump::Failure) { release_current }.message, "git ls-remote"
  end

  def test_current_is_refused_below_a_released_version
    start_plugin_at_zero_one
    git("tag", "tokra-demo/v0.2.0")

    error = assert_raises(Bump::Failure) { release_current }

    assert_equal "0.1.0 is below 0.2.0, which is released; bump past it", error.message
    assert_equal 0, @gate_runs
  end
end
