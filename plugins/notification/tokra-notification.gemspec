# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "lib/tokra/plugins/notification/version"

Gem::Specification.new do |spec|
  spec.name = "tokra-notification"
  spec.version = Tokra::Plugins::Notification::VERSION
  spec.authors = ["Kerrick Long"]
  spec.email = ["me@kerricklong.com"]

  spec.summary = "Desktop notifications for Tokra applications"
  spec.description = File.read(File.expand_path("README.rdoc", __dir__))
  spec.license = "AGPL-3.0-or-later"
  spec.homepage = "https://tokra.app"
  spec.required_ruby_version = ">= 4.0.1"
  spec.required_rubygems_version = ">= 3.3.11"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/setdef/Tokra/tree/trunk/plugins/notification"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Ship what an installed app loads. The plugin is pure Ruby: the
  # notifications go out through ferro-notify-rust, and attachment URLs
  # are read with ferro-url and scheduled dates with ferro-time (ADR 011,
  # plans 024, 030, and 031).
  packaged = %w[lib sig README.rdoc]
  spec.files = IO.popen(["git", "ls-files", "-z", "--", *packaged], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true)
  end
  spec.require_paths = ["lib"]

  # An exact pin: a prerelease promises no API between prereleases, and
  # RubyGems considers prereleases only for a requirement that names one.
  spec.add_dependency "ferro-notify-rust", "= 0.1.0.pre.3"
  spec.add_dependency "ferro-time", "= 0.1.0.pre.1"
  spec.add_dependency "ferro-url", "= 0.1.0.pre.1"
  spec.add_dependency "tokra", "~> 0.0"
end
