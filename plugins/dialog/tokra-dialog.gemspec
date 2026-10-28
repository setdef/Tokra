# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "lib/tokra/plugins/dialog/version"

Gem::Specification.new do |spec|
  spec.name = "tokra-dialog"
  spec.version = Tokra::Plugins::Dialog::VERSION
  spec.authors = ["Kerrick Long"]
  spec.email = ["me@kerricklong.com"]

  spec.summary = "Native file and message dialogs for Tokra desktop applications"
  spec.description = File.read(File.expand_path("README.rdoc", __dir__))
  spec.license = "AGPL-3.0-or-later"
  spec.homepage = "https://tokra.app"
  spec.required_ruby_version = ">= 4.0.1"
  spec.required_rubygems_version = ">= 3.3.11"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/setdef/Tokra/tree/trunk/plugins/dialog"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Ship what an installed app loads. The plugin is pure Ruby: the native
  # dialogs come from ferro-rfd (ADR 011, Plan 023).
  packaged = %w[lib sig README.rdoc]
  spec.files = IO.popen(["git", "ls-files", "-z", "--", *packaged], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true)
  end
  spec.require_paths = ["lib"]

  # An exact pin: a prerelease promises no API between prereleases, and
  # RubyGems considers prereleases only for a requirement that names one.
  spec.add_dependency "ferro-rfd", "= 0.1.0.pre.3"
  spec.add_dependency "tokra", "~> 0.0"
end
