# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "support/notification_test"

# The notify command's options, read as Tauri reads NotificationData.
#
# Every expected message here came from Tauri's own types: models.rs from
# plugins-workspace d4613ff0, compiled with the versions its Cargo.lock
# pins (serde 1.0.228, serde_json 1.0.140, time 0.3.41, url 2.5.4, idna
# 1.0.3), deserializing each JSON value with serde_json::from_value. A
# nil expectation means Tauri accepted the value. Each date's expectation
# is the moment Tauri parsed, as nanoseconds since the epoch and the
# offset in seconds, and each accepted URL's is the serialization Tauri
# parsed it to.
class TestArguments < Minitest::Test
  include NotificationTest

  Arguments = Notification::Commands::Arguments

  SERDE_CASES = [
    ["{}", nil],
    ["null", "invalid type: null, expected struct NotificationData"],
    ["[]", "invalid length 1, expected struct NotificationData with 20 elements"],
    ["1", "invalid type: integer `1`, expected struct NotificationData"],
    ["\"x\"", "invalid type: string \"x\", expected struct NotificationData"],
    ["{\"title\":1}", "invalid type: integer `1`, expected a string"],
    ["{\"title\":null}", nil],
    ["{\"id\":null}", "invalid type: null, expected i32"],
    ["{\"id\":-2147483648}", nil],
    ["{\"id\":2147483648}", "invalid value: integer `2147483648`, expected i32"],
    ["{\"id\":-2147483649}", "invalid value: integer `-2147483649`, expected i32"],
    ["{\"id\":1.5}", "invalid type: floating point `1.5`, expected i32"],
    ["{\"id\":1e20}", "invalid type: floating point `1e20`, expected i32"],
    ["{\"id\":1.5e-7}", "invalid type: floating point `1.5e-7`, expected i32"],
    ["{\"id\":\"3\"}", "invalid type: string \"3\", expected i32"],
    ["{\"id\":18446744073709551616}", "invalid type: floating point `1.8446744073709552e19`, expected i32"],
    ["{\"groupSummary\":null}", "invalid type: null, expected a boolean"],
    ["{\"groupSummary\":\"yes\"}", "invalid type: string \"yes\", expected a boolean"],
    ["{\"inboxLines\":null}", "invalid type: null, expected a sequence"],
    ["{\"inboxLines\":[\"a\",2]}", "invalid type: integer `2`, expected a string"],
    ["{\"inboxLines\":\"a\"}", "invalid type: string \"a\", expected a sequence"],
    ["{\"extra\":null}", "invalid type: null, expected a map"],
    ["{\"extra\":[1]}", "invalid type: sequence, expected a map"],
    ["{\"extra\":{\"a\":[1,{\"b\":null}]}}", nil],
    ["{\"attachments\":[{\"id\":\"a\"}]}", "missing field `url`"],
    ["{\"attachments\":[{\"url\":\"file:///x\"}]}", "missing field `id`"],
    ["{\"attachments\":[{\"id\":1,\"url\":\"x\"}]}", "invalid type: integer `1`, expected a string"],
    ["{\"attachments\":[{\"id\":\"a\",\"url\":1}]}", "invalid type: integer `1`, expected a string representing an URL"],
    ["{\"attachments\":[[\"a\",\"file:///x\"]]}", nil],
    ["{\"attachments\":[[\"a\"]]}", "invalid length 1, expected struct Attachment with 2 elements"],
    ["{\"attachments\":[[\"a\",\"file:///x\",\"extra\"]]}", "invalid length 3, expected fewer elements in array"],
    ["{\"attachments\":[1]}", "invalid type: integer `1`, expected struct Attachment"],
    ["{\"attachments\":{\"id\":\"a\"}}", "invalid type: map, expected a sequence"],
    ["{\"schedule\":null}", nil],
    ["{\"schedule\":\"at\"}", "invalid type: unit variant, expected struct variant"],
    ["{\"schedule\":\"daily\"}", "unknown variant `daily`, expected one of `at`, `interval`, `every`"],
    ["{\"schedule\":{}}", "invalid value: map, expected map with a single key"],
    ["{\"schedule\":{\"at\":{},\"every\":{}}}", "invalid value: map, expected map with a single key"],
    ["{\"schedule\":{\"at\":null}}", "invalid type: null, expected struct variant"],
    ["{\"schedule\":{\"at\":[1]}}", "invalid type: sequence, expected struct variant"],
    ["{\"schedule\":{\"at\":{}}}", "missing field `date`"],
    ["{\"schedule\":{\"at\":{\"date\":1}}}", "invalid type: integer `1`, expected an ISO 8601-formatted `OffsetDateTime`"],
    ["{\"schedule\":{\"at\":{\"date\":\"2026-10-26T12:00:00Z\",\"repeating\":null}}}", "invalid type: null, expected a boolean"],
    ["{\"schedule\":{\"interval\":{}}}", "missing field `interval`"],
    ["{\"schedule\":{\"interval\":{\"interval\":{\"hour\":300}}}}", "invalid value: integer `300`, expected u8"],
    ["{\"schedule\":{\"interval\":{\"interval\":{\"hour\":-1}}}}", "invalid value: integer `-1`, expected u8"],
    ["{\"schedule\":{\"interval\":{\"interval\":[1,2,3]}}}", "invalid length 3, expected struct ScheduleInterval with 7 elements"],
    ["{\"schedule\":{\"interval\":{\"interval\":[1,2,3,4,5,6,7]}}}", nil],
    ["{\"schedule\":{\"interval\":{\"interval\":[1,2,3,4,5,6,7,8]}}}", "invalid length 8, expected fewer elements in array"],
    ["{\"schedule\":{\"interval\":{\"interval\":\"x\"}}}", "invalid type: string \"x\", expected struct ScheduleInterval"],
    ["{\"schedule\":{\"every\":{\"interval\":\"TwoWeeks\",\"count\":1}}}", nil],
    ["{\"schedule\":{\"every\":{\"interval\":\"fortnight\",\"count\":1}}}", "unknown every kind 'fortnight'"],
    ["{\"schedule\":{\"every\":{\"interval\":\"day\"}}}", "missing field `count`"],
    ["{\"schedule\":{\"every\":{\"count\":300,\"interval\":\"day\"}}}", "invalid value: integer `300`, expected u8"],
    ["{\"schedule\":{\"every\":{\"interval\":3,\"count\":1}}}", "invalid type: integer `3`, expected a string"],
    ["{\"schedule\":true}", "invalid type: boolean `true`, expected string or map"],
    ["{\"title\":\"x\",\"body\":\"tab\\there \\\"q\\\" \\u0001 é\"}", nil],
    ["{\"body\":[\"x\"]}", "invalid type: sequence, expected a string"],
    ["{\"sound\":{\"a\":1}}", "invalid type: map, expected a string"],
    ["{\"title\":true,\"body\":1}", "invalid type: integer `1`, expected a string"],
    ["[1]", "invalid length 1, expected struct NotificationData with 20 elements"],
    ["[1,\"c\",\"t\",\"b\",null,null,null,null,null,false,null,[],null,null,null,[],{},false,false,false]", nil],
    ["[1,\"c\",\"t\",\"b\",null,null,null,null,null,false,null,[],null,null,null,[],{},false,false,false,1]", "invalid length 21, expected fewer elements in array"],
    ["[1,\"c\",\"t\",\"b\",null,null,null,null,null,false,null,[],null,null,null]", nil],
    ["[1,\"c\",\"t\",\"b\",null,null,null,null,null,false]", "invalid length 10, expected struct NotificationData with 20 elements"],
    ["[1,\"c\",\"t\",\"b\",null,null,null,null,null]", "invalid length 10, expected struct NotificationData with 20 elements"],
    ["{\"visibility\":1,\"number\":3,\"title\":\"ok\"}", nil],
    ["{\"silent\":0}", "invalid type: integer `0`, expected a boolean"],
    ["{\"id\":-0.0}", "invalid type: floating point `-0.0`, expected i32"],
    ["{\"id\":\"a\\u0000b\\t\\\"\\\\\"}", "invalid type: string \"a\\0b\\t\\\"\\\\\", expected i32"],
    [
      "{\"id\":\"a\\u0301\\u200b\\u0085\\u00a0\\u2028 \\u00ad\\ue000x\\u200c\\u001f\\u007f\"}",
      "invalid type: string \"a\\u{301}\\u{200b}\\u{85}\\u{a0}\\u{2028} \\u{ad}\\u{e000}x\\u{200c}\\u{1f}\\u{7f}\", expected i32",
],
    ["{\"id\":0.00005}", "invalid type: floating point `0.00005`, expected i32"],
    ["{\"id\":0.000001}", "invalid type: floating point `1e-6`, expected i32"],
    ["{\"id\":1e16}", "invalid type: floating point `1e16`, expected i32"],
    ["{\"id\":1e15}", "invalid type: floating point `1000000000000000.0`, expected i32"],
  ].freeze

  DATE_CASES = [
    ["2026-10-26T12:00:60Z", "second must be in the range 0..=59 because leap seconds are not supported"],
    ["2026-10-26T12:00:00.000Z", [1793016000000000000, 0]],
    ["2026-10-26T12:00:00Z", [1793016000000000000, 0]],
    ["2026-13-01T00:00:00Z", "unexpected trailing characters; the end of input was expected"],
    ["2026-02-30T00:00:00Z", "day must be in the range 1..=28 for the given month and year"],
    ["2024-02-29T00:00:00Z", [1709164800000000000, 0]],
    ["2023-02-29T00:00:00Z", "day must be in the range 1..=28 for the given month and year"],
    ["20261026T120000Z", [1793016000000000000, 0]],
    ["2026-10-26T12:00Z", [1793016000000000000, 0]],
    ["2026-10-26T12Z", "unexpected trailing characters; the end of input was expected"],
    ["2026-10-26T12.5Z", [1793017800000000000, 0]],
    ["2026-10-26T12:30.5Z", [1793017830000000000, 0]],
    ["2026-10-26T12:30:15,25+01:00", [1793014215250000000, 3600]],
    ["2026-10-26T12:30:15+0100", [1793014215000000000, 3600]],
    ["2026-10-26T1230+01:00", [1793014200000000000, 3600]],
    ["20261026T12:30Z", "unexpected trailing characters; the end of input was expected"],
    ["2026-299T12:00Z", [1793016000000000000, 0]],
    ["2025-366T12:00Z", "ordinal must be in the range 1..=365 for the given year"],
    ["2024-366T12:00Z", [1735646400000000000, 0]],
    ["2026-W01-1T09+01", "unexpected trailing characters; the end of input was expected"],
    ["2026W011T09Z", [1766998800000000000, 0]],
    ["2026-W53-1T00Z", "unexpected trailing characters; the end of input was expected"],
    ["2020-W53-5T00Z", "unexpected trailing characters; the end of input was expected"],
    ["+002026-10-26T00:00:00Z", [1792972800000000000, 0]],
    ["-000001-01-01T00:00:00Z", [-62198755200000000000, 0]],
    ["+010000-01-01T00:00:00Z", "unexpected trailing characters; the end of input was expected"],
    ["2026-10-26", "the `Parsed` struct did not include enough information to construct the type"],
    ["2026-10-26T", "unexpected trailing characters; the end of input was expected"],
    ["T12:00Z", "the 'year' component could not be parsed"],
    ["12:00:00Z", "the `Parsed` struct did not include enough information to construct the type"],
    ["Z", "the `Parsed` struct did not include enough information to construct the type"],
    ["garbage", "the 'year' component could not be parsed"],
    ["", "the 'year' component could not be parsed"],
    ["2026-10-26T24:00:00Z", "unexpected trailing characters; the end of input was expected"],
    ["2026-10-26T23:60:00Z", "unexpected trailing characters; the end of input was expected"],
    ["2026-12-31T23:59:60Z", [1798761599999999999, 0]],
    ["2026-10-31T23:59:60Z", [1793491199999999999, 0]],
    ["2026-12-31T23:59:60.5Z", [1798761599999999999, 0]],
    ["2027-01-01T00:59:60+01:00", [1798761599999999999, 3600]],
    ["2026-10-26T12:00:00+24:00", "unexpected trailing characters; the end of input was expected"],
    ["2026-10-26T12:00:00-00:30", [1793017800000000000, -1800]],
    ["2026-10-26T12:00:00+05:60", "unexpected trailing characters; the end of input was expected"],
    ["2026-10-26T12:00:00.9999999999Z", "unexpected trailing characters; the end of input was expected"],
    ["2026-10-26T12:00:00.123456789Z", [1793016000123456789, 0]],
    ["2026-10-26T12:00:00.Z", "unexpected trailing characters; the end of input was expected"],
    ["2026-1026T12:00Z", "unexpected trailing characters; the end of input was expected"],
    ["202610-26T12:00Z", "unexpected trailing characters; the end of input was expected"],
    ["2026-10-26 12:00:00Z", "unexpected trailing characters; the end of input was expected"],
    ["2026-10-26T12:00:00", "the `Parsed` struct did not include enough information to construct the type"],
    ["2026-00-10T00:00Z", "unexpected trailing characters; the end of input was expected"],
    ["2026-10-00T00:00Z", "unexpected trailing characters; the end of input was expected"],
    ["2026-000T00:00Z", "unexpected trailing characters; the end of input was expected"],
    ["2026-W00-1T00Z", "unexpected trailing characters; the end of input was expected"],
    ["2026-W10-8T00Z", "unexpected trailing characters; the end of input was expected"],
    ["2026-W10T00Z", "unexpected trailing characters; the end of input was expected"],
    ["2026-10-26T12:00:00z", "unexpected trailing characters; the end of input was expected"],
    ["2026-10-26t12:00:00Z", "unexpected trailing characters; the end of input was expected"],
    ["2026-10-26T12:00:00+01:00:00", "unexpected trailing characters; the end of input was expected"],
    ["1234", "the `Parsed` struct did not include enough information to construct the type"],
    ["12", "the `Parsed` struct did not include enough information to construct the type"],
    ["2026-10-26T12:00:00.000+05:45", [1792995300000000000, 20700]],
    ["-9999-01-01T00:00Z", "the 'year' component could not be parsed"],
    ["-9999-W01-1T00Z", "the 'year' component could not be parsed"],
    ["2026-10-26T12:5Z", "unexpected trailing characters; the end of input was expected"],
    ["2026-10-26T12:00:0Z", "unexpected trailing characters; the end of input was expected"],
    ["2026-10-26T12:00:00+1", "unexpected trailing characters; the end of input was expected"],
    ["2026-10-26T12:00:00+1:00", "unexpected trailing characters; the end of input was expected"],
  ].freeze

  URL_CASES = [
    ["file:///tmp/a.png", nil, "file:///tmp/a.png"],
    ["asset://localhost/a.png", nil, "asset://localhost/a.png"],
    ["image.png", "relative URL without a base: \"image.png\""],
    ["", "relative URL without a base: \"\""],
    ["http://", "empty host: \"http://\""],
    ["http:///x", nil, "http://x/"],
    ["http://example.com:65535/", nil, "http://example.com:65535/"],
    ["http://example.com:65536/", "invalid port number: \"http://example.com:65536/\""],
    ["http://example.com:8a/", "invalid port number: \"http://example.com:8a/\""],
    ["http://example.com:/", nil, "http://example.com/"],
    ["http://[::1]/", nil, "http://[::1]/"],
    ["http://[::1/", "invalid IPv6 address: \"http://[::1/\""],
    ["http://[1:2:3:4:5:6:7:8:9]/", "invalid IPv6 address: \"http://[1:2:3:4:5:6:7:8:9]/\""],
    ["http://[::ffff:1.2.3.4]/", nil, "http://[::ffff:102:304]/"],
    ["http://[::ffff:1.2.3.04]/", "invalid IPv6 address: \"http://[::ffff:1.2.3.04]/\""],
    ["http://1.2.3.4/", nil, "http://1.2.3.4/"],
    ["http://1.2.3.256/", "invalid IPv4 address: \"http://1.2.3.256/\""],
    ["http://0x7f.1/", nil, "http://127.0.0.1/"],
    ["http://999999999999/", "invalid IPv4 address: \"http://999999999999/\""],
    ["http://a.b.1/", "invalid IPv4 address: \"http://a.b.1/\""],
    ["http://a.b.09/", "invalid IPv4 address: \"http://a.b.09/\""],
    ["http://exa mple.com/", "invalid international domain name: \"http://exa mple.com/\""],
    ["http://exa%20mple.com/", "invalid international domain name: \"http://exa%20mple.com/\""],
    ["http://EXAMPLE.com/", nil, "http://example.com/"],
    ["http://ex%41mple.com/", nil, "http://example.com/"],
    ["http://user@/", "empty host: \"http://user@/\""],
    ["http://@/", "empty host: \"http://@/\""],
    ["http://@host/", nil, "http://host/"],
    ["http://user:pass@host:80/", nil, "http://user:pass@host/"],
    ["http://:@host/", nil, "http://host/"],
    ["http://xn--abc-.com/", "invalid international domain name: \"http://xn--abc-.com/\""],
    ["http://xn--nxasmq6b.com/", nil, "http://xn--nxasmq6b.com/"],
    ["http://bücher.de/", nil, "http://xn--bcher-kva.de/"],
    ["foo://", nil, "foo://"],
    ["foo://:80", "empty host: \"foo://:80\""],
    ["foo://user@", "empty host: \"foo://user@\""],
    ["foo://exa mple/", "invalid domain character: \"foo://exa mple/\""],
    ["foo://[::1]:5/", nil, "foo://[::1]:5/"],
    ["foo://h:99999/", "invalid port number: \"foo://h:99999/\""],
    ["foo:bar", nil, "foo:bar"],
    ["mailto:x@y", nil, "mailto:x@y"],
    ["file://host/x", nil, "file://host/x"],
    ["file://C:/x", nil, "file:///C:/x"],
    ["file://exa mple/x", "invalid international domain name: \"file://exa mple/x\""],
    ["file://[::1/x", "invalid IPv6 address: \"file://[::1/x\""],
    ["1http://x", "relative URL without a base: \"1http://x\""],
    ["  http://x.com  ", nil, "http://x.com/"],
    ["http\t://x.com", nil, "http://x.com/"],
    ["data:text/plain,hi", nil, "data:text/plain,hi"],
    ["http:\\\\example.com\\x", nil, "http://example.com/x"],
    ["ws://a.b", nil, "ws://a.b/"],
    ["http://a..b/", nil, "http://a..b/"],
    ["http://.example/", nil, "http://.example/"],
    ["http://%zz.com/", "invalid international domain name: \"http://%zz.com/\""],
    ["http://a%2Fb.com/", "invalid international domain name: \"http://a%2Fb.com/\""],
    ["http://[::1]:80x/", "invalid port number: \"http://[::1]:80x/\""],
    ["http://host:0080/", nil, "http://host/"],
    ["http://xn--a/", "invalid international domain name: \"http://xn--a/\""],
    ["http://xn--a.xn--b/", "invalid international domain name: \"http://xn--a.xn--b/\""],
    ["http://xn--Mnchen-3YA.de/", nil, "http://xn--mnchen-3ya.de/"],
    ["http://faß.de/", nil, "http://xn--fa-hia.de/"],
    ["http://ｅｘａｍｐｌｅ.com/", nil, "http://example.com/"],
    ["http://a。b/", nil, "http://a.b/"],
    ["http://a\u200Cb.com/", "invalid international domain name: \"http://a\\u{200c}b.com/\""],
    ["http://\u094D\u0915.in/", "invalid international domain name: \"http://\\u{94d}\u0915.in/\""],
    ["http://אב.com/", nil, "http://xn--4dbc.com/"],
    ["http://%C3%BC.de/", nil, "http://xn--tda.de/"],
    ["http://x%80y/", "invalid international domain name: \"http://x%80y/\""],
    ["http://１.２.３.４/", nil, "http://1.2.3.4/"],
    ["http://a\u00ADb/", nil, "http://ab/"],
    ["http://\uFFFD.com/", "invalid international domain name: \"http://\uFFFD.com/\""],
    ["http://\u2488.com/", "invalid international domain name: \"http://\u2488.com/\""],
    ["file://bücher/x", nil, "file://xn--bcher-kva/x"],
    ["foo://bücher/", nil, "foo://b%C3%BCcher/"],
    ["HTTP://ｅｘａｍｐｌｅ.com:80/a/../b", nil, "http://example.com/b"],
  ].freeze

  # Every value reads as Tauri reads it, or rejects with Tauri's message
  # wrapped in its InvalidArgs text (tauri error.rs:59-60).
  def test_each_value_reads_as_serde_reads_it
    SERDE_CASES.each do |json, expected|
      assert_reading({ "options" => JSON.parse(json) }, expected, json)
    end
  end

  # time's ISO 8601 parser, through Schedule::At's date
  # (models.rs:100-105).
  def test_each_date_parses_as_time_parses_it
    DATE_CASES.each do |text, expected|
      options = { "schedule" => { "at" => { "date" => text } } }
      if expected.is_a?(String)
        assert_reading({ "options" => options }, expected, text)
      else
        date = read(options).schedule.date
        assert_equal expected, [(date.to_r * 1_000_000_000).to_i, date.utc_offset], text
      end
    end
  end

  # url's parser, through Attachment's url (models.rs:11-16), with url's
  # message and the string as Rust's Debug quotes it
  # (url lib.rs:2936). An accepted URL is held parsed, as Tauri's
  # url::Url field holds it.
  def test_each_url_parses_as_url_parses_it
    URL_CASES.each do |url, expected, serialized|
      options = { "attachments" => [{ "id" => "a", "url" => url }] }
      if expected
        assert_reading({ "options" => options }, expected, url.inspect)
      else
        parsed = read(options).attachments.first.url
        assert_instance_of Ferro::Url::Url, parsed, url.inspect
        assert_equal serialized, parsed.as_str, url.inspect
      end
    end
  end

  # Deviation (Plan 030): ferro-url's idna reads Unicode 18.0's UTS 46
  # tables, where Tauri's lockfile has Unicode 15.1's (ICU4X 1.5), so a
  # domain with a character Unicode 16.0 or later assigned, or one of the
  # 66 older ones UTS 46 16.0 no longer refuses, such as Georgian
  # capital letters, parses where Tauri answers "invalid international
  # domain name".
  def test_a_domain_in_newer_unicode_parses
    { "http://\u10A0.ge/" => "http://xn--rkj.ge/", "http://\u{10D50}.com/" => "http://xn--dh0d.com/" }.each do |url, serialized|
      assert_equal serialized, read({ "attachments" => [{ "id" => "a", "url" => url }] }).attachments.first.url.as_str
    end
  end

  # serde_json's map is a BTreeMap, so the first bad field in key order
  # is the one reported, not the first the frontend sent.
  def test_the_first_bad_field_in_key_order_is_reported
    assert_equal "invalid args `options` for command `notify`: invalid type: integer `1`, expected a string",
      notify_rejection({ "title" => true, "body" => 1 })
  end

  # The fields reach NotificationData with Tauri's names and defaults
  # (models.rs:148-210).
  def test_every_field_reaches_notification_data
    data = read({
      "id" => 7,
      "channelId" => "c",
      "title" => "t",
      "body" => "b",
      "largeBody" => "lb",
      "summary" => "s",
      "actionTypeId" => "a",
      "group" => "g",
      "groupSummary" => true,
      "sound" => "Ping",
      "inboxLines" => ["1", "2"],
      "icon" => "i",
      "largeIcon" => "li",
      "iconColor" => "#fff",
      "attachments" => [["x", "file:///x"]],
      "extra" => { "k" => [1, nil] },
      "ongoing" => true,
      "autoCancel" => true,
      "silent" => true,
      "schedule" => { "every" => { "interval" => "TWOWEEKS", "count" => 2 } },
      "visibility" => 1,
    })

    assert_equal [7, "c", "t", "b", "lb", "s", "a", "g", true, "Ping", ["1", "2"], "i", "li", "#fff"],
      data.to_h.values_at(:id, :channel_id, :title, :body, :large_body, :summary, :action_type_id, :group,
        :group_summary, :sound, :inbox_lines, :icon, :large_icon, :icon_color)
    assert_equal [Notification::Attachment.new(id: "x", url: Ferro::Url::Url.parse("file:///x"))], data.attachments
    assert_equal({ "k" => [1, nil] }, data.extra)
    assert_equal [true, true, true], [data.ongoing, data.auto_cancel, data.silent]
    assert_equal Notification::Schedule::Every.new(interval: Notification::ScheduleEvery::TwoWeeks, count: 2), data.schedule
  end

  def test_missing_fields_take_taurus_defaults
    data = read({})

    assert_kind_of Integer, data.id
    assert_includes(-(2 ** 31)...(2 ** 31), data.id)
    assert_nil data.title
    assert_equal [false, [], [], {}, false, false, false],
      [data.group_summary, data.inbox_lines, data.attachments, data.extra, data.ongoing, data.auto_cancel, data.silent]
  end

  def test_schedules_read_into_their_variants
    at = read({ "schedule" => { "at" => { "date" => "2026-10-26T12:00:00.000Z", "repeating" => true } } }).schedule
    assert_equal Notification::Schedule::At.new(date: Time.utc(2026, 10, 26, 12), repeating: true), at

    interval = read({ "schedule" => { "interval" => { "interval" => { "hour" => 9, "minute" => 0 } } } }).schedule
    assert_equal Notification::Schedule::Interval.new(interval: Notification::ScheduleInterval.new(hour: 9, minute: 0)),
      interval
  end

  private def read(options)
    Arguments.new({ "options" => options }, "notify").notification_data
  end

  private def assert_reading(payload, expected, label)
    if expected
      error = assert_raises(Tokra::Error::InvalidArgs, label) { Arguments.new(payload, "notify").notification_data }
      assert_equal "invalid args `options` for command `notify`: #{expected}", error.message, label
    else
      assert_kind_of Notification::NotificationData, Arguments.new(payload, "notify").notification_data, label
    end
  end
end
