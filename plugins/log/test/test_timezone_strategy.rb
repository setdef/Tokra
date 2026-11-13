# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# TimezoneStrategy chooses the clock of the default timestamps and of
# rotated file names (lib.rs:132-147).
class TestTimezoneStrategy < Minitest::Test
  TimezoneStrategy = Tokra::Plugins::Log::TimezoneStrategy

  # Data class structure

  def test_use_utc_is_data_class_with_no_fields
    use_utc = TimezoneStrategy::UseUtc.new

    assert_kind_of Data, use_utc
    assert_equal [], use_utc.members
  end

  def test_use_local_is_data_class_with_no_fields
    use_local = TimezoneStrategy::UseLocal.new

    assert_kind_of Data, use_local
    assert_equal [], use_local.members
  end

  # get_now: the time crate's now, as Tauri's get_now (lib.rs:138-147)

  def test_use_utc_gets_now_in_utc_from_the_time_crate
    before = Ferro::Time::OffsetDateTime.now_utc
    now = TimezoneStrategy::UseUtc.new.get_now

    assert_instance_of Ferro::Time::OffsetDateTime, now
    assert now.offset.is_utc
    assert_operator now, :>=, before
  end

  def test_use_local_gets_now_in_the_local_offset
    now = TimezoneStrategy::UseLocal.new.get_now

    assert_instance_of Ferro::Time::OffsetDateTime, now
    assert_equal Ferro::Time::UtcOffset.current_local_offset, now.offset
  end

  # Rust cannot always learn the local offset; Tauri falls back to UTC.
  def test_use_local_falls_back_to_utc_when_the_local_offset_is_unknown
    unknown = -> { raise Ferro::Time::Error::IndeterminateOffset }
    now = Ferro::Time::OffsetDateTime.stub(:now_local, unknown) { TimezoneStrategy::UseLocal.new.get_now }

    assert now.offset.is_utc
  end
end
