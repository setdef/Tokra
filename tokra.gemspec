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
  spec.metadata["source_code_uri"] = "https://github.com/setdef/Tokra"
  # spec.metadata["changelog_uri"] = "https://github.com/setdef/Tokra/blob/stable/CHANGELOG.md"
  # spec.metadata["documentation_uri"] = "https://tokra.app/docs/"
  spec.metadata["funding_uri"] = "https://opencollective.com/tauri"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Ship what an installed app loads and what compiles the native extension:
  # the Ruby library, its signatures, the crate, and the Cargo workspace and
  # lockfile that pin the crate's dependencies (Plan 017). Listing paths keeps
  # development files (plans, chats, tasks, tests, tool configuration) out
  # without a deny list that every new file has to remember.
  packaged = %w[lib sig ext/tokra Cargo.toml Cargo.lock README.rdoc CHANGELOG.md LICENSE LICENSES]
  spec.files = IO.popen(["git", "ls-files", "-z", "--", *packaged], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true)
  end
  # Add the vendored Tauri scripts (rake sync:tauri), which are .gitignore'd
  # but loaded at runtime by Native.load_js_template. Glob relative to this
  # file so the list does not depend on the current directory.
  spec.files += Dir.glob("lib/tokra/js/*", base: __dir__)
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/tokra/extconf.rb"]

  # Runtime dependency for Rust extension
  spec.add_dependency "rb_sys", "~> 0.9.129"

  # Development dependencies

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
