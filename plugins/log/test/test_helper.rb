# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/autorun"
require "minitest/mock"
require "logger"
require "stringio"
require "tmpdir"
require "tokra-log"

# Tokra's StubNative double lives with the core tests; the plugin's tests
# run on a real AppHandle built on it instead of a hand-rolled stand-in.
$LOAD_PATH.unshift File.expand_path("../../../test", __dir__)
require "support/test_app"

# Helpers the log plugin's tests share.
module LogTest
  Log = Tokra::Plugins::Log

  # A date and time as Tauri's default format writes them (lib.rs:407).
  STAMP = /\[\d{4}-\d{2}-\d{2}\]\[\d{2}:\d{2}:\d{2}\]/

  # Tauri's timestamp format description, parsed here independently of
  # the plugin's own constant.
  TIMESTAMP = Ractor.make_shareable(
    Ferro::Time::FormatDescription.parse_borrowed(1, "[[[year]-[month]-[day]][[[hour]:[minute]:[second]]")
  )

  # A Stdout target, the one the tests read through capture_io.
  private def stdout_target
    Log::Target.new(Log::TargetKind::Stdout.new)
  end

  # A plugin built from +builder+ with standard output as its only target.
  private def stdout_plugin(builder = Log::Builder.new)
    builder.clear_targets.target(stdout_target).build
  end

  # What the plugin built from +builder+ writes to standard output while
  # the block logs through it.
  private def logged(builder = Log::Builder.new)
    plugin = stdout_plugin(builder)
    out, = capture_io { yield plugin }
    out
  end

  # The timestamps +strategy+ gives before and after the block runs, so a
  # line stamped while it ran carries one of them.
  private def stamps_around(strategy)
    before = strategy.get_now.format(TIMESTAMP)
    yield
    [before, strategy.get_now.format(TIMESTAMP)]
  end

  # A real app handle, built as an app builds one, on StubNative.
  private def app_handle
    TestApp.build_test_app.handle
  end
end
