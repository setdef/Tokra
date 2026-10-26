# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Tokra::PermissionState is Tauri's tauri::plugin::PermissionState
# (plugin.rs:1012-1045): four states, Prompt by default, each displayed
# and serialized as its lowercase, hyphenated name.
class TestPermissionState < Minitest::Test
  State = Tokra::PermissionState

  def test_each_state_displays_as_tauri_writes_it
    assert_equal %w[granted denied prompt prompt-with-rationale],
      [State::Granted, State::Denied, State::Prompt, State::PromptWithRationale].map(&:to_s)
  end

  def test_the_default_is_prompt
    assert_same State::Prompt, State.default
  end

  def test_a_state_serializes_as_its_name
    assert_equal '"prompt-with-rationale"', JSON.generate(State::PromptWithRationale)
    assert_equal '["granted"]', JSON.generate([State::Granted])
  end

  def test_states_are_shareable_values
    assert Ractor.shareable?(State::Granted)
    assert_equal State::Denied, State.new(name: "denied")
  end
end
