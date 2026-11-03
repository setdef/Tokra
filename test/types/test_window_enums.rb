# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# The readers for the window plugin's enum arguments, each as its Rust
# type's Deserialize reads serde_json's Value (plan 050, decision 5), and
# Theme's JSON.
class TestWindowEnums < Minitest::Test
  private def mismatch(&)
    assert_raises(Tokra::Ipc::CommandItem::Mismatch, &).message
  end

  # CursorIcon's own Deserialize reads a String and matches it lowercased;
  # any other name is Default (tauri-runtime src/window.rs:160-206).
  def test_a_cursor_icon_reads_any_case_and_falls_back_to_default
    assert_same Tokra::CursorIcon::NotAllowed, Tokra::CursorIcon.deserialize("NOTALLOWED")
    assert_same Tokra::CursorIcon::NotAllowed, Tokra::CursorIcon.deserialize("notAllowed")
    assert_same Tokra::CursorIcon::Default, Tokra::CursorIcon.deserialize("bogus")
    assert_same Tokra::CursorIcon::Default, Tokra::CursorIcon.deserialize("not-allowed")
    Tokra::CursorIcon.constants.each do |name|
      icon = Tokra::CursorIcon.const_get(name)
      assert_same icon, Tokra::CursorIcon.deserialize(icon.name.downcase), name
      assert_same icon, Tokra::CursorIcon.deserialize(icon.name.upcase), name
    end
    assert_equal "invalid type: integer `1`, expected a string", mismatch { Tokra::CursorIcon.deserialize(1) }
    assert_equal "invalid type: map, expected a string", mismatch { Tokra::CursorIcon.deserialize({ "Wait" => nil }) }
  end

  # Theme's Deserialize: "dark" in any case is Dark, and anything else
  # Light (tauri-utils src/lib.rs:238-250).
  def test_a_theme_is_dark_only_for_dark
    assert_same Tokra::Theme::Dark, Tokra::Theme.deserialize("DARK")
    assert_same Tokra::Theme::Dark, Tokra::Theme.deserialize("dark")
    assert_same Tokra::Theme::Light, Tokra::Theme.deserialize("x")
    assert_same Tokra::Theme::Light, Tokra::Theme.deserialize("Light")
    assert_equal "invalid type: null, expected a string", mismatch { Tokra::Theme.deserialize(nil) }
  end

  # TitleBarStyle's Deserialize: "transparent" and "overlay" in any case,
  # and anything else Visible (tauri-utils src/lib.rs:189-201).
  def test_a_title_bar_style_falls_back_to_visible
    assert_same Tokra::TitleBarStyle::Overlay, Tokra::TitleBarStyle.deserialize("OVERLAY")
    assert_same Tokra::TitleBarStyle::Transparent, Tokra::TitleBarStyle.deserialize("Transparent")
    assert_same Tokra::TitleBarStyle::Visible, Tokra::TitleBarStyle.deserialize("visible")
    assert_same Tokra::TitleBarStyle::Visible, Tokra::TitleBarStyle.deserialize("x")
    assert_equal "invalid type: boolean `true`, expected a string", mismatch { Tokra::TitleBarStyle.deserialize(true) }
  end

  # ResizeDirection derives Deserialize with no renaming
  # (tauri-runtime src/lib.rs:105-116): only Tauri's names.
  def test_a_resize_direction_reads_only_tauris_names
    names = %w[East North NorthEast NorthWest South SouthEast SouthWest West]
    names.each { |name| assert_same Tokra::ResizeDirection.const_get(name), Tokra::ResizeDirection.deserialize(name) }
    assert_same Tokra::ResizeDirection::West, Tokra::ResizeDirection.deserialize({ "West" => nil })
    assert_equal "unknown variant `east`, expected one of #{names.map { |name| "`#{name}`" }.join(', ')}",
      mismatch { Tokra::ResizeDirection.deserialize("east") }
    assert_equal "invalid type: integer `1`, expected unit", mismatch { Tokra::ResizeDirection.deserialize({ "East" => 1 }) }
  end

  # UserAttentionType is internally tagged on "type"
  # (tauri-runtime src/lib.rs:79-91): a map whose other keys are ignored,
  # or a sequence that holds the tag alone (serde private/de.rs:845-886,
  # 2983-2996).
  def test_a_user_attention_type_reads_its_tag_from_a_map_or_a_sequence
    assert_same Tokra::UserAttentionType::Critical, Tokra::UserAttentionType.deserialize({ "type" => "Critical" })
    assert_same Tokra::UserAttentionType::Informational,
      Tokra::UserAttentionType.deserialize({ "type" => "Informational", "other" => [1] })
    assert_same Tokra::UserAttentionType::Informational, Tokra::UserAttentionType.deserialize(["Informational"])
    assert_equal "invalid length 1, expected 0 elements in sequence",
      mismatch { Tokra::UserAttentionType.deserialize(["Critical", 1]) }
  end

  def test_a_user_attention_type_rejects_in_serdes_words
    assert_equal "missing field `type`", mismatch { Tokra::UserAttentionType.deserialize({ "kind" => "Critical" }) }
    assert_equal "missing field `type`", mismatch { Tokra::UserAttentionType.deserialize([]) }
    assert_equal "unknown variant `critical`, expected `Critical` or `Informational`",
      mismatch { Tokra::UserAttentionType.deserialize({ "type" => "critical" }) }
    assert_equal "invalid type: integer `1`, expected variant identifier",
      mismatch { Tokra::UserAttentionType.deserialize({ "type" => 1 }) }
    assert_equal "invalid type: string \"Critical\", expected internally tagged enum UserAttentionType",
      mismatch { Tokra::UserAttentionType.deserialize("Critical") }
  end

  # Theme serializes as its Display text, lowercase (tauri-utils
  # src/lib.rs:228-236, 252-260).
  def test_a_theme_writes_its_lowercase_name
    assert_equal '"light"', Tokra::Theme::Light.to_json
    assert_equal '["dark"]', JSON.generate([Tokra::Theme::Dark])
  end
end
