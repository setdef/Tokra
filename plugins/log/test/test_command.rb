# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "json"

# The log command @tauri-apps/plugin-log's functions invoke as
# plugin:log|log (commands.rs:11-41; guest-js/index.ts:113-130), through
# the real plugin on a real app handle.
class TestCommand < Minitest::Test
  include LogTest

  # Every record the plugin logs, as a Logger target sees it, and its
  # Record through the format.
  RECORD = Ractor.shareable_proc do |_message, record|
    JSON.generate(record.to_h)
  end

  def setup
    @handle = app_handle
    @out = StringIO.new
    logger = ::Logger.new(@out, formatter: -> (_severity, _time, _progname, message) { "#{message}\n" })
    @plugin, _, FORWARDER.to = Log::Builder.new.format(RECORD).level(:debug).clear_targets
      .target(Log::Target.new(Log::TargetKind::Dispatch.new(logger)))
      .split(@handle)
    @handle.plugin(@plugin)
  end

  def teardown
    FORWARDER.to = nil
  end

  # Runs +command+ with +payload+ and returns whether the plugin claimed
  # it and its first answer, <tt>[success, value]</tt>.
  private def invoke(payload, command: "log")
    answers = Thread::Queue.new
    window = Tokra::Window.new(label: "main", native: Object.new, app_handle: @handle)
    webview = Tokra::Webview.new(label: "main", native: Object.new, window:, app_handle: @handle)
    invoke = Tokra::Ipc::Invoke.new(command:, payload:, webview:,
      responder: -> (success, json) { answers << [success, JSON.parse(json)] })
    handled = @plugin.extend_api(invoke)
    [handled, answers.pop(timeout: 1)]
  end

  private def logged
    @out.string.lines.map { |line| JSON.parse(line) }
  end

  # guest-js sends level, message, location, file, line, and keyValues
  # (index.ts:113-130); the command logs them as a record targeted at
  # webview:<location> and resolves null.
  def test_the_page_logs_a_record_targeted_at_the_webview
    handled, answer = invoke({
      "level" => 3,
      "message" => "clicked",
      "location" => "onClick@http://localhost/main.js:12:3",
      "file" => "main.js",
      "line" => 12,
      "keyValues" => { "button" => "save" },
    })

    assert handled
    assert_equal [true, nil], answer
    assert_equal [
{
      "args" => "clicked",
      "level" => "info",
      "target" => "webview:onClick@http://localhost/main.js:12:3",
      "file" => "main.js",
      "line" => 12,
      "key_values" => { "button" => "save" },
    },
], logged
  end

  # Without a location the target is WEBVIEW_TARGET alone (commands.rs:22-26).
  def test_without_a_location_the_target_is_webview
    invoke({ "level" => 5, "message" => "boom" })

    assert_equal [["webview", "error", nil, nil, {}]],
      logged.map { |record| record.values_at("target", "level", "file", "line", "key_values") }
  end

  # LogLevel's numbers (lib.rs:70-96).
  def test_each_level_number_logs_at_its_level
    [2, 3, 4, 5].each { |level| invoke({ "level" => level, "message" => "m" }) }

    assert_equal %w[debug info warn error], logged.map { |record| record["level"] }
  end

  # The builder's level applies to the page's records as to Ruby's.
  def test_the_level_applies_to_the_pages_records
    _, answer = invoke({ "level" => 1, "message" => "too low" })

    assert_equal [true, nil], answer
    assert_empty logged
  end

  # The page's records reach the Webview target, formatted, as Ruby's do.
  def test_the_pages_records_reach_the_webview_target
    payloads = []
    @handle.listen("log://log") { |event| payloads << JSON.parse(event.payload) }
    @plugin, _, FORWARDER.to = Log::Builder.new.clear_targets.target(Log::Target.new(Log::TargetKind::Webview.new))
      .split(@handle)

    invoke({ "level" => 4, "message" => "careful", "location" => "f@a.js:1:1" })

    assert_equal 1, payloads.size
    assert_match(/\A#{STAMP}\[webview:f@a.js:1:1\]\[WARN\] careful\z/o, payloads[0]["message"])
    assert_equal 4, payloads[0]["level"]
  end

  # The command logs to the process's logger, as Tauri's logs to
  # log::logger() (commands.rs:40), so a plugin built with skip_logger
  # still reaches the logger the app attached.
  def test_the_command_logs_to_the_process_logger
    @plugin = Log::Builder.new.skip_logger.build

    handled, answer = invoke({ "level" => 3, "message" => "via the global" })

    assert handled
    assert_equal [true, nil], answer
    assert_equal ["via the global"], logged.map { |record| record["args"] }
  end

  # With nothing behind the process's logger the record goes nowhere and
  # the command still resolves, as Tauri's no-op logger drops it.
  def test_with_no_logger_the_command_still_resolves
    FORWARDER.to = nil

    assert_equal [true, [true, nil]], invoke({ "level" => 3, "message" => "dropped" })
    assert_empty logged
  end

  def test_other_commands_are_left_for_the_router
    handled, answer = invoke({}, command: "attach_console")

    refute handled
    assert_nil answer
  end

  # Each argument reads as its Rust type and rejects in serde's words,
  # wrapped in Tauri's invalid args message.
  def test_a_bad_argument_rejects_with_tauris_message
    {
      { "message" => "m" } => "invalid args `level` for command `log`: command log missing required key level",
      { "level" => 7, "message" => "m" } =>
        "invalid args `level` for command `log`: invalid value: 7, expected one of: 1, 2, 3, 4, 5",
      { "level" => 0, "message" => "m" } =>
        "invalid args `level` for command `log`: invalid value: 0, expected one of: 1, 2, 3, 4, 5",
      { "level" => "info", "message" => "m" } =>
        "invalid args `level` for command `log`: invalid type: string \"info\", expected u16",
      { "level" => 70_000, "message" => "m" } =>
        "invalid args `level` for command `log`: invalid value: integer `70000`, expected u16",
      { "level" => 3 } => "invalid args `message` for command `log`: command log missing required key message",
      { "level" => 3, "message" => 1 } =>
        "invalid args `message` for command `log`: invalid type: integer `1`, expected a string",
      { "level" => 3, "message" => "m", "location" => 1 } =>
        "invalid args `location` for command `log`: invalid type: integer `1`, expected a borrowed string",
      { "level" => 3, "message" => "m", "file" => true } =>
        "invalid args `file` for command `log`: invalid type: boolean `true`, expected a borrowed string",
      { "level" => 3, "message" => "m", "line" => -1 } =>
        "invalid args `line` for command `log`: invalid value: integer `-1`, expected u32",
      { "level" => 3, "message" => "m", "keyValues" => [] } =>
        "invalid args `keyValues` for command `log`: invalid type: sequence, expected a map",
      { "level" => 3, "message" => "m", "keyValues" => { "a" => 1 } } =>
        "invalid args `keyValues` for command `log`: invalid type: integer `1`, expected a string",
    }.each do |payload, message|
      handled, answer = invoke(payload)

      assert handled
      assert_equal [false, message], answer, payload.inspect
    end
    assert_empty logged
  end

  # Arguments read in the order the command declares them, so the first
  # bad one is the one reported.
  def test_the_first_bad_argument_is_reported
    _, answer = invoke({ "level" => 9, "message" => 1 })

    assert_equal [false, "invalid args `level` for command `log`: invalid value: 9, expected one of: 1, 2, 3, 4, 5"],
      answer

    _, answer = invoke({
"level" => 3,
"message" => "m",
"location" => 1,
"file" => 1,
"line" => "x",
"keyValues" => 1,
})

    assert_equal [false, "invalid args `location` for command `log`: invalid type: integer `1`, expected a borrowed string"],
      answer
  end

  # Optional arguments may be null, as Option reads it.
  def test_null_optional_arguments_are_none
    _, answer = invoke({
"level" => 3,
"message" => "m",
"location" => nil,
"file" => nil,
"line" => nil,
"keyValues" => nil,
})

    assert_equal [true, nil], answer
    assert_equal "webview", logged[0]["target"]
  end
end
