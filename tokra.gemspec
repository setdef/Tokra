# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "lib/tokra/version"

Gem::Specification.new do |spec|
  spec.name = "tokra"
  spec.version = Tokra::VERSION
  spec.authors = ["Kerrick Long"]
  spec.email = ["me@kerricklong.com"]

  spec.summary = "A port of Tauri to Ruby."
  spec.description = File.read(File.expand_path("README.rdoc", __dir__))
  spec.license = "AGPL-3.0-or-later"
  spec.homepage = "https://www.tokra.app"
  spec.required_ruby_version = ">= 4.0.1"
  spec.required_rubygems_version = ">= 3.3.11"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  # spec.metadata["bug_tracker_uri"] = "https://todo.sr.ht/~kerrick/tokra"
  # spec.metadata["mailing_list_uri"] = "https://lists.sr.ht/~kerrick/tokra-discuss"
  spec.metadata["source_code_uri"] = "https://git.sr.ht/~kerrick/tokra"
  # spec.metadata["changelog_uri"] = "https://git.sr.ht/~kerrick/tokra/tree/stable/item/CHANGELOG.md"
  # spec.metadata["documentation_uri"] = "https://tokra.app/docs/"
  spec.metadata["funding_uri"] = "https://opencollective.com/tauri"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/tokra/extconf.rb"]

  # Runtime dependency for Rust extension
  spec.add_dependency "rb_sys", "~> 0.9.91"

  # Development dependencies

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
