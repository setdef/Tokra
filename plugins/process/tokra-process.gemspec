# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "lib/tokra/plugins/process/version"

Gem::Specification.new do |spec|
  spec.name = "tokra-process"
  spec.version = Tokra::Plugins::Process::VERSION
  spec.authors = ["Kerrick Long"]
  spec.email = ["me@kerricklong.com"]

  spec.summary = "Exit or restart a Tokra application from its frontend"
  spec.description = File.read(File.expand_path("README.rdoc", __dir__))
  spec.license = "AGPL-3.0-or-later"
  spec.homepage = "https://www.tokra.app"
  spec.required_ruby_version = ">= 4.0.1"
  spec.required_rubygems_version = ">= 3.3.11"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/setdef/Tokra/tree/trunk/plugins/process"
  spec.metadata["changelog_uri"] = "https://github.com/setdef/Tokra/blob/trunk/plugins/process/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Ship only what an installed app loads (Plan 017). The plugin is pure
  # Ruby and needs nothing but Tokra, whose AppHandle exits and restarts
  # (Plan 066).
  packaged = %w[lib sig README.rdoc CHANGELOG.md]
  spec.files = IO.popen(["git", "ls-files", "-z", "--", *packaged], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true)
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "tokra", "~> 0.0"
end
