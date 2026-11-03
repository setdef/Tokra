# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../../support/config_fixtures"

# The config schema, held up against what serde_json::from_value made of
# the same JSON in Tauri's own types (test/fixtures/config/from_value,
# from tauri-utils at vendor/tauri 9f0306fbc). Every case whose type
# Tokra reads is read by Tokra's deserializer and compared: the error's
# words, or the value written back as serde_json writes Tauri's.
class TestUtilsConfig < Minitest::Test
  C = Tokra::Utils::Config
  Mismatch = Tokra::Ipc::CommandItem::Mismatch
  REPOSITORY = File.expand_path("../../..", __dir__)

  # Each tauri-utils type the generator reads, as Tokra reads it.
  READERS = {
    "AppConfig" => -> (value) { C::AppConfig.deserialize(value) },
    "AssetProtocolConfig" => -> (value) { C::AssetProtocolConfig.deserialize(value) },
    "BackgroundThrottlingPolicy" => -> (value) { Tokra::BackgroundThrottlingPolicy.deserialize(value) },
    "BeforeDevCommand" => -> (value) { C::BeforeDevCommand.deserialize(value) },
    "BuildConfig" => -> (value) { C::BuildConfig.deserialize(value) },
    "BundleConfig" => -> (value) { C::BundleConfig.deserialize(value) },
    "CapabilityEntry" => -> (value) { C::CapabilityEntry.deserialize(value) },
    # The generator ran from the repository's root, where no file is named
    # like a version.
    "Config" => -> (value) { C::Config.deserialize(value, REPOSITORY) },
    "Csp" => -> (value) { C::Csp.deserialize(value) },
    "DisabledCspModificationKind" => -> (value) { C::DisabledCspModificationKind.deserialize(value) },
    "FrontendDist" => -> (value) { C::FrontendDist.deserialize(value) },
    "FsScope" => -> (value) { C::FsScope.deserialize(value) },
    "HeaderConfig" => -> (value) { C::HeaderConfig.deserialize(value) },
    "HookCommand" => -> (value) { C::HookCommand.deserialize(value) },
    "LogicalPosition" => -> (value) { C::LogicalPosition.deserialize(value) },
    "PatternKind" => -> (value) { C::PatternKind.deserialize(value) },
    "PreventOverflowConfig" => -> (value) { C::PreventOverflowConfig.deserialize(value) },
    "PreventOverflowMargin" => -> (value) { C::PreventOverflowMargin.deserialize(value) },
    "RunnerConfig" => -> (value) { C::RunnerConfig.deserialize(value) },
    "ScrollBarStyle" => -> (value) { C::ScrollBarStyle.deserialize(value) },
    "SecurityConfig" => -> (value) { C::SecurityConfig.deserialize(value) },
    "TrayIconConfig" => -> (value) { C::TrayIconConfig.deserialize(value) },
    "WebviewUrl" => -> (value) { Tokra::WebviewUrl.deserialize(value) },
    "WindowConfig" => -> (value) { C::WindowConfig.deserialize(value) },
  }.freeze

  def test_every_type_the_generator_reads_is_read
    types = ConfigFixtures.from_value.values.map { |answer| answer.fetch("type") }.uniq
    assert_empty types - READERS.keys
  end

  # One test per case, so each failure names its case.
  ConfigFixtures.from_value.each_key do |name|
    define_method(:"test_from_value_#{name}") { assert_answer(name) }
  end

  # --- what the cases cannot show ---

  # serde's unknown-field error lists FIELDS in declaration order, and
  # Data.define's members are the same names in the same order.
  def test_each_struct_lists_its_fields_in_its_members_order
    [
      C::Config,
      C::AppConfig,
      C::WindowConfig,
      C::SecurityConfig,
      C::AssetProtocolConfig,
      C::HeaderConfig,
      C::TrayIconConfig,
      C::BuildConfig,
      C::BundleConfig,
      C::LogicalPosition,
      C::PreventOverflowMargin,
].each do |struct|
      assert_equal struct.members, struct::FIELDS.map(&:member), struct.name
    end
  end

  # A struct built in Ruby takes Tauri's Default, and a required field
  # stays required.
  def test_new_takes_tauris_defaults
    window = C::WindowConfig.new(label: "settings")
    assert_equal ["settings", true, "Tokra App"], [window.label, window.create, window.title]
    assert_equal [[Float, 800.0], [Float, 600.0]], [window.width, window.height].map { |value| [value.class, value] }
    assert_equal Tokra::WebviewUrl::App.new(path: "index.html"), window.url
    assert_equal C::PatternKind::Brownfield.new, C::Config.new(identifier: "a").app.security.pattern
    assert_raises(ArgumentError) { C::Config.new }
    assert_raises(ArgumentError) { C::TrayIconConfig.new }
  end

  # A default is shared by every struct that takes it, so it is frozen.
  def test_defaults_are_frozen
    assert_predicate C::AppConfig.new.windows, :frozen?
    assert Ractor.shareable?(C::WindowConfig.new)
  end

  # *Deviation* (plan 054, Security inventory): Tauri reads an inline
  # capability as its Capability struct and refuses one that is not; Tokra
  # keeps it as JSON until the capabilities plan.
  def test_an_inline_capability_is_kept_as_its_json
    entry = C::CapabilityEntry.deserialize({ "identifier" => "inline", "bogus" => [1] })
    assert_equal C::CapabilityEntry::Inlined.new(capability: { "identifier" => "inline", "bogus" => [1] }), entry
    security = C::SecurityConfig.deserialize({ "capabilities" => ["main", { "identifier" => "x" }] })
    assert_equal [C::CapabilityEntry::Reference, C::CapabilityEntry::Inlined], security.capabilities.map(&:class)
  end

  def test_the_whole_config_is_deep_frozen_and_shareable
    config = C::Config.deserialize({
"identifier" => "a",
"plugins" => { "log" => { "level" => ["info"] } },
"app" => { "windows" => [{}] },
}, REPOSITORY)
    assert Ractor.shareable?(config)
    assert_predicate config.plugins.fetch("log").fetch("level"), :frozen?
    assert_predicate config.app.windows.first.url.path, :frozen?
  end

  # The variant each untagged URL case reads as. The dumper writes a URL
  # and a path the same way, as serde does, so the class is checked apart.
  VARIANTS = {
    "webview_url_external" => Tokra::WebviewUrl::External,
    "webview_url_app" => Tokra::WebviewUrl::App,
    "webview_url_invalid_port" => Tokra::WebviewUrl::App,
    "webview_url_missing_slashes" => Tokra::WebviewUrl::External,
    "webview_url_idn_host" => Tokra::WebviewUrl::External,
    "webview_url_dot_segments" => Tokra::WebviewUrl::External,
    "webview_url_ipv4_shorthand" => Tokra::WebviewUrl::External,
    "webview_url_bad_percent_escape" => Tokra::WebviewUrl::External,
    "webview_url_windows_path" => Tokra::WebviewUrl::CustomProtocol,
    "webview_url_opaque_with_space" => Tokra::WebviewUrl::CustomProtocol,
    "frontend_dist_directory" => C::FrontendDist::Directory,
    "frontend_dist_windows_path" => C::FrontendDist::Url,
    "frontend_dist_missing_slashes" => C::FrontendDist::Url,
    "frontend_dist_invalid_port" => C::FrontendDist::Directory,
    "frontend_dist_idn_host" => C::FrontendDist::Url,
  }.freeze

  def test_each_untagged_url_reads_as_its_variant
    VARIANTS.each do |name, variant|
      answer = ConfigFixtures.from_value.fetch(name)
      assert_instance_of variant, READERS.fetch(answer.fetch("type")).call(answer.fetch("value")), name
    end
  end

  # A WebviewUrl's URL is url's own, from a config or from code (plan 055).
  def test_a_webview_url_names_the_url_type_it_takes
    error = assert_raises(TypeError) { Tokra::WebviewUrl::External.new(url: "https://tauri.app") }
    assert_equal "wrong argument type String (expected Ferro::Url::Url)", error.message
  end

  # FrontendDist tries a URL before a path (config.rs:2940-2947), for any
  # scheme.
  def test_frontend_dist_reads_a_url_of_any_scheme_before_a_path
    assert_instance_of C::FrontendDist::Url, C::FrontendDist.deserialize("https://example.com/app")
    assert_instance_of C::FrontendDist::Url, C::FrontendDist.deserialize("doom://index.html")
    assert_instance_of C::FrontendDist::Directory, C::FrontendDist.deserialize("../dist")
  end

  # serde's f64 visitor answers a float for an integer too; == alone would
  # take 800 for 800.0.
  def test_f64_fields_hold_floats
    window = C::WindowConfig.new
    [window.width, window.height].each { |value| assert_instance_of Float, value }
    read = C::WindowConfig.deserialize(ConfigFixtures.from_value.fetch("window_default_width_is_a_float").fetch("value"))
    assert_equal [[Float, 1024.0], [Float, 600.0]], [read.width, read.height].map { |value| [value.class, value] }
    assert_instance_of Float, C::LogicalPosition.deserialize({ "x" => 1, "y" => 2 }).x
  end

  # Tauri's own deserializer splits a URL by its scheme (config.rs:88-109).
  def test_a_webview_url_is_external_custom_or_an_app_path
    assert_instance_of Tokra::WebviewUrl::External, Tokra::WebviewUrl.deserialize("http://localhost:1420")
    assert_instance_of Tokra::WebviewUrl::External, Tokra::WebviewUrl.deserialize("https://tauri.app")
    assert_instance_of Tokra::WebviewUrl::CustomProtocol, Tokra::WebviewUrl.deserialize("doom://index.html")
    assert_equal Tokra::WebviewUrl::App.new(path: "users/john"), Tokra::WebviewUrl.deserialize("users/john")
  end

  # A config URL is url's own, through ferro-url, as Tauri's is a
  # url::Url (plan 054, decision 25).
  def test_a_config_url_is_the_url_crates
    assert_instance_of Ferro::Url::Url, C::BuildConfig.deserialize({ "devUrl" => "HTTP://LocalHost:1420" }).dev_url
    assert_instance_of Ferro::Url::Url, C::WindowConfig.deserialize({ "proxyUrl" => "http://p:1" }).proxy_url
    assert_instance_of Ferro::Url::Url, Tokra::WebviewUrl.deserialize("doom://index.html").url
    assert Ractor.shareable?(C::Config.deserialize({ "identifier" => "a", "build" => { "devUrl" => "http://a" } }, REPOSITORY))
  end

  private def assert_answer(name)
    answer = ConfigFixtures.from_value.fetch(name)
    read = READERS.fetch(answer.fetch("type"))
    if answer.key?("error")
      error = assert_raises(Mismatch, name) { read.call(answer.fetch("value")) }
      assert_equal answer.fetch("error"), error.message, name
    else
      result = read.call(answer.fetch("value"))
      actual = answer.key?("probes") ? ConfigFixtures.probed(result, answer.fetch("probes")) : ConfigFixtures.dump(result)
      assert_equal renamed(answer.fetch("ok")), actual, name
    end
  end

  # Tauri's default window title, renamed as ADR 014 §4 renames it.
  private def renamed(value)
    case value
    when "Tauri App" then "Tokra App"
    when Array then value.map { |item| renamed(item) }
    when Hash then value.transform_values { |item| renamed(item) }
    else value
    end
  end
end
