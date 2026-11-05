# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "stub_native"

# The one place the suite turns a Builder into an app.
#
# Every test that needs an app asks for it here, so a change to how an app is
# built changes this file and not seventy tests. An app is built from a
# Context, as Tauri's is (plan 054, 054a-3), so the helper builds one from a
# config Hash, the way Tokra.generate_context builds one from a file. The
# methods are available in every Minitest::Test, and on the test classes
# themselves for a constant built in a class body.
module TestApp
  extend self

  # The identifier and product name every test app has. A product name is
  # set so no test depends on the test runner's script name, which
  # PackageInfo would fall back to.
  IDENTIFIER = "com.tokra.test"
  PRODUCT_NAME = "Tokra Test"

  # The directory every test app's config is read as if it sat in, which
  # holds the icons/icon.png codegen decodes for the default window icon,
  # as a Tauri app's src-tauri/ does.
  CONFIG_PARENT = File.expand_path("../fixtures/test_app", __dir__)

  # The data directory a webview built with no #data_directory row is
  # given in a test app: on Linux and Windows the local data directory
  # StubNative answers, a temporary one, pushed with IDENTIFIER, as Rust's
  # PathBuf::push writes it, and none on macOS (manager/webview.rs:505-523).
  def default_data_directory
    return nil unless %w[linux windows].include?(Tokra::App.os_name)

    "#{StubNative.data_local_dir}#{File::ALT_SEPARATOR || '/'}#{IDENTIFIER}"
  end

  # Builds an app from +builder+ and a context #build_test_context builds,
  # standing +native+ in for the Rust binding.
  def build_test_app(builder = Tokra::Builder.default, native: StubNative, title: nil, width: nil, height: nil,
    config: {}
  )
    builder.build(build_test_context(title:, width:, height:, config:), native:)
  end

  # Runs an app built as #build_test_app builds it, passing +block+ to
  # Builder#run.
  def run_test_app(builder = Tokra::Builder.default, native: StubNative, title: nil, width: nil, height: nil,
    config: {}, &
  )
    builder.run(build_test_context(title:, width:, height:, config:), native:, &)
  end

  # A Context whose config has IDENTIFIER, PRODUCT_NAME, and one window,
  # +main+, with +title+, +width+, and +height+ when given and the
  # schema's defaults otherwise. +config+, a JSON Hash, is merged over that
  # as a platform file is (JSON Merge Patch), so
  # <tt>{ "app" => { "windows" => [] } }</tt> lists no window and
  # <tt>{ "app" => { "withGlobalTauri" => true } }</tt> keeps +main+.
  # The config sits in CONFIG_PARENT, so its default window icon is that
  # directory's icons/icon.png.
  def build_test_context(title: nil, width: nil, height: nil, config: {})
    window = { "label" => "main", "title" => title, "width" => width, "height" => height }.compact
    raw = { "identifier" => IDENTIFIER, "productName" => PRODUCT_NAME, "app" => { "windows" => [window] } }
    raw = Tokra::Utils::Config::Parse.merge(raw, config)
    parent = CONFIG_PARENT
    config = Tokra::Utils::Config::Config.deserialize(raw, parent)
    Tokra::Codegen.context_codegen(Tokra::Codegen::ContextData.new(dev: true, config:, config_parent: parent))
  end

  # An AppManager built from +context+, as App.new builds one, for a test
  # that drives a manager or a handle without an app.
  def build_test_manager(context = build_test_context, webviews: {}, windows: {})
    Tokra::AppManager.new(config: context.config, package_info: context.package_info, pattern: context.pattern,
      dev: context.dev, default_window_icon: context.default_window_icon, app_icon: context.app_icon, webviews:,
      windows:)
  end
end

Minitest::Test.include(TestApp)
Minitest::Test.extend(TestApp)
