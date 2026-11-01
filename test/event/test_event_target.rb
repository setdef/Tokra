# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# EventTarget's variants, constructors, and serde form (event/mod.rs:22-110,
# serde's internally tagged enums).
class TestEventTarget < Minitest::Test
  T = Tokra::EventTarget

  def test_constructors_make_each_variant
    assert_equal T::Any.new, T.any
    assert_equal T::App.new, T.app
    assert_equal T::AnyLabel.new(label: "x"), T.labeled("x")
    assert_equal T::Window.new(label: "x"), T.window("x")
    assert_equal T::Webview.new(label: "x"), T.webview("x")
    assert_equal T::WebviewWindow.new(label: "x"), T.webview_window("x")
  end

  def test_a_string_becomes_any_label_and_a_target_stays_itself
    assert_equal T.labeled("main"), T.from("main")
    assert_equal T.window("main"), T.from(T.window("main"))
    assert_raises(TypeError) { T.from(1) }
  end

  def test_to_json_is_serdes_internally_tagged_form
    assert_equal '{"kind":"Any"}', T.any.to_json
    assert_equal '{"kind":"App"}', T.app.to_json
    assert_equal '{"kind":"AnyLabel","label":"a"}', T.labeled("a").to_json
    assert_equal '{"kind":"Window","label":"a"}', T.window("a").to_json
    assert_equal '{"kind":"Webview","label":"a"}', T.webview("a").to_json
    assert_equal '{"kind":"WebviewWindow","label":"a"}', T.webview_window("a").to_json
  end

  def test_reads_each_variant_back
    [T.any, T.app, T.labeled("a"), T.window("a"), T.webview("a"), T.webview_window("a")].each do |target|
      assert_equal target, read(JSON.parse(target.to_json))
    end
  end

  # serde_json's Value reads an identifier only from a string
  # (value/de.rs:1025-1030), so a variant index is no tag.
  def test_ignores_unknown_fields
    assert_equal T.app, read({ "kind" => "App", "label" => "ignored" })
    assert_equal T.window("a"), read({ "kind" => "Window", "label" => "a", "extra" => 1 })
  end

  # serde's TaggedContentVisitor also reads a sequence whose first element
  # is the tag (private/de.rs:845-857), and a struct variant reads its
  # fields from the rest in order.
  def test_reads_the_sequence_form
    assert_equal T.window("a"), read(["Window", "a"])
    assert_equal T.app, read(["App"])
  end

  def test_rejects_in_serdes_words
    {
      "x" => 'invalid type: string "x", expected internally tagged enum EventTarget',
      nil => "invalid type: null, expected internally tagged enum EventTarget",
      {} => "missing field `kind`",
      { "kind" => "Nope" } => "unknown variant `Nope`, expected one of " \
        "`Any`, `AnyLabel`, `App`, `Window`, `Webview`, `WebviewWindow`",
      { "kind" => 1 } => "invalid type: integer `1`, expected variant identifier",
      { "kind" => -1 } => "invalid type: integer `-1`, expected variant identifier",
      { "kind" => true } => "invalid type: boolean `true`, expected variant identifier",
      { "kind" => "Window" } => "missing field `label`",
      { "kind" => "Window", "label" => 2 } => "invalid type: integer `2`, expected a string",
      [] => "missing field `kind`",
      ["Window"] => "invalid length 0, expected struct variant EventTarget::Window with 1 element",
      ["Window", "a", "b"] => "invalid length 2, expected 1 element in sequence",
      ["Webview", 3] => "invalid type: integer `3`, expected a string",
      ["Any", 1] => "invalid length 1, expected 0 elements in sequence",
      ["App", 1, 2] => "invalid length 2, expected 0 elements in sequence",
    }.each do |value, message|
      error = assert_raises(Tokra::Error::InvalidArgs) { read(value) }
      assert_equal "invalid args `target` for command `listen`: #{message}", error.message
    end
  end

  private def read(value)
    T.read(Tokra::Ipc::CommandItem.new(name: "listen", key: "target", payload: { "target" => value }))
  end
end
