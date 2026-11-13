# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# One gem this repository publishes, as the bump and release tasks see it.
#
# Tokra publishes six gems: tokra at the root, and a plugin gem in each
# folder under <tt>plugins/</tt>. Each has its own version.rb, gemspec,
# Gemfile.lock, and CHANGELOG.md in its folder, and each releases on its
# own, under a tag named for it (Plan 059). The tasks build every name they
# need from this description, so adding a plugin means adding an entry to
# TOKRA_GEMS.
#
# [short_name] The name in task names and commit scopes: +tokra+ for
#   <tt>rake bump:tokra:minor</tt>, +dialog+ for
#   <tt>chore(dialog): release 0.1.0</tt>.
# [name] The gem's name, such as <tt>tokra-dialog</tt>.
# [dir] The gem's folder, relative to the repository: <tt>.</tt> for tokra.
# [version_file] The file that defines VERSION, relative to +dir+.
# [crate] The native crate's folder, relative to +dir+, whose Cargo.toml
#   carries the gem's version too; nil for a pure-Ruby plugin.
# [generated] Globs, relative to +dir+, of git-ignored files the gemspec
#   packs by hand, which a release checks the built package holds.
# [prepare] Commands that make those files in a clean checkout of a tag,
#   run there before the build; given the repository's root, which a
#   command may borrow from.
class TokraGem < Data.define(:short_name, :name, :dir, :version_file, :crate, :generated, :prepare)
  # Creates the description of a pure-Ruby gem unless told otherwise.
  def initialize(crate: nil, generated: [], prepare: -> (_root) { [] }, **fields)
    super
  end

  # The plugin gem in <tt>plugins/<short_name></tt>, whose VERSION lives
  # in <tt>lib/tokra/plugins/<short_name, snake-cased>/version.rb</tt>.
  def self.plugin(short_name)
    new(short_name:, name: "tokra-#{short_name}", dir: File.join("plugins", short_name),
      version_file: File.join("lib/tokra/plugins", short_name.tr("-", "_"), "version.rb"))
  end

  # Whether this is tokra itself, which every plugin depends on.
  def core?
    dir == "."
  end

  # +relative+, a path inside the gem, as a path inside the repository:
  # <tt>CHANGELOG.md</tt> for tokra, <tt>plugins/dialog/CHANGELOG.md</tt>
  # for tokra-dialog.
  def path(relative)
    core? ? relative : File.join(dir, relative)
  end

  # The gem's changelog, relative to the gem.
  def changelog
    "CHANGELOG.md"
  end

  # The gemspec, relative to the gem.
  def gemspec
    "#{name}.gemspec"
  end

  # The native extension's name, as Cargo.lock knows it.
  def extension_name
    crate && File.basename(crate)
  end

  # What comes before the version in the gem's release tags:
  # <tt>tokra-dialog/v</tt>, so <tt>tokra-dialog/v0.1.0</tt>.
  def tag_prefix
    "#{name}/v"
  end

  # The version as version.rb writes it, such as <tt>0.1.0</tt>: what tags
  # and CHANGELOG headings use.
  def written_version(root = Dir.pwd)
    File.read(File.join(root, path(version_file)))[/(?<=VERSION = ")[^"]+(?=")/] or
      raise "#{path(version_file)} has no VERSION"
  end
end

# The gems this repository publishes, in the order they go to RubyGems.org
# (Plan 059): tokra first, since every plugin depends on it.
TOKRA_GEMS = [
  TokraGem.new(
    short_name: "tokra",
    name: "tokra",
    dir: ".",
    version_file: "lib/tokra/version.rb",
    crate: "ext/tokra",
    # The JavaScript templates rake sync:tauri extracts from the Tauri
    # submodule, which git ignores and the gemspec adds by hand.
    generated: ["lib/tokra/js/*"],
    # A fresh checkout has no submodule. It borrows the objects of the
    # repository's own, which the gate keeps checked out, so nothing is
    # fetched that is already here.
    prepare: lambda do |root|
      [
        ["git", "submodule", "update", "--init", "--reference", File.join(root, "vendor/tauri"), "vendor/tauri"],
        ["bundle", "exec", "rake", "sync:tauri"],
      ]
    end,
  ),
  *%w[log clipboard dialog notification global-shortcut].map { |short_name| TokraGem.plugin(short_name) },
].freeze
