# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

source "https://rubygems.org"

# Specify your gem's dependencies in tokra.gemspec
gemspec

# tokra-clipboard builds on ferro-arboard (ADR 011). Ferro releases are
# tags on its repository; Tokra depends only on released versions, never a
# path source, so a contributor needs only this clone.
gem "ferro-arboard", git: "https://github.com/setdef/Ferro", tag: "ferro-arboard/v0.1.0.pre.2", glob: "gems/*/*.gemspec"
# tokra-dialog builds on ferro-rfd (Plan 023). Its glob names only ferro-rfd,
# so ferro-arboard still comes from its own tag.
gem "ferro-rfd", git: "https://github.com/setdef/Ferro", tag: "ferro-rfd/v0.1.0.pre.2", glob: "gems/rfd/*.gemspec"
# tokra-notification builds on ferro-notify-rust (Plan 024). Its glob names
# only ferro-notify-rust, so the other Ferro gems keep their own tags.
gem "ferro-notify-rust", git: "https://github.com/setdef/Ferro", tag: "ferro-notify-rust/v0.1.0.pre.1",
  glob: "gems/notify-rust/*.gemspec"

gem "irb"
gem "rake", "~> 13.0"
gem "rake-compiler"

gem "minitest", "~> 6.0"
gem "minitest-mock"

gem "rubocop", "~> 1.21"
gem "rubycritic", "~> 4.11"
gem "ostruct", "~> 0.6.3"
gem "inch", "~> 0.4"
gem "flog", "4.8.0"
gem "steep"

# examples/
gem "rack", ">= 3.0"
gem "rdoc", "~> 7.0"
gem "roda", ">= 3.0"
gem "tilt", ">= 2.0"
