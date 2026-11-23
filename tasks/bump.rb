# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "date"
require "open3"
require_relative "changelog"
require_relative "gem_version"

# Bumps one gem's version and commits the release.
#
# A gem's version lives in several files besides its CHANGELOG: version.rb,
# which the gemspec reads, and the gem's Gemfile.lock, which records it as
# a path gem. tokra's also lives in its crate's Cargo.toml and in
# Cargo.lock, which spell it Cargo's way, and in each plugin's
# Gemfile.lock, since every plugin bundles the tokra beside it. Editing
# them by hand, one is always missed. This bump rewrites them all, releases
# the CHANGELOG's Unreleased entries, runs the gate, and commits
# <tt>chore(dialog): release 0.1.0</tt>, a scoped Conventional Commit.
# Tagging that commit is a separate step (Release#tag!).
#
# A tokra release that moves its minor version also raises each plugin's
# floor to it, <tt>~> 0.1</tt> in the gemspec and its Gemfile.lock, in the
# same commit. A plugin is only ever tested against the tokra beside it,
# so a plugin released after tokra 0.1.0 cannot promise to work with an
# older one; and tokra 0.0.1.pre.2, which <tt>~> 0.0</tt> admits, lacks
# the plugin hooks every plugin calls (Plan 059). A prerelease leaves the
# floor where it is: <tt>~> 0.2</tt> would refuse 0.2.0-beta.1 itself.
#
# This is Ferro's <tt>tasks/bump.rb</tt>, by the same author under the same
# license, which follows ratatui_ruby-devtools 0.4.1's bump workflow
# (<tt>lib/ratatui_ruby/devtools/tasks/bump/bump_workflow.rb</tt>). It bumps
# only on a clean trunk, and refuses a stable 1.0 or later until Tokra has
# a release-branch policy. A prerelease is an opt-in preview of a coming
# release, so the first public versions are plain 0.x releases, and a
# dotted <tt>0.0.1.pre.2</tt> is released as <tt>0.1.0</tt> with a minor
# bump and no label (Plan 059, Versions).
#
# Versions are written as SemVer, <tt>1.0.0-beta.1</tt>, in version.rb, the
# CHANGELOG, and the tag; Gemfile.lock holds RubyGems' form,
# <tt>1.0.0.pre.beta.1</tt> (GemVersion).
class Bump
  # Raised when the bump must not proceed; the message says why.
  class Failure < StandardError; end

  # The footer AGENTS.md asks every commit to end with.
  FOOTER = "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"

  # Where version.rb writes the version.
  VERSION = /(?<=VERSION = ")[^"]+(?=")/

  # [root] The repository root.
  # [gem] The TokraGem to bump.
  # [dependents] The TokraGems whose gemspecs depend on +gem+, whose
  #   Gemfile.locks bundle it, and whose floor follows it: every plugin when
  #   +gem+ is tokra, none otherwise.
  # [gate] Runs the gate; returns whether it passed.
  # [date] The release date for the CHANGELOG.
  def initialize(root:, gem:, dependents: [], gate: -> { system("bundle", "exec", "rake", chdir: root) }, date: Date.today)
    @root = root
    @gem = gem
    @dependents = dependents
    @gate = gate
    @date = date
  end

  # The version the gem has now.
  def current
    GemVersion.parse(File.read(path(@gem.version_file))[VERSION] || raise(Failure, "#{@gem.path(@gem.version_file)} has no VERSION"))
  end

  # Bumps to the version the block returns, given the current one.
  def run!
    preflight!
    from = current
    target = yield(from)
    check_target!(from, target)
    commit!(from, target)
  rescue Changelog::Failure, ArgumentError => e
    raise Failure, e.message
  end

  # Releases the version the gem has now, without moving it.
  #
  # A new gem starts at <tt>0.1.0</tt> with its changes under Unreleased.
  # #run! only moves forward, so without this the first release would skip
  # to <tt>0.1.1</tt>. Releasing the current version is safe only while nobody has it,
  # so this refuses when the gem's tag exists here or on origin (asking
  # origin, so a missing remote is a failure, not a pass), when the
  # CHANGELOG already has the version's section, or when a later version is
  # already tagged here or in the CHANGELOG.
  def release_current!
    preflight!
    version = current
    check_unreleased!(version)
    check_target!(nil, version)
    commit!(version, version)
  rescue Changelog::Failure, ArgumentError => e
    raise Failure, e.message
  end

  # The release commit's message: a scoped Conventional Commit subject, a
  # short prose body, and the footer AGENTS.md asks for.
  # +raised+ is the floor the dependents' bound moved to, if it moved.
  def commit_message(target, raised: nil)
    places = @gem.crate ? "version.rb, the crate's Cargo.toml, Cargo.lock, and the Gemfile.lock" : "version.rb and its Gemfile.lock"
    places += ", and each plugin's Gemfile.lock," unless @dependents.empty?
    floor = raised ? " Each plugin now requires #{@gem.name} ~> #{raised}, since a plugin is only ever tested " \
      "against the #{@gem.name} beside it." : ""
    <<~MESSAGE
      chore(#{@gem.short_name}): release #{target}

      #{wrap("Release #{@gem.name} #{target}. The entries that were under Unreleased in its CHANGELOG are now the " \
        "#{target} section, dated #{@date.iso8601}, and #{places} name #{target}.#{floor} " \
        "Tag it with rake release:#{@gem.short_name}:tag.")}

      #{FOOTER}
    MESSAGE
  end

  # Writes +target+ over +from+, runs the gate, and commits the release.
  private def commit!(from, target)
    raised = edit(from, target)
    raise Failure, "the gate failed; #{target}'s changes are left uncommitted for you to inspect" unless @gate.call

    git("add", "--", *files)
    git("commit", "--quiet", "--message", commit_message(target, raised:))
    target
  end

  # Rewrites every file, or none: the tree was clean, so a failure part way
  # restores what was written. Returns the floor the dependents' bound
  # moved to, or nil.
  private def edit(from, target)
    Changelog.new(path(@gem.changelog), tag_prefix: @gem.tag_prefix).release(target, date: @date)
    write_versions(from, target)
  rescue Failure, Changelog::Failure
    git("checkout", "--", *files)
    raise
  end

  # +text+ wrapped at 72 columns, as commit bodies are.
  private def wrap(text)
    text.gsub(/(.{1,72})(?:\s+|\z)/, "\\1\n").chomp
  end

  private def preflight!
    branch = git("rev-parse", "--abbrev-ref", "HEAD").strip
    raise Failure, "bump on trunk, not #{branch}" unless branch == "trunk"
    raise Failure, "commit or stash your changes first" unless git("status", "--porcelain").empty?
  end

  # Refuses a +version+ anyone could already have.
  private def check_unreleased!(version)
    tag = "#{@gem.tag_prefix}#{version}"
    _, status = Open3.capture2e("git", "rev-parse", "--quiet", "--verify", "refs/tags/#{tag}", chdir: @root)
    raise Failure, "#{tag} already exists, so #{version} is released; bump past it" if status.success?
    unless git("ls-remote", "--tags", "origin", "refs/tags/#{tag}").empty?
      raise Failure, "origin already has #{tag}, so #{version} is released; bump past it"
    end
    if Changelog.new(path(@gem.changelog), tag_prefix: @gem.tag_prefix).released?(version)
      raise Failure, "#{@gem.path(@gem.changelog)} already has a #{version} section; bump past it"
    end

    newest = released_versions.max
    raise Failure, "#{version} is below #{newest}, which is released; bump past it" if newest && newest > version
  end

  # The versions the gem's local tags and CHANGELOG sections name.
  private def released_versions
    tags = git("tag", "--list", "#{@gem.tag_prefix}*").lines.map { |line| line.strip.delete_prefix(@gem.tag_prefix) }
    sections = File.read(path(@gem.changelog)).scan(/^## \[([^\]]+)\]/).flatten - ["Unreleased"]
    (tags + sections).filter_map do |text|
      GemVersion.parse(text)
    rescue ArgumentError
      nil
    end
  end

  # Refuses a +target+ that does not follow +from+ (+nil+ when the version
  # stays), or a stable one.
  private def check_target!(from, target)
    raise Failure, "#{target} does not come after #{from}" if from && !(target > from)
    return unless target.stable?

    raise Failure, "#{target} is 1.0 or later, which needs a release-branch policy Tokra does not have yet (Plan 059)"
  end

  # Returns the floor the dependents' bound moved to, or nil.
  private def write_versions(from, target)
    rewrite(@gem.version_file, VERSION, target.to_s, "VERSION")
    write_crate(target) if @gem.crate
    write_lock(@gem.path("Gemfile.lock"), from, target)
    example_locks.each { |relative| write_lock(relative, from, target) }
    floor = floor_for(target)
    moved = @dependents.map do |dependent|
      write_lock(dependent.path("Gemfile.lock"), from, target)
      floor && write_floor(dependent, floor)
    end
    floor if moved.any?
  end

  # Sets the crate's version to +target+. tokra's crate stood at 0.1.0
  # while the gem was 0.0.1.pre.2, so unlike a Ferro gem's it is set to the
  # gem's version whatever it held, which brings it into step.
  private def write_crate(target)
    rewrite(File.join(@gem.crate, "Cargo.toml"), /^(\[package\]\n(?:(?:[^\[\n][^\n]*)?\n)*?)version = "[^"]*"$/,
      %(\\1version = "#{target.cargo}"), "[package] version")
    rewrite("Cargo.lock", /^(name = "#{Regexp.escape(@gem.extension_name)}"\nversion = )"[^"]*"$/,
      %(\\1"#{target.cargo}"), "#{@gem.extension_name} package")
  end

  # Moves the gem's own entries in the Gemfile.lock at +relative+, from the
  # repository, from +from+ to +target+.
  private def write_lock(relative, from, target)
    file = File.join(@root, relative)
    text = File.read(file)
    pattern = /^( +#{Regexp.escape(@gem.name)}) \(#{Regexp.escape(from.rubygems)}\)$/
    raise Failure, "#{relative} does not list #{@gem.name} #{from.rubygems}" unless text.match?(pattern)

    File.write(file, text.gsub(pattern, "\\1 (#{target.rubygems})"))
  end

  # The floor, such as <tt>0.1</tt>, that the dependents' bound on the gem
  # takes when it releases +target+: its major and minor version. None for
  # a prerelease, which keeps the floor below it.
  private def floor_for(target)
    target.rubygems.split(".").first(2).join(".") unless target.prerelease?
  end

  # Moves +dependent+'s bound on the gem to <tt>~> floor</tt>, in its
  # gemspec and in its Gemfile.lock's record of that gemspec. Returns
  # whether the bound moved.
  private def write_floor(dependent, floor)
    gemspec = File.join(@root, dependent.path(dependent.gemspec))
    dependency = /^(\s*spec\.add_dependency "#{Regexp.escape(@gem.name)}", "~> )([^"]+)"$/
    before = File.read(gemspec)[dependency, 2]
    rewrite_file(gemspec, dependent.path(dependent.gemspec), dependency, %(\\1#{floor}"), "#{@gem.name} ~> bound")
    lock = File.join(@root, dependent.path("Gemfile.lock"))
    locked = /^(      #{Regexp.escape(@gem.name)} \(~> )[^)]+\)$/
    rewrite_file(lock, dependent.path("Gemfile.lock"), locked, "\\1#{floor})", "#{@gem.name} ~> bound")
    before != floor
  end

  # Replaces +pattern+ in the gem's file at +relative+, failing when the
  # file does not hold +what+.
  private def rewrite(relative, pattern, replacement, what)
    rewrite_file(path(relative), @gem.path(relative), pattern, replacement, what)
  end

  private def rewrite_file(file, shown, pattern, replacement, what)
    text = File.read(file)
    raise Failure, "#{shown} has no #{what}; keep it equal to the gem's version" unless text.match?(pattern)

    File.write(file, text.sub(pattern, replacement))
  end

  # Every file a bump may write, relative to the repository.
  private def files
    own = [@gem.version_file, @gem.changelog, "Gemfile.lock"]
    own += [File.join(@gem.crate, "Cargo.toml"), "Cargo.lock"] if @gem.crate
    own.map { |relative| @gem.path(relative) } + example_locks +
      @dependents.flat_map { |dependent| [dependent.path("Gemfile.lock"), dependent.path(dependent.gemspec)] }
  end

  # The examples' tracked lockfiles that list the gem, relative to the
  # repository. An example takes the gem by path from this checkout, so
  # its lockfile names the gem's version, and a release that left it
  # behind would tag an example whose bundle no longer matches.
  private def example_locks
    @example_locks ||= git("ls-files", "-z", "--", "examples/*/Gemfile.lock").split("\0").select do |relative|
      File.read(File.join(@root, relative)).match?(/^ +#{Regexp.escape(@gem.name)} \(/)
    end
  end

  private def path(relative)
    File.join(@root, @gem.path(relative))
  end

  private def git(*arguments)
    output, status = Open3.capture2e("git", *arguments, chdir: @root)
    raise Failure, "git #{arguments.join(' ')} failed: #{output}" unless status.success?

    output
  end
end
