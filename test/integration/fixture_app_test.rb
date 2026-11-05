# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require "open3"
require "json"
require_relative "../support/watched_child"

# Every window a real-window fixture builds keeps its page running when the
# session is off the console (FixtureApp.webview_window): the config's
# windows through backgroundThrottling in each fixture's tokra.conf.json,
# and the rest through FixtureApp.webview_window. The build runs in a child
# process, because requiring the fixtures' support changes $stdout.
class FixtureAppTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  # Every fixture's config, the plugins' included.
  CONFIGS = Dir[File.join(ROOT, "test/integration/fixtures/*/tokra.conf.json"),
    File.join(ROOT, "plugins/*/test/integration/fixtures/*/tokra.conf.json")].sort.freeze

  # Every fixture's Ruby, the plugins' included.
  FIXTURE_SOURCES = Dir[File.join(ROOT, "test/integration/fixtures/**/*.rb"),
    File.join(ROOT, "plugins/*/test/integration/fixtures/**/*.rb")].sort.freeze

  def test_every_window_a_fixtures_config_lists_has_throttling_disabled
    assert_operator CONFIGS.size, :>=, 26, "the fixture configs were not found"
    CONFIGS.each do |path|
      windows = Tokra.generate_context(path).config.app.windows
      # A fixture that lists no window says so with "windows": [] (the
      # config tray's opens none, so it runs on Windows without WebView2);
      # any other empty list means the config lost its windows.
      refute_empty windows, path unless JSON.parse(File.read(path)).dig("app", "windows") == []
      windows.each do |window|
        assert_same Tokra::BackgroundThrottlingPolicy::Disabled, window.background_throttling, "#{path}: #{window.label}"
      end
    end
  end

  # A fixture's own window starts from FixtureApp.webview_window, and
  # from_config takes only an entry of the fixture's tokra.conf.json, whose
  # throttling the test above checks: a WindowConfig built in code, or one
  # whose throttling is changed with Data#with, would bypass both.
  BYPASSES = {
    "WebviewWindowBuilder.new" => /WebviewWindowBuilder\.new\b/,
    "a WindowConfig built in code" => /WindowConfig\.(?:new|deserialize)\b/,
    "a changed backgroundThrottling" => /\bbackground_throttling:/,
  }.freeze

  def test_no_fixture_builds_a_window_but_through_fixture_app_or_its_config
    BYPASSES.each do |what, pattern|
      found = FIXTURE_SOURCES.select { |path| File.read(path).match?(pattern) }.map { |path| path.delete_prefix("#{ROOT}/") }

      assert_empty found, "#{what}: build through FixtureApp.webview_window or an entry of tokra.conf.json"
    end
  end

  def test_the_bypass_patterns_match_what_they_name
    assert_match BYPASSES.fetch("WebviewWindowBuilder.new"), 'Tokra::WebviewWindowBuilder.new(app, "x", url)'
    assert_match BYPASSES.fetch("a WindowConfig built in code"), 'Tokra::Utils::Config::WindowConfig.new(label: "x")'
    assert_match BYPASSES.fetch("a WindowConfig built in code"), "Tokra::Utils::Config::WindowConfig.deserialize(json)"
    assert_match BYPASSES.fetch("a changed backgroundThrottling"), "entry.with(label: \"x\", background_throttling: nil)"
    refute_match BYPASSES.fetch("a WindowConfig built in code"), "app.config.app.windows.first.with(label: \"x\")"
  end

  SCRIPT = <<~RUBY
    require "json"
    require_relative "test/integration/support/fixture_app"
    require_relative "test/support/stub_native"
    context = Tokra.generate_context(File.expand_path("test/integration/fixtures/event/tokra.conf.json"))
    app = FixtureApp.builder(->(_env) { [200, {}, []] }).build(context, native: StubNative)
    own = FixtureApp.webview_window(app.handle, "own", Tokra::WebviewUrl::App.new("index.html"))
    app.run do |handle, event|
      next unless event.is_a?(Tokra::RunEvent::Ready)

      own.build
      puts "THROTTLING " + JSON.generate(StubNative.webviews.map { |webview| [webview.label, webview.attributes[:background_throttling]] })
      handle.exit(0)
    end
  RUBY

  def test_a_fixtures_config_window_and_its_own_are_built_with_throttling_disabled
    output, status = Open3.capture2e(RbConfig.ruby, "-I", File.join(ROOT, "lib"), "-I", File.join(ROOT, "test"), "-e", SCRIPT, chdir: ROOT)

    assert_predicate status, :success?, output
    assert_equal [["main", "Disabled"], ["own", "Disabled"]], JSON.parse(output[/^THROTTLING (.*)$/, 1])
  end

  # On macOS, keep_in_sight goes on to turn off WebKit's occlusion
  # detection (FixtureApp.keep_page_awake). A StubNative window has no
  # handle, so the fixture says the call was unavailable, and why.
  def test_on_macos_keep_in_sight_reaches_the_occlusion_call
    skip "WebKit's occlusion detection is macOS's" unless RUBY_PLATFORM.include?("darwin")
    output, status = Open3.capture2e(RbConfig.ruby, "-I", File.join(ROOT, "lib"), "-I", File.join(ROOT, "test"), "-e", SCRIPT, chdir: ROOT)

    assert_predicate status, :success?, output
    assert_match(/^PROGRESS occlusion-detection unavailable, Tokra::RawWindowHandle::HandleError::Unavailable \d/, output)
  end

  # What a fixture's page sees and makes it print (Plan 060): the
  # patience RealApp gave it, in milliseconds, and a PROGRESS line for
  # each check it starts and ends. A fixture's first line says it loaded,
  # and its stdout is synced, so each line reaches RealApp as it is
  # printed.
  SITE = <<~'RUBY'
    require "json"
    require "stringio"
    ENV["TOKRA_FIXTURE_PATIENCE"] = "2.5"
    require_relative "test/integration/support/fixture_app"
    site = FixtureApp::Site.new("test/integration/fixtures/event", { exit_code: 0, wait: false })
    get = ->(path) { site.call("REQUEST_METHOD" => "GET", "PATH_INFO" => path) }
    post = ->(path, body) { site.call("REQUEST_METHOD" => "POST", "PATH_INFO" => path, "rack.input" => StringIO.new(body)) }
    puts "OPTIONS " + get.("/options.json")[2].join
    puts "STARTED #{post.("/progress", JSON.generate(stage: "start", name: "a check")).first}"
    puts "ENDED #{post.("/progress", JSON.generate(stage: "end", name: "a check")).first}"
    puts "OTHER #{post.("/progress", JSON.generate(stage: "beat", name: "a check")).first}"
    puts "SYNC #{$stdout.sync}"
  RUBY

  def test_a_fixture_serves_its_patience_and_prints_each_checks_progress
    output, status = Open3.capture2(RbConfig.ruby, "-I", File.join(ROOT, "lib"), "-e", SITE, chdir: ROOT)
    lines = output.lines(chomp: true).map { |line| line.sub(/\A(PROGRESS .*) \d+\.\d{3}\z/, '\1') }

    assert_predicate status, :success?, output
    assert_equal [
      "PROGRESS loaded",
      %(OPTIONS {"exitCode":0,"wait":false,"patience":2500}),
      "PROGRESS check-start a check",
      "STARTED 204",
      "PROGRESS check-end a check",
      "ENDED 204",
      "OTHER 400",
      "SYNC true",
    ], lines
  end

  # Run by hand, without RealApp's variable, a fixture takes the same
  # patience RealApp would have given it.
  def test_a_fixture_run_by_hand_takes_watched_childs_patience
    script = 'require_relative "test/integration/support/fixture_app"; puts "PATIENCE #{FixtureApp::PATIENCE}"'
    output, status = Open3.capture2({ "TOKRA_FIXTURE_PATIENCE" => nil }, RbConfig.ruby, "-I", File.join(ROOT, "lib"),
      "-e", script, chdir: ROOT)

    assert_predicate status, :success?, output
    assert_equal "PATIENCE #{Float(WatchedChild::PATIENCE)}", output.lines(chomp: true).last
  end

  # FixtureApp.take waits for what a test reads up to the fixture's
  # patience: when two of three items come and the third never does, the
  # wait ends with what came, in order; it takes no more than it was
  # asked for; and with no patience left it takes nothing.
  TAKE = <<~'RUBY'
    ENV["TOKRA_FIXTURE_PATIENCE"] = "0.5"
    require_relative "test/integration/support/fixture_app"
    queue = Thread::Queue.new
    queue << "first" << "second"
    puts "TAKEN #{FixtureApp.take(queue, 3).inspect}"
    puts "SOME #{FixtureApp.take(Thread::Queue.new.tap { |q| q << "a" << "b" << "c" }, 2).inspect}"
    puts "NONE #{FixtureApp.take(Thread::Queue.new, 2, patience: 0).inspect}"
  RUBY

  def test_take_waits_up_to_the_patience_for_the_items_a_test_reads
    output, status = Open3.capture2(RbConfig.ruby, "-I", File.join(ROOT, "lib"), "-e", TAKE, chdir: ROOT)

    assert_predicate status, :success?, output
    assert_equal ['TAKEN ["first", "second"]', 'SOME ["a", "b"]', "NONE []"], output.lines(chomp: true).grep(/\A(TAKEN|SOME|NONE) /)
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
