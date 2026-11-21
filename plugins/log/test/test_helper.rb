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

  # The process's logger in the tests. A process attaches one logger, once
  # (Log.attach_logger), so the tests attach this one when they load, and
  # each test that needs the global logger points it at a Logger of its
  # own with #forwarding_to. An app the tests register Builder#build's
  # plugin on calls Builder#skip_logger, as Tauri's skip_logger tells a
  # test that registers the plugin more than once to (lib.rs:519-533).
  class Forwarder < Log::Logger
    # The Logger each record goes to, or +nil+ to drop it.
    attr_accessor :to

    def initialize
      super(level: :trace, filters: [], format: nil, app_name: "forwarder", targets: [])
    end

    # Hands +record+ to #to.
    def log(record)
      @to&.log(record)
      nil
    end
  end

  FORWARDER = Forwarder.new
  Log.attach_logger(:trace, FORWARDER)

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

  # The Logger +builder+ describes, made for +handle+ with Builder#split,
  # which attaches nothing, so each test has a logger of its own while
  # the process keeps one global logger.
  private def logger_of(builder, handle = app_handle)
    _plugin, _max_level, logger = builder.split(handle)
    logger
  end

  # The Logger +builder+ describes, with standard output its only target.
  private def stdout_logger(builder = Log::Builder.new, handle = app_handle)
    logger_of(builder.clear_targets.target(stdout_target), handle)
  end

  # What the Logger made from +builder+ writes to standard output while
  # the block logs through it.
  private def logged(builder = Log::Builder.new, handle = app_handle)
    logger = stdout_logger(builder, handle)
    out, = capture_io { yield logger }
    out
  end

  # Points the process's logger at +logger+ while the block runs.
  private def forwarding_to(logger)
    FORWARDER.to = logger
    yield
  ensure
    FORWARDER.to = nil
  end

  # The timestamps +strategy+ gives before and after the block runs, so a
  # line stamped while it ran carries one of them.
  private def stamps_around(strategy)
    before = strategy.get_now.format(TIMESTAMP)
    yield
    [before, strategy.get_now.format(TIMESTAMP)]
  end

  # A real app handle, built as an app builds one, on StubNative, for an
  # app whose package is named +product_name+.
  private def app_handle(product_name: "demo")
    TestApp.build_test_app(config: { "productName" => product_name }).handle
  end
end
