# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "yaml"

# Tests that the Ruby mise.toml pins on each system, the one bin/setup
# installs and the pre-push hook runs the gate on, is one CI runs on that
# system and one tokra.gemspec admits (Plan 069). Linux and macOS run Ruby
# 4.1 and Windows 4.0, so a pin that moves on one system and not in CI's
# matrix would leave the hook testing a Ruby CI never runs there.
class TestRubyPins < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  # mise's name for each system, and the runner ci.yml runs it on.
  RUNNERS = { "linux" => "ubuntu-latest", "macos" => "macos-latest", "windows" => "windows-latest" }.freeze

  def test_mise_pins_one_ruby_on_each_system
    assert_equal RUNNERS.keys.sort, pins.keys.sort
  end

  def test_ci_runs_each_systems_pin_on_that_system
    pins.each do |system, version|
      series = ci_rubies(RUNNERS.fetch(system))

      assert(series.any? { |name| version.start_with?("#{name}.") }, "mise.toml pins #{version} on #{system}, but ci.yml runs #{series.inspect} there")
    end
  end

  def test_the_gemspec_admits_each_pin
    requirement = Gem::Specification.load(File.join(ROOT, "tokra.gemspec")).required_ruby_version

    pins.each do |system, version|
      assert requirement.satisfied_by?(Gem::Version.new(version.tr("-", "."))), "tokra.gemspec requires Ruby #{requirement}, but mise.toml pins #{version} on #{system}"
    end
  end

  # Each system's Ruby, from mise.toml's list of a version for each set of
  # systems.
  private def pins
    list = File.read(File.join(ROOT, "mise.toml"))[/^ruby = \[\n(.*?)^\]$/m, 1] || flunk("mise.toml pins no Ruby for each system")
    list.scan(/\{ version = "([^"]+)", os = \[([^\]]*)\] \}/).each_with_object({}) do |(version, systems), pins|
      systems.scan(/"(\w+)"/).flatten.each do |system|
        assert_nil pins[system], "mise.toml pins two Rubies on #{system}"
        pins[system] = version
      end
    end
  end

  # The Ruby series ci.yml's gate job runs on +runner+.
  private def ci_rubies(runner)
    matrix = YAML.safe_load_file(File.join(ROOT, ".github/workflows/ci.yml")).dig("jobs", "gate", "strategy", "matrix")

    assert_includes matrix.fetch("os"), runner
    excluded = matrix.fetch("exclude", []).select { |entry| entry["os"] == runner }.map { |entry| entry["ruby"] }
    matrix.fetch("ruby") - excluded
  end
end
