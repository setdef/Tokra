# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "fileutils"
require "tmpdir"
require_relative "../../tasks/release"

# Tests the release task's checks and commands in a throwaway repository.
# A recorder stands in for the commands, so nothing is built, tagged, or
# pushed.
class TestRelease < Minitest::Test
  # An annotated tag needs a tagger; a CI runner has no git identity.
  IDENTITY = { "GIT_COMMITTER_NAME" => "Test", "GIT_COMMITTER_EMAIL" => "test@example.com" }.freeze

  def setup
    @root = Dir.mktmpdir("release")
    write("plugins/demo/CHANGELOG.md", "# Changelog\n\n## [Unreleased]\n\n## [0.1.0] - 2026-10-24\n\n- First.\n")
    # As Tokra's own .gitignore does.
    write(".gitignore", "/pkg/\n/tmp/\n")
    git("init", "--quiet", "--initial-branch", "trunk")
    git("add", ".")
    git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "--quiet", "--message", "init")
    @ran = []
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  private def write(path, content)
    FileUtils.mkdir_p(File.dirname(File.join(@root, path)))
    File.write(File.join(@root, path), content)
  end

  private def git(*, chdir: @root)
    system("git", "-c", "user.name=Test", "-c", "user.email=test@example.com", *, chdir:, exception: true,
      out: File::NULL, err: File::NULL)
  end

  private def output(*)
    IO.popen(["git", *, chdir: @root], err: File::NULL, &:read)
  end

  # A release whose commands only record themselves, and succeed unless
  # +succeed+ is false or names the command's second word. Its gem build
  # writes a real package of +built+, holding +files+.
  private def release(version: "0.1.0", succeed: true, built: version, files: [], generated: [], name: "tokra-demo",
    dir: "plugins/demo"
  )
    runner = lambda do |command, chdir:|
      @ran << [command, chdir]
      ok = succeed == true || (succeed && succeed != command[1])
      write_package(command[command.index("--output") + 1], built, files:, name:) if ok && command.first(2) == %w[gem build]
      ok
    end
    Release.new(root: @root, name:, dir:, version:, scope: "demo", runner:, generated:)
  end

  def test_the_tag_names_the_gem
    assert_equal "tokra-demo/v0.1.0", release.tag
  end

  def test_a_ready_repository_runs_build_push_tag_and_publish_in_order
    release.run!

    assert_equal [
      ["gem", "build", "tokra-demo.gemspec", "--output", File.join(@root, "pkg/tokra-demo-0.1.0.gem")],
      %w[git push origin trunk],
      ["git", "tag", "--annotate", "tokra-demo/v0.1.0", "--message", "tokra-demo 0.1.0"],
      ["git", "push", "origin", "tokra-demo/v0.1.0"],
      ["gem", "push", File.join(@root, "pkg/tokra-demo-0.1.0.gem")],
    ], @ran.map(&:first)
    assert_equal File.join(@root, "plugins/demo"), @ran.first.last
  end

  # The package is read back after the build, before anything is pushed.
  def test_a_package_of_another_version_stops_the_release_before_any_push
    error = assert_raises(Release::Failure) { release(built: "0.0.9").run! }

    assert_includes error.message, "holds version 0.0.9, not 0.1.0"
    assert_equal [%w[gem build]], @ran.map { |command, _| command.first(2) }
  end

  # tokra's JavaScript templates are git-ignored and packed by hand, so a
  # build without them would ship a gem that fails to load.
  def test_a_package_without_its_generated_files_stops_the_release_before_any_push
    error = assert_raises(Release::Failure) { release(generated: ["lib/tokra/js/*"], files: ["lib/tokra.rb"]).run! }

    assert_includes error.message, "has no lib/tokra/js/*; the gemspec packs them only once they are generated"
    assert_equal 1, @ran.size
  end

  def test_a_package_with_its_generated_files_goes_ahead
    release(generated: ["lib/tokra/js/*"], files: ["lib/tokra.rb", "lib/tokra/js/emit.js.erb"]).run!

    assert_equal 5, @ran.size
  end

  def test_tokra_releases_from_the_root_under_a_tag_named_for_it
    write("CHANGELOG.md", "# Changelog\n\n## [Unreleased]\n\n## [0.1.0] - 2026-11-13\n\n- First.\n")
    git("add", ".")
    git("commit", "--quiet", "--message", "tokra's changelog")
    tokra = release(name: "tokra", dir: ".")

    tokra.run!

    assert_equal "tokra/v0.1.0", tokra.tag
    assert_equal [["gem", "build", "tokra.gemspec", "--output", File.join(@root, "pkg/tokra-0.1.0.gem")], File.join(@root, ".")],
      @ran.first
    assert_equal "CHANGELOG.md has no section for 0.2.0",
      assert_raises(Release::Failure) { release(name: "tokra", dir: ".", version: "0.2.0").run! }.message
  end

  def test_a_failing_command_stops_the_release
    error = assert_raises(Release::Failure) { release(succeed: false).run! }

    assert_includes error.message, "gem build"
    assert_equal 1, @ran.size
  end

  # Pushing trunk runs the gate. Were the tag made first, a push the gate
  # refused would leave it behind, and the next try would stop at "already
  # exists".
  def test_a_branch_push_that_is_refused_leaves_no_tag
    error = assert_raises(Release::Failure) { release(succeed: "push").run! }

    assert_equal "git push origin trunk failed", error.message
    assert_equal [%w[gem build], %w[git push]], @ran.map { |command, _| command.first(2) }
  end

  def test_another_branch_is_refused
    git("switch", "--quiet", "--create", "topic")

    error = assert_raises(Release::Failure) { release.run! }

    assert_equal "release from trunk, not topic", error.message
    assert_empty @ran
  end

  def test_a_dirty_tree_is_refused
    write("plugins/demo/stray.rb", "")

    error = assert_raises(Release::Failure) { release.run! }

    assert_equal "commit or stash your changes first", error.message
  end

  def test_an_existing_tag_is_refused
    git("tag", "tokra-demo/v0.1.0")

    error = assert_raises(Release::Failure) { release.run! }

    assert_equal "tokra-demo/v0.1.0 already exists", error.message
  end

  def test_a_version_without_a_changelog_section_is_refused
    error = assert_raises(Release::Failure) { release(version: "0.2.0").run! }

    assert_equal "plugins/demo/CHANGELOG.md has no section for 0.2.0", error.message
  end

  # The tag-only path runs real git against a bare origin.
  private def with_origin
    @origin = Dir.mktmpdir("origin")
    git("init", "--quiet", "--bare", chdir: @origin)
    git("remote", "add", "origin", @origin)
    git("push", "--quiet", "origin", "trunk")
    yield
  ensure
    FileUtils.remove_entry(@origin)
  end

  private def tagging_release(version: "0.1.0")
    runner = lambda do |command, chdir:|
      @ran << command
      system(IDENTITY, *command, chdir:, out: File::NULL, err: File::NULL)
    end
    Release.new(root: @root, name: "tokra-demo", dir: "plugins/demo", version:, scope: "demo", runner:)
  end

  private def commit_release(version = "0.1.0")
    write("plugins/demo/VERSION", version)
    git("add", ".")
    git("commit", "--quiet", "--message", "chore(demo): release #{version}")
    output("rev-parse", "HEAD").strip
  end

  def test_the_tag_goes_on_the_release_commit_and_only_the_tag_is_pushed
    with_origin do
      release_commit = commit_release
      write("plugins/demo/notes.md", "after the release\n")
      git("add", ".")
      git("commit", "--quiet", "--message", "docs: a later commit")
      git("push", "--quiet", "origin", "trunk")
      trunk = output("rev-parse", "HEAD").strip

      tagging_release.tag!

      assert_equal [
        ["git", "tag", "--annotate", "tokra-demo/v0.1.0", release_commit, "--message", "tokra-demo 0.1.0"],
        ["git", "push", "origin", "refs/tags/tokra-demo/v0.1.0"],
      ], @ran
      assert_equal release_commit, IO.popen(["git", "rev-parse", "tokra-demo/v0.1.0^{commit}", chdir: @origin], &:read).strip
      assert_equal trunk, IO.popen(["git", "rev-parse", "trunk", chdir: @origin], &:read).strip
    end
  end

  def test_tagging_refuses_a_trunk_out_of_step_with_origin
    with_origin do
      commit_release

      error = assert_raises(Release::Failure) { tagging_release.tag! }

      assert_equal "trunk differs from origin's; pull or push it first", error.message
      assert_empty @ran
    end
  end

  def test_tagging_refuses_a_tag_origin_already_has
    with_origin do
      commit_release
      git("push", "--quiet", "origin", "trunk")
      git("push", "--quiet", "origin", "HEAD:refs/tags/tokra-demo/v0.1.0")

      error = assert_raises(Release::Failure) { tagging_release.tag! }

      assert_equal "origin already has tokra-demo/v0.1.0", error.message
    end
  end

  def test_tagging_refuses_without_a_release_commit
    with_origin do
      error = assert_raises(Release::Failure) { tagging_release.tag! }

      assert_includes error.message, %(trunk has no commit "chore(demo): release 0.1.0")
      assert_empty @ran
    end
  end

  def test_tagging_checks_what_a_full_release_checks
    with_origin do
      commit_release
      git("push", "--quiet", "origin", "trunk")
      write("plugins/demo/stray.rb", "")

      assert_equal "commit or stash your changes first", assert_raises(Release::Failure) { tagging_release.tag! }.message
      FileUtils.rm(File.join(@root, "plugins/demo/stray.rb"))
      assert_equal "plugins/demo/CHANGELOG.md has no section for 0.2.0",
        assert_raises(Release::Failure) { tagging_release(version: "0.2.0").tag! }.message
    end
  end

  def test_a_semver_version_names_the_tag_as_written_and_the_package_as_rubygems_stores_it
    release = release(version: "1.0.0-beta.1")

    assert_equal "tokra-demo/v1.0.0-beta.1", release.tag
    assert_equal File.join(@root, "pkg/tokra-demo-1.0.0.pre.beta.1.gem"), release.package
    assert_equal "chore(demo): release 1.0.0-beta.1", release.release_subject
  end

  def test_a_dotted_version_keeps_its_dotted_tag_and_package
    release = release(version: "0.1.0.pre.4")

    assert_equal "tokra-demo/v0.1.0.pre.4", release.tag
    assert_equal File.join(@root, "pkg/tokra-demo-0.1.0.pre.4.gem"), release.package
  end

  # Pushing a tagged version: the tag is on a bare origin, the working tree
  # has moved on, and only the build and the push go through the runner,
  # with any +prepare+ commands, which run for real. The build packs what
  # the checkout holds under js/.
  private def pushing_release(version: "0.1.0-pre.1", published: [], build: true, push: true, package_version: nil,
    prepare: [], generated: []
  )
    runner = lambda do |command, chdir:|
      @ran << [command, chdir]
      case command.first(2)
      when %w[gem build]
        if build
          output = command[command.index("--output") + 1]
          write_package(output, package_version || File.read(File.join(chdir, "VERSION")), files: Dir.glob("js/*", base: chdir))
        end
        build
      when %w[gem push]
        push
      else
        system(*command, chdir:, out: File::NULL, err: File::NULL)
      end
    end
    @asked = []
    lookup = lambda do |name|
      @asked << name
      published
    end
    Release.new(root: @root, name: "tokra-demo", dir: "plugins/demo", version:, scope: "demo", runner:, published_versions: lookup,
      prepare:, generated:)
  end

  # A real package, so the release reads its version and files back as
  # RubyGems does. Each of +files+ is written beside it first.
  private def write_package(output, semver, files: [], name: "tokra-demo")
    FileUtils.mkdir_p(File.dirname(output))
    files.each do |file|
      FileUtils.mkdir_p(File.join(File.dirname(output), File.dirname(file)))
      File.write(File.join(File.dirname(output), file), "")
    end
    spec = Gem::Specification.new do |s|
      s.name = name
      s.version = GemVersion.parse(semver).rubygems
      s.summary = "demo"
      s.authors = ["Demo"]
      s.files = files
    end
    Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) do
      Dir.chdir(File.dirname(output)) { Gem::Package.build(spec, true, false, output) }
    end
  end

  private def tag_release(version)
    commit_release(version)
    git("tag", "--annotate", "tokra-demo/v#{version}", "--message", "tokra-demo #{version}")
    git("push", "--quiet", "origin", "trunk", "refs/tags/tokra-demo/v#{version}")
  end

  def test_push_builds_the_tag_from_a_clean_checkout_and_pushes_the_package
    with_origin do
      tag_release("0.1.0-pre.1")
      write("plugins/demo/VERSION", "moved on, dirty")
      package = File.join(@root, "pkg/tokra-demo-0.1.0.pre.pre.1.gem")

      pushing_release.push!
      built_in = @ran.first.last

      assert_equal ["gem", "build", "tokra-demo.gemspec", "--output", package], @ran.first.first
      refute_equal File.join(@root, "plugins/demo"), built_in
      assert_equal [["gem", "push", package], @root], @ran.last
      assert_equal ["tokra-demo"], @asked
      assert_equal "moved on, dirty", File.read(File.join(@root, "plugins/demo/VERSION"))
    end
  end

  def test_push_builds_what_the_tag_holds_and_removes_its_checkout
    with_origin do
      tag_release("0.1.0-pre.1")
      write("plugins/demo/VERSION", "moved on")
      git("commit", "--quiet", "--all", "--message", "later")

      pushing_release.push!

      assert_equal Gem::Version.new("0.1.0.pre.pre.1"), Gem::Package.new(File.join(@root, "pkg/tokra-demo-0.1.0.pre.pre.1.gem")).spec.version
      assert_empty Dir.glob(File.join(@root, "tmp/push/*"))
      refute_includes output("worktree", "list"), "tmp/push"
    end
  end

  def test_push_refuses_a_tag_origin_does_not_have
    with_origin do
      commit_release("0.1.0-pre.1")
      git("tag", "tokra-demo/v0.1.0-pre.1")

      error = assert_raises(Release::Failure) { pushing_release.push! }

      assert_equal "origin does not have tokra-demo/v0.1.0-pre.1; tag it with rake release:demo:tag first", error.message
      assert_empty @ran
      assert_empty @asked
    end
  end

  def test_push_refuses_a_version_rubygems_already_has
    with_origin do
      tag_release("0.1.0-pre.1")

      error = assert_raises(Release::Failure) { pushing_release(published: %w[0.1.0.pre.pre.1 0.1.0.pre.4]).push! }

      assert_equal "RubyGems.org already has tokra-demo 0.1.0.pre.pre.1", error.message
      assert_empty @ran
    end
  end

  def test_push_goes_ahead_when_rubygems_has_only_other_versions
    with_origin do
      tag_release("1.0.0-beta.1")

      pushing_release(version: "1.0.0-beta.1", published: %w[0.1.0.pre.4 1.0.0.pre.beta.2]).push!

      assert_equal 2, @ran.size
      assert_equal ["gem", "push", File.join(@root, "pkg/tokra-demo-1.0.0.pre.beta.1.gem")], @ran.last.first
    end
  end

  def test_push_stops_when_the_build_fails
    with_origin do
      tag_release("0.1.0-pre.1")

      assert_includes assert_raises(Release::Failure) { pushing_release(push: false, build: false).push! }.message, "gem build"
      assert_equal 1, @ran.size
      assert_empty Dir.glob(File.join(@root, "tmp/push/*"))
    end
  end

  def test_push_refuses_a_build_that_writes_no_package
    with_origin do
      tag_release("0.1.0-pre.1")
      package = File.join(@root, "pkg/tokra-demo-0.1.0.pre.pre.1.gem")
      FileUtils.mkdir_p(File.dirname(package))
      File.write(package, "a stale package")
      silent = -> (command, chdir:) { @ran << [command, chdir]; true }
      release = Release.new(root: @root, name: "tokra-demo", dir: "plugins/demo", version: "0.1.0-pre.1", scope: "demo", runner: silent, published_versions: -> (_) { [] })

      error = assert_raises(Release::Failure) { release.push! }

      assert_equal "gem build made no #{package}", error.message
      assert_equal 1, @ran.size
      refute_includes @ran.map { |command, _| command.first(2) }, %w[gem push]
    end
  end

  def test_push_refuses_a_package_of_the_wrong_version
    with_origin do
      tag_release("0.1.0-pre.1")

      error = assert_raises(Release::Failure) { pushing_release(package_version: "0.1.0-pre.2").push! }

      assert_includes error.message, "holds version 0.1.0.pre.pre.2, not 0.1.0.pre.pre.1"
      assert_equal 1, @ran.size
      assert_empty Dir.glob(File.join(@root, "tmp/push/*"))
    end
  end

  def test_push_replaces_the_checkout_a_killed_run_left_behind
    with_origin do
      tag_release("0.1.0-pre.1")
      leftover = File.join(@root, "tmp/push/tokra-demo-0.1.0-pre.1")
      git("worktree", "add", "--quiet", "--detach", leftover, "HEAD")
      File.write(File.join(leftover, "stale"), "")

      pushing_release.push!

      assert_equal 2, @ran.size
      assert_empty Dir.glob(File.join(@root, "tmp/push/*"))
    end
  end

  # tokra's checkout gets its submodule and its JavaScript templates this
  # way before the build (TOKRA_GEMS).
  def test_push_prepares_the_checkout_before_it_builds_there
    with_origin do
      tag_release("0.1.0-pre.1")

      pushing_release(prepare: [%w[mkdir js], %w[touch js/emit.js.erb]], generated: ["js/*"]).push!

      assert_equal [%w[mkdir js], %w[touch js/emit.js.erb], %w[gem build], %w[gem push]], @ran.map { |command, _| command.first(2) }
      assert_equal 1, @ran.first(3).map(&:last).uniq.size
      refute_equal File.join(@root, "plugins/demo"), @ran.first.last
      assert_includes Gem::Package.new(File.join(@root, "pkg/tokra-demo-0.1.0.pre.pre.1.gem")).spec.files, "js/emit.js.erb"
      assert_empty Dir.glob(File.join(@root, "tmp/push/*"))
    end
  end

  def test_push_refuses_a_build_without_its_generated_files
    with_origin do
      tag_release("0.1.0-pre.1")

      error = assert_raises(Release::Failure) { pushing_release(generated: ["js/*"]).push! }

      assert_includes error.message, "has no js/*"
      refute_includes @ran.map { |command, _| command.first(2) }, %w[gem push]
    end
  end

  def test_a_failing_prepare_command_stops_before_the_build
    with_origin do
      tag_release("0.1.0-pre.1")

      error = assert_raises(Release::Failure) { pushing_release(prepare: [%w[false]]).push! }

      assert_equal "false failed", error.message
      assert_equal [%w[false]], @ran.map(&:first)
      assert_empty Dir.glob(File.join(@root, "tmp/push/*"))
    end
  end

  def test_push_stops_when_the_push_fails
    with_origin do
      tag_release("0.1.0-pre.1")

      assert_includes assert_raises(Release::Failure) { pushing_release(push: false).push! }.message, "gem push"
    end
  end

  def test_push_needs_no_clean_tree_or_trunk
    with_origin do
      tag_release("0.1.0-pre.1")
      git("switch", "--quiet", "--create", "topic")
      write("plugins/demo/stray.rb", "")

      pushing_release.push!

      assert_equal 2, @ran.size
    end
  end

  # The default lookup is the only code that would touch the network, so
  # these hand it a stand-in for Net::HTTP that answers from a script.
  Network = Struct.new(:response, :asked) do
    def get_response(uri)
      asked << uri.to_s
      response
    end
  end

  private def answering(response)
    network = Network.new(response, [])
    yield network
  end

  private def http_response(klass, code, body)
    klass.new("1.1", code, "").tap do |response|
      response.instance_variable_set(:@read, true)
      response.instance_variable_set(:@body, body)
    end
  end

  def test_the_default_lookup_reads_the_numbers_rubygems_lists
    answering(http_response(Net::HTTPOK, "200", %([{"number":"0.1.0.pre.4"},{"number":"1.0.0.pre.beta.1"}]))) do |network|
      assert_equal %w[0.1.0.pre.4 1.0.0.pre.beta.1], Release::PUBLISHED_VERSIONS.call("tokra-demo", network)
      assert_equal ["https://rubygems.org/api/v1/versions/tokra-demo.json"], network.asked
    end
  end

  def test_the_default_lookup_finds_nothing_for_a_gem_rubygems_has_never_seen
    answering(http_response(Net::HTTPNotFound, "404", "This rubygem could not be found.")) do |network|
      assert_empty Release::PUBLISHED_VERSIONS.call("tokra-demo", network)
    end
  end

  def test_the_default_lookup_fails_on_any_other_answer
    answering(http_response(Net::HTTPServiceUnavailable, "503", "")) do |network|
      error = assert_raises(Release::Failure) { Release::PUBLISHED_VERSIONS.call("tokra-demo", network) }

      assert_equal "RubyGems.org answered 503 when asked for tokra-demo's versions", error.message
    end
  end
end
