# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "lib/tokra/plugins/clipboard/version"

Gem::Specification.new do |spec|
  spec.name = "tokra-clipboard"
  spec.version = Tokra::Plugins::Clipboard::VERSION
  spec.authors = ["Kerrick Long"]
  spec.email = ["me@kerricklong.com"]

  spec.summary = "Clipboard plugin for Tokra desktop applications"
  spec.description = File.read(File.expand_path("README.rdoc", __dir__))
  spec.license = "AGPL-3.0-or-later"
  spec.homepage = "https://tokra.app"
  spec.required_ruby_version = ">= 4.0.1"
  spec.required_rubygems_version = ">= 3.3.11"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/setdef/Tokra/tree/trunk/plugins/clipboard"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Ship what an installed app loads. The plugin is pure Ruby: the native
  # clipboard comes from ferro-arboard (ADR 011, Plan 021).
  packaged = %w[lib sig README.rdoc]
  spec.files = IO.popen(["git", "ls-files", "-z", "--", *packaged], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true)
  end
  spec.require_paths = ["lib"]

  # An exact pin: a prerelease promises no API between prereleases, and
  # RubyGems considers prereleases only for a requirement that names one.
  spec.add_dependency "ferro-arboard", "= 0.1.0.pre.2"
  spec.add_dependency "tokra", "~> 0.0"
end
