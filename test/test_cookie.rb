# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tokra::Cookie holds what the cookie crate 0.18.1's Cookie holds, which
# Tauri's cookie methods take and answer (tauri-runtime lib.rs:46;
# cookie src/lib.rs:215-239): a name and a value, and the optional
# expiration, max age, domain, path, and flags, each unset until given
# (plan 052, 052e-2).
class TestCookie < Minitest::Test
  Cookie = Tokra::Cookie

  def test_a_cookie_needs_only_a_name_and_a_value
    cookie = Cookie.new(name: "session", value: "abc")

    assert_equal "session", cookie.name
    assert_equal "abc", cookie.value
    %i[expires max_age domain path secure http_only same_site partitioned].each do |field|
      assert_nil cookie.public_send(field), "#{field} is unset, as the cookie crate's Option is None"
    end
  end

  def test_each_field_takes_only_its_type
    {
      name: :session,
      value: 1,
      expires: Time.now,
      max_age: 1.5,
      domain: :localhost,
      path: Pathname("/"),
      secure: 1,
      http_only: "true",
      same_site: "Lax",
      partitioned: :yes,
    }.each do |field, wrong|
      fields = { name: "n", value: "v" }.merge(field => wrong)

      assert_raises(TypeError, "#{field} refuses #{wrong.inspect}") { Cookie.new(**fields) }
    end
  end

  def test_same_site_is_one_of_the_cookie_crates_three
    assert_equal %w[Strict Lax None], [Cookie::SameSite::Strict, Cookie::SameSite::Lax, Cookie::SameSite::None].map(&:name)
    assert_raises(NoMethodError) { Cookie::SameSite.new(name: "Loose") }
  end

  def test_an_expiration_is_a_moment_or_the_session
    moment = Cookie::Expiration::DateTime.new(datetime: Time.at(0).utc)

    assert_equal Time.at(0).utc, moment.datetime
    assert_raises(TypeError) { Cookie::Expiration::DateTime.new(datetime: 0) }
    assert_equal Cookie::Expiration::Session.new, Cookie.new(name: "n", value: "v", expires: Cookie::Expiration::Session.new).expires
  end

  # The native side reads an expiration as "Session" or whole Unix seconds,
  # as wry reads and writes them (wkwebview/mod.rs:1003-1013, 1043-1051;
  # webview2/mod.rs:1538-1552, 1574-1584).
  def test_a_cookie_crosses_to_the_native_side_as_a_hash_and_back
    session = Cookie.new(name: "a", value: "1", expires: Cookie::Expiration::Session.new, same_site: Cookie::SameSite::Lax)
    dated = Cookie.new(name: "b", value: "2", expires: Cookie::Expiration::DateTime.new(datetime: Time.at(1_700_000_000.9)))

    expected = {
      name: "a",
      value: "1",
      expires: "Session",
      max_age: nil,
      domain: nil,
      path: nil,
      secure: nil,
      http_only: nil,
      same_site: "Lax",
      partitioned: nil,
    }

    assert_equal expected, session.native_fields
    assert_equal 1_700_000_000, dated.native_fields[:expires], "whole seconds, as wry's unix_timestamp"
    assert_equal session, Cookie.from_native(session.native_fields)
    assert_equal Time.at(1_700_000_000).utc, Cookie.from_native(dated.native_fields).expires.datetime
  end

  # The time crate wry's cookie crate uses holds years -9999 to 9999
  # (time 0.3 without large-dates), and the cookie crate's max_age an i64
  # of seconds, so a cookie outside them is refused here, on the calling
  # thread, rather than inside the main thread's task.
  def test_an_expiration_or_max_age_the_cookie_crate_cannot_hold_raises_range_error
    first = -377_705_116_800
    last = 253_402_300_799

    assert_equal last, Cookie::Expiration::DateTime.new(datetime: Time.at(last)).datetime.to_i
    assert_equal first, Cookie::Expiration::DateTime.new(datetime: Time.at(first)).datetime.to_i
    assert_raises(RangeError) { Cookie::Expiration::DateTime.new(datetime: Time.at(last + 1)) }
    assert_raises(RangeError) { Cookie::Expiration::DateTime.new(datetime: Time.at(first - 1)) }
    assert_equal (2 ** 63) - 1, Cookie.new(name: "n", value: "v", max_age: (2 ** 63) - 1).max_age
    assert_equal(-2 ** 63, Cookie.new(name: "n", value: "v", max_age: -2 ** 63).max_age)
    assert_raises(RangeError) { Cookie.new(name: "n", value: "v", max_age: 2 ** 63) }
    assert_raises(RangeError) { Cookie.new(name: "n", value: "v", max_age: (-2 ** 63) - 1) }
  end
end
