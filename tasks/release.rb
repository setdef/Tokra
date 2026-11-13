# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "json"
require "net/http"
require "open3"
require "rubygems/package"
require_relative "changelog"
require_relative "gem_version"

# Tags and publishes one gem.
#
# Bundler's release task tags each release <tt>v0.1.0</tt>, as tokra's
# <tt>v0.0.1.pre.2</tt> was. In a repository of seven gems, each with its own
# version, those tags collide. This release names the tag for the gem,
# <tt>tokra/v0.1.0</tt> or <tt>tokra-dialog/v0.1.0</tt> (Plan 059), and
# otherwise does what Bundler's does: build the gem, push the branch, tag
# the commit, push the tag, and push the gem. The branch goes before the
# tag because a push of it runs the gate (the pre-push hook): a push the
# gate refuses then leaves no tag behind for the next try to trip over.
#
# A release can also stop at the tag (#tag!), and push the tagged version
# to RubyGems.org afterwards (#push!). The tag goes on the commit the bump
# made (Bump), so it names exactly the release the CHANGELOG describes.
# Every step here is the maintainer's alone (AGENTS.md, Committing).
#
# The version is the SemVer string version.rb holds, <tt>1.0.0-beta.1</tt>,
# and the tag and the CHANGELOG heading spell it that way. The built
# package's file name spells it as RubyGems stores it,
# <tt>tokra-1.0.0.pre.beta.1.gem</tt> (GemVersion).
#
# This is Ferro's <tt>tasks/release.rb</tt>, by the same author under the
# same license, with one addition. tokra's gemspec packs files git ignores,
# the JavaScript templates <tt>rake sync:tauri</tt> extracts from the Tauri
# submodule. A clean checkout of a tag has neither the submodule nor the
# templates, and a gem built there without them would install and then
# fail to load. So a release runs the gem's +prepare+ commands in that
# checkout before the build, and refuses any package, built anywhere, that
# lacks a file its +generated+ globs name.
class Release
  # The branch releases come from.
  BRANCH = "trunk"

  # Raised when a release must not proceed; the message says why.
  class Failure < StandardError; end

  # Where the versions RubyGems.org has of a gem are listed, given its name.
  VERSIONS_URL = "https://rubygems.org/api/v1/versions/%<name>s.json"

  # Asks RubyGems.org which versions of the gem +name+ it has, as the
  # strings it stores, such as <tt>1.0.0.pre.beta.1</tt>. A gem it has never
  # seen has none.
  #
  # Tests pass +http+, anything with Net::HTTP's +get_response+.
  PUBLISHED_VERSIONS = lambda do |name, http = Net::HTTP|
    response = http.get_response(URI(format(VERSIONS_URL, name:)))
    case response
    when Net::HTTPNotFound then []
    when Net::HTTPSuccess then JSON.parse(response.body).map { |entry| entry.fetch("number") }
    else raise Failure, "RubyGems.org answered #{response.code} when asked for #{name}'s versions"
    end
  end

  # [root] The repository root.
  # [name] The gem's name, such as <tt>tokra-dialog</tt>.
  # [dir] The gem's directory, relative to +root+: <tt>.</tt> for tokra.
  # [version] The version to release, as version.rb writes it.
  # [scope] The gem's commit scope, such as <tt>dialog</tt>.
  # [runner] Runs one command (an Array) in a directory; returns whether
  #   it succeeded. Tests pass a recorder.
  # [published_versions] Given the gem's name, returns the versions
  #   RubyGems.org has. Tests pass a stand-in; nothing else touches the
  #   network.
  # [generated] Globs, relative to the gem, of git-ignored files the
  #   package holds, which the build is checked for.
  # [prepare] Commands that make those files in a clean checkout, run in
  #   the checkout's gem directory before #push! builds there.
  def initialize(root:, name:, dir:, version:, scope:, runner: -> (command, chdir:) { system(*command, chdir:) },
    published_versions: PUBLISHED_VERSIONS, generated: [], prepare: []
  )
    @root = root
    @name = name
    @dir = dir
    @version = version
    @scope = scope
    @runner = runner
    @published_versions = published_versions
    @generated = generated
    @prepare = prepare
  end

  # The subject of the commit that released this version.
  def release_subject
    "chore(#{@scope}): release #{@version}"
  end

  # The release's git tag.
  def tag
    "#{@name}/v#{@version}"
  end

  # The package the release builds and pushes.
  def package
    File.join(@root, "pkg", "#{@name}-#{GemVersion.parse(@version).rubygems}.gem")
  end

  # Raises Failure unless the repository is ready: on trunk, with a clean
  # tree, no tag for this version yet, and a CHANGELOG section for it.
  def preflight!
    branch = git("rev-parse", "--abbrev-ref", "HEAD").strip
    raise Failure, "release from #{BRANCH}, not #{branch}" unless branch == BRANCH
    raise Failure, "commit or stash your changes first" unless git("status", "--porcelain").empty?
    raise Failure, "#{tag} already exists" if tagged?

    changelog = Changelog.new(File.join(@root, @dir, "CHANGELOG.md"), tag_prefix: "#{@name}/v")
    shown = File.join(@dir, "CHANGELOG.md").delete_prefix("./")
    raise Failure, "#{shown} has no section for #{@version}" unless changelog.released?(@version)
  end

  # Tags the commit that released this version and pushes only the tag.
  # Raises Failure, before running anything, unless #preflight! passes,
  # trunk matches origin's, origin has no such tag either, and trunk holds
  # the commit #release_subject names.
  def tag!
    preflight!
    git("fetch", "--quiet", "origin", "refs/heads/#{BRANCH}")
    unless git("rev-parse", "HEAD") == git("rev-parse", "FETCH_HEAD")
      raise Failure, "#{BRANCH} differs from origin's; pull or push it first"
    end
    raise Failure, "origin already has #{tag}" unless git("ls-remote", "--tags", "origin", "refs/tags/#{tag}").empty?

    commit = release_commit or raise Failure, "#{BRANCH} has no commit \"#{release_subject}\"; run rake bump:#{@scope}:... first"
    [
      ["git", "tag", "--annotate", tag, commit, "--message", "#{@name} #{@version}"],
      ["git", "push", "origin", "refs/tags/#{tag}"],
    ].each { |command| raise Failure, "#{command.join(' ')} failed" unless @runner.call(command, chdir: @root) }
  end

  # Pushes a version that is already tagged to RubyGems.org, built from a
  # clean checkout of origin's tag, never from the working tree.
  #
  # Raises Failure, before building anything, unless origin has the tag and
  # RubyGems.org does not have the version. Then it checks the tag out into
  # <tt>tmp/push/</tt> as a git worktree (the gemspec lists its files with
  # <tt>git ls-files</tt>), runs the +prepare+ commands there, builds the
  # gem, pushes it, and removes the checkout. It needs no particular branch
  # and no clean tree.
  def push!
    raise Failure, "origin does not have #{tag}; tag it with rake release:#{@scope}:tag first" if remote_tag.empty?

    number = GemVersion.parse(@version).rubygems
    if @published_versions.call(@name).any? { |published| Gem::Version.new(published) == Gem::Version.new(number) }
      raise Failure, "RubyGems.org already has #{@name} #{number}"
    end

    git("fetch", "--quiet", "origin", "refs/tags/#{tag}")
    in_checkout_of("FETCH_HEAD") { |checkout| build_and_push(checkout) }
  end

  # The commands a release runs, each with the directory it runs in.
  def commands
    [
      [["gem", "build", "#{@name}.gemspec", "--output", package], File.join(@root, @dir)],
      [["git", "push", "origin", BRANCH], @root],
      [["git", "tag", "--annotate", tag, "--message", "#{@name} #{@version}"], @root],
      [["git", "push", "origin", tag], @root],
      [["gem", "push", package], @root],
    ]
  end

  # Checks, then runs each command, stopping at the first that fails. The
  # package is checked (#check_package!) after the build, before anything
  # is pushed.
  def run!
    preflight!
    FileUtils.mkdir_p(File.dirname(package))
    FileUtils.rm_f(package)
    commands.each_with_index do |(command, chdir), index|
      raise Failure, "#{command.join(' ')} failed" unless @runner.call(command, chdir:)

      check_package! if index.zero?
    end
  end

  private def remote_tag
    git("ls-remote", "--tags", "origin", "refs/tags/#{tag}")
  end

  # Yields a clean checkout of +revision+ under <tt>tmp/push/</tt>, and
  # removes it afterwards.
  private def in_checkout_of(revision)
    checkout = File.join(@root, "tmp", "push", "#{@name}-#{@version}")
    FileUtils.mkdir_p(File.dirname(checkout))
    clear_leftover(checkout)
    git("worktree", "add", "--quiet", "--detach", checkout, revision)
    begin
      yield checkout
    ensure
      begin
        git("worktree", "remove", "--force", checkout)
      rescue Failure => e
        warn "could not remove #{checkout}: #{e.message}"
      end
    end
  end

  # Removes what a killed run left at +checkout+, so the next run can add
  # its worktree there.
  private def clear_leftover(checkout)
    return unless File.exist?(checkout)

    Open3.capture2e("git", "worktree", "remove", "--force", checkout, chdir: @root)
    FileUtils.rm_rf(checkout)
    git("worktree", "prune")
  end

  # Builds the package and pushes it, once the package holds this version.
  # The package is deleted first, because +gem build --output+ leaves an
  # old one in place if it fails to write a new one, and the build is
  # checked by reading the package back, since a tag whose version.rb says
  # something else builds a different version than the tag names.
  private def build_and_push(checkout)
    FileUtils.mkdir_p(File.dirname(package))
    FileUtils.rm_f(package)
    gem_dir = File.join(checkout, @dir)
    @prepare.each { |command| raise Failure, "#{command.join(' ')} failed" unless @runner.call(command, chdir: gem_dir) }
    build = ["gem", "build", "#{@name}.gemspec", "--output", package]
    raise Failure, "#{build.join(' ')} failed" unless @runner.call(build, chdir: gem_dir)

    check_package!

    push = ["gem", "push", package]
    raise Failure, "#{push.join(' ')} failed" unless @runner.call(push, chdir: @root)
  end

  # Refuses a package that is missing, holds another version, or lacks a
  # file a +generated+ glob names.
  private def check_package!
    raise Failure, "gem build made no #{package}" unless File.exist?(package)

    spec = Gem::Package.new(package).spec
    wanted = Gem::Version.new(GemVersion.parse(@version).rubygems)
    unless spec.version == wanted
      raise Failure, "#{package} holds version #{spec.version}, not #{wanted}; does the tag's version.rb say #{@version}?"
    end

    missing = @generated.reject { |glob| spec.files.any? { |file| File.fnmatch?(glob, file, File::FNM_PATHNAME) } }
    return if missing.empty?

    raise Failure, "#{package} has no #{missing.join(', ')}; the gemspec packs them only once they are generated"
  end

  # The newest commit on trunk's first-parent history with the release
  # subject, or nil.
  private def release_commit
    git("log", "--first-parent", "--format=%H %s", BRANCH).lines.map { |line| line.chomp.split(" ", 2) }
      .find { |_, subject| subject == release_subject }&.first
  end

  private def tagged?
    _, status = Open3.capture2e("git", "rev-parse", "--quiet", "--verify", "refs/tags/#{tag}", chdir: @root)
    status.success?
  end

  private def git(*arguments)
    output, status = Open3.capture2e("git", *arguments, chdir: @root)
    raise Failure, "git #{arguments.join(' ')} failed: #{output}" unless status.success?

    output
  end
end
