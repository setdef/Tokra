# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Fixture for rack_assets_test.rb: a binary asset served by a Rack app over
# tokra://, once as an array body and once as a file body (to_path), the way
# Rack::Files serves one. Run by hand to watch it:
#
#   bundle exec ruby test/integration/fixtures/rack_assets/app.rb --wait

require_relative "../../support/fixture_app"

PNG = File.expand_path("../../../fixtures/2x1.png", __dir__)

# A body that only offers its path, like Rack::Files::Iterator.
FileBody = Data.define(:to_path) do
  def each
    yield File.binread(to_path)
  end
end

options = FixtureApp.options(ARGV)
routes = {
  "/array.png" => -> (_env) { [200, { "content-type" => "image/png" }, [File.binread(PNG)]] },
  "/file.png" => -> (_env) { [200, { "content-type" => "image/png" }, FileBody.new(PNG)] },
}
FixtureApp.builder(FixtureApp::Site.new(__dir__, options, routes), "rack assets").run
