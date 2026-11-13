# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "release"
require_relative "tokra_gems"

# Replaces bundler/gem_tasks, whose v0.1.0 tags would collide between
# Tokra's gems (Plan 059). release:<gem>:tag tags the release commit a bump
# made, <gem-name>/vX.Y.Z, and pushes only the tag. release:<gem> builds the
# gem, pushes trunk, tags it, and pushes the tag and the gem to
# RubyGems.org, and release:<gem>:push[version] pushes an already-tagged
# version there from a clean checkout of its tag. Only the maintainer runs
# any of them (AGENTS.md, Committing).
namespace :release do
  TOKRA_GEMS.each do |gem|
    release = lambda do |version = gem.written_version|
      Release.new(root: Dir.pwd, name: gem.name, dir: gem.dir, version:, scope: gem.short_name, generated: gem.generated,
        prepare: gem.prepare.call(Dir.pwd))
    end

    desc "Tag #{gem.tag_prefix}X.Y.Z, push it, and push the gem to RubyGems (maintainer only)"
    task gem.short_name do
      release.call.run!
    rescue Release::Failure => e
      abort "❌ #{e.message}"
    end

    namespace gem.short_name do
      desc "Tag #{gem.name}'s release commit #{gem.tag_prefix}X.Y.Z and push only the tag (maintainer only)"
      task :tag do
        release.call.tag!
      rescue Release::Failure => e
        abort "❌ #{e.message}"
      end

      desc "Push #{gem.name}'s tagged version to RubyGems (maintainer only; push[0.1.0], default the version.rb one)"
      task :push, [:version] do |_, args|
        release.call(*args[:version]).push!
      rescue Release::Failure, ArgumentError => e
        abort "❌ #{e.message}"
      end
    end
  end
end
