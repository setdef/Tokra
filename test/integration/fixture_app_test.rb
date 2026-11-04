# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "open3"
require "json"

# Every window a real-window fixture builds keeps its page running when the
# session is off the console (FixtureApp::Unthrottled). Runs in a child
# process, because the fixtures' seam is a global prepend that would reach
# every other test.
class FixtureAppTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  SCRIPT = <<~RUBY
    require "json"
    require_relative "test/integration/support/fixture_app"
    require_relative "test/support/stub_native"
    windows = [Tokra::Utils::Config::WindowConfig.new]
    config = Tokra::Config.new(identifier: "com.tokra.unthrottled", app: Tokra::Utils::Config::AppConfig.new(windows:))
    data = Tokra::Codegen::ContextData.new(dev: true, config:, config_parent: Dir.pwd)
    app = FixtureApp.builder(->(_env) { [200, {}, []] }).build(Tokra::Codegen.context_codegen(data), native: StubNative)
    own = Tokra::WebviewWindowBuilder.new(app.handle, "own", Tokra::WebviewUrl::App.new("index.html"))
      .background_throttling(Tokra::BackgroundThrottlingPolicy::Suspend)
    plain = Tokra::WebviewWindowBuilder.new(app.handle, "plain", Tokra::WebviewUrl::App.new("index.html"))
    app.run do |handle, event|
      next unless event.is_a?(Tokra::RunEvent::Ready)

      own.build
      plain.build
      puts "THROTTLING " + JSON.generate(StubNative.webviews.map { |webview| webview.attributes[:background_throttling] })
      handle.exit(0)
    end
  RUBY

  def test_main_and_other_windows_are_built_with_throttling_disabled_unless_the_fixture_chose
    output, status = Open3.capture2e(RbConfig.ruby, "-I", File.join(ROOT, "lib"), "-I", File.join(ROOT, "test"), "-e", SCRIPT, chdir: ROOT)

    assert_predicate status, :success?, output
    assert_equal ["Disabled", "Suspend", "Disabled"], JSON.parse(output[/^THROTTLING (.*)$/, 1])
  end

  # A line a fixture prints from one thread arrives whole even while
  # another thread prints, because each puts is one write
  # (FixtureApp::WholeLines), where Ruby's own puts writes a line and its
  # newline separately.
  LINES = <<~RUBY
    require "json"
    require_relative "test/integration/support/fixture_app"
    writes = []
    out = Object.new
    out.define_singleton_method(:write) { |*strings| writes << strings; strings.sum(&:bytesize) }
    out.extend(FixtureApp::WholeLines)
    out.puts("EVENT exit")
    out.puts("a\\n", ["b", nil])
    out.puts
    $stderr.puts "WRITES " + JSON.generate(writes)
    $stderr.puts "STDOUT " + JSON.generate($stdout.singleton_class.include?(FixtureApp::WholeLines))
  RUBY

  def test_each_line_a_fixture_prints_is_one_write_to_its_stdout
    output, status = Open3.capture2e(RbConfig.ruby, "-I", File.join(ROOT, "lib"), "-e", LINES, chdir: ROOT)

    assert_predicate status, :success?, output
    assert_equal [["EVENT exit\n"], ["a\nb\n\n"], ["\n"]], JSON.parse(output[/^WRITES (.*)$/, 1])
    assert JSON.parse(output[/^STDOUT (.*)$/, 1]), output
  end
end
