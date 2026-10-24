# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for image_plugin_test.rb: the core image plugin through the real
# Image class from @tauri-apps/api. Run by hand to watch it:
#
#   bundle exec ruby test/integration/fixtures/image_plugin/app.rb --wait

require_relative "../../support/fixture_app"

options = FixtureApp.options(ARGV)
FixtureApp.builder(FixtureApp::Site.new(__dir__, options), "image plugin")
  .with_global_tauri
  .run
