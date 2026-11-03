# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Monitor's JSON, as Tauri's derived Serialize with rename_all =
# "camelCase" writes it (window/mod.rs:57-65): the window plugin's
# monitor commands answer it.
class TestMonitor < Minitest::Test
  def monitor(name: "Built-in Retina Display")
    Tokra::Monitor.from_native([name, [0, -25], [2880, 1800], [[0, 25], [2880, 1750]], 2.0])
  end

  def test_a_monitor_writes_tauris_camel_case_keys_in_their_order
    expected = '{"name":"Built-in Retina Display","size":{"width":2880,"height":1800},"position":{"x":0,"y":-25},' \
      '"workArea":{"position":{"x":0,"y":25},"size":{"width":2880,"height":1750}},"scaleFactor":2.0}'

    assert_equal expected, monitor.to_json
    assert_equal "[#{expected}]", JSON.generate([monitor])
  end

  def test_a_monitor_without_a_name_writes_null
    assert_nil JSON.parse(monitor(name: nil).to_json).fetch("name")
  end

  # scale_factor is an f64, which serde_json writes with its point.
  def test_a_monitor_writes_its_scale_factor_as_a_float
    size = Tokra::PhysicalSize.new(width: 1, height: 1)
    position = Tokra::PhysicalPosition.new(x: 0, y: 0)
    monitor = Tokra::Monitor.new(name: nil, size:, position:,
      work_area: Tokra::PhysicalRect.new(position:, size:), scale_factor: 2)

    assert_includes monitor.to_json, '"scaleFactor":2.0}'
  end
end
