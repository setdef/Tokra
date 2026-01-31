# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

class TestPathResolver < Minitest::Test
  # Stub native module for isolated testing
  StubNative = Data.define(:home_dir, :data_local_dir)

  def setup
    @config = { identifier: "com.example.testapp" }
    @stub_native = StubNative.new(
      home_dir: "/Users/test",
      data_local_dir: "/home/test/.local/share"
    )
  end

  def test_app_log_dir_returns_pathname
    resolver = Tokra::Path::Resolver.new(@config, native: @stub_native)

    result = resolver.app_log_dir

    assert_kind_of Pathname, result
  end

  def test_app_log_dir_includes_identifier
    resolver = Tokra::Path::Resolver.new(@config, native: @stub_native)

    result = resolver.app_log_dir

    assert_includes result.to_s, "com.example.testapp"
  end

  def test_app_log_dir_macos_uses_library_logs
    resolver = Tokra::Path::Resolver.new(
      @config,
      platform: "arm64-darwin24",
      native: @stub_native
    )

    result = resolver.app_log_dir

    assert_equal "/Users/test/Library/Logs/com.example.testapp", result.to_s
  end

  def test_app_log_dir_linux_uses_data_local
    resolver = Tokra::Path::Resolver.new(
      @config,
      platform: "x86_64-linux",
      native: @stub_native
    )

    result = resolver.app_log_dir

    assert_equal "/home/test/.local/share/logs/com.example.testapp", result.to_s
  end

  def test_app_handle_path_returns_resolver
    config = { identifier: "com.example.testapp" }
    handle = Tokra::AppHandle.new(config)

    result = handle.path

    assert_kind_of Tokra::Path::Resolver, result
  end
end

# Integration tests using real Rust bindings.
# These verify the actual dirs crate works via the compiled extension.
# Run with: bundle exec rake compile && bundle exec ruby -Ilib:test test/test_path_resolver.rb
class TestPathResolverIntegration < Minitest::Test
  def test_real_native_home_dir_returns_string_on_macos
    skip "macOS-only integration test" unless RUBY_PLATFORM.include?("darwin")

    result = Tokra::Native.home_dir

    assert_kind_of String, result
    assert_includes result, "/Users/"
  end

  def test_real_native_home_dir_returns_string_on_linux
    skip "Linux-only integration test" unless RUBY_PLATFORM.include?("linux")

    result = Tokra::Native.home_dir

    assert_kind_of String, result
    assert_includes result, "/home/"
  end

  def test_real_native_data_local_dir_returns_string_on_macos
    skip "macOS-only integration test" unless RUBY_PLATFORM.include?("darwin")

    result = Tokra::Native.data_local_dir

    assert_kind_of String, result
    assert_includes result, "Library/Application Support"
  end

  def test_real_native_data_local_dir_returns_string_on_linux
    skip "Linux-only integration test" unless RUBY_PLATFORM.include?("linux")

    result = Tokra::Native.data_local_dir

    assert_kind_of String, result
    assert_includes result, ".local/share"
  end

  def test_real_native_data_local_dir_returns_string_on_windows
    skip "Windows-only integration test" unless RUBY_PLATFORM.include?("mingw")

    result = Tokra::Native.data_local_dir

    assert_kind_of String, result
    assert_includes result, "AppData"
  end

  def test_real_path_resolver_app_log_dir_on_macos
    skip "macOS-only integration test" unless RUBY_PLATFORM.include?("darwin")

    config = { identifier: "app.tokra.test" }
    resolver = Tokra::Path::Resolver.new(config)

    result = resolver.app_log_dir

    assert_kind_of Pathname, result
    assert_includes result.to_s, "Library/Logs"
    assert_includes result.to_s, "app.tokra.test"
  end

  def test_real_path_resolver_app_log_dir_on_linux
    skip "Linux-only integration test" unless RUBY_PLATFORM.include?("linux")

    config = { identifier: "app.tokra.test" }
    resolver = Tokra::Path::Resolver.new(config)

    result = resolver.app_log_dir

    assert_kind_of Pathname, result
    assert_includes result.to_s, ".local/share/logs"
    assert_includes result.to_s, "app.tokra.test"
  end
end
