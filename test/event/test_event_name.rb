# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Event names allow what Tauri's is_event_name_valid allows: Unicode
# alphanumerics, '-', '/', ':', and '_' (event/event_name.rs:8-12), and a
# bad one raises IllegalEventName with Tauri's message (error.rs:163-165),
# the name quoted as Rust's Debug quotes it (event/mod.rs:243-251).
class TestEventName < Minitest::Test
  def test_tauris_own_illegal_name_test
    error = assert_raises(Tokra::Error::IllegalEventName) { Tokra::Event::Name.check("some\r illegal event name") }

    assert_equal "only alphanumeric, '-', '/', ':', '_' permitted for event names: \"some\\r illegal event name\"",
      error.message
  end

  def test_the_permitted_characters_pass
    %w[tauri://resize log://log a-b_c:d/e 123 ünïcødé 名前 Ⅻ].each do |name|
      assert_equal name, Tokra::Event::Name.check(name), name
    end
    assert_equal "", Tokra::Event::Name.check(""), "an empty name has no bad character"
  end

  def test_anything_else_is_illegal
    ["a b", "a.b", "a*", "emoji😀", "quote'"].each do |name|
      refute Tokra::Event::Name.valid?(name), name
      assert_raises(Tokra::Error::IllegalEventName) { Tokra::Event::Name.check(name) }
    end
  end

  def test_a_name_from_the_page_fails_with_the_deserializers_words
    item = Tokra::Ipc::CommandItem.new(name: "listen", key: "event", payload: { "event" => "a b" })
    error = assert_raises(Tokra::Error::InvalidArgs) { Tokra::Event::Name.read(item) }

    assert_equal "invalid args `event` for command `listen`: " \
      "Event name must include only alphanumeric characters, `-`, `/`, `:` and `_`.", error.message
  end

  def test_a_name_from_the_page_must_be_a_string
    item = Tokra::Ipc::CommandItem.new(name: "emit", key: "event", payload: { "event" => 1 })
    error = assert_raises(Tokra::Error::InvalidArgs) { Tokra::Event::Name.read(item) }

    assert_equal "invalid args `event` for command `emit`: invalid type: integer `1`, expected a string", error.message
  end
end
