# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"
require_relative "../../tasks/gem_version"

# Tests the version arithmetic behind bump:<gem>:*, which writes SemVer and
# still reads the RubyGems form older tags use.
class TestGemVersion < Minitest::Test
  private def bump(from, segment, label = nil)
    GemVersion.parse(from).next(segment, label).to_s
  end

  def test_a_segment_bump_resets_the_segments_after_it
    assert_equal "0.1.1", bump("0.1.0", :patch)
    assert_equal "0.2.0", bump("0.1.3", :minor)
    assert_equal "1.0.0", bump("0.4.2", :major)
  end

  def test_a_bump_finishes_a_prerelease_it_leads_up_to
    assert_equal "0.1.0", bump("0.1.0-pre.2", :patch)
    assert_equal "0.1.0", bump("0.1.0.pre.2", :minor)
    assert_equal "1.0.0", bump("1.0.0-rc.2", :major)
    assert_equal "1.0.0", bump("0.1.0-pre.2", :major)
  end

  def test_a_label_counts_up_toward_the_same_release_and_writes_semver
    assert_equal "0.1.0-pre.2", bump("0.1.0-pre.1", :patch, "pre")
    assert_equal "0.1.0-pre.2", bump("0.1.0-pre.1", :minor, "pre")
    assert_equal "0.1.0-rc.1", bump("0.1.0-beta.3", :patch, "rc")
    assert_equal "0.2.0-pre.1", bump("0.1.0", :minor, "pre")
    assert_equal "1.0.0-beta.1", bump("0.1.0-pre.2", :major, "beta")
  end

  def test_a_bump_from_the_rubygems_form_moves_to_a_release_it_can_precede
    assert_equal "1.0.0-beta.1", bump("0.1.0.pre.4", :major, "beta")
    assert_equal "0.1.0", bump("0.1.0.pre.4", :patch)
  end

  # tokra is at 0.0.1.pre.2 and each plugin at 0.0.1.pre.1; a minor bump
  # takes each to the plain 0.1.0 Plan 059 releases.
  def test_tokras_dotted_prerelease_bumps_to_a_plain_zero_one
    assert_equal "0.1.0", bump("0.0.1.pre.2", :minor)
    assert_equal "0.1.0", bump("0.0.1.pre.1", :minor)
    assert_equal "0.0.1", bump("0.0.1.pre.2", :patch)
  end

  def test_a_hyphenated_prerelease_cannot_follow_a_dotted_one_of_the_same_release
    error = assert_raises(ArgumentError) { bump("0.1.0.pre.4", :patch, "pre") }

    assert_equal "0.1.0-pre.5 would come before 0.1.0.pre.4, and no label changes that: RubyGems sorts every hyphenated 0.1.0 prerelease below the dotted 0.1.0.pre.4. Release it as 0.1.0 with a bump and no label, stay dotted with exact[0.1.0.pre.5], or move to a later release in SemVer form, like exact[0.1.1-pre.1]", error.message
    assert_raises(ArgumentError) { bump("0.1.0.pre.4", :patch, "rc") }
  end

  def test_a_dotted_conflict_names_the_choices_for_any_label
    error = assert_raises(ArgumentError) { bump("0.1.0.pre.4", :patch, "rc") }

    assert_includes error.message, "exact[0.1.0.pre.5]"
    assert_includes error.message, "exact[0.1.1-pre.1]"
    assert_includes error.message, "Release it as 0.1.0 with a bump and no label"
    refute_includes error.message, "pick a label"
  end

  def test_hyphenated_input_must_be_exact_semver
    ["1.0-beta.1", "1-beta.1", "1.0.0-beta.01", "01.0.0-beta.1", "1.0.0-beta.1.00", "1.0.0-1"].each do |text|
      assert_raises(ArgumentError, text) { GemVersion.parse(text) }
    end
    assert_equal "1.0.0-beta.1.0a", GemVersion.parse("1.0.0-beta.1.0a").to_s
    assert_equal "1.0.0-beta.0", GemVersion.parse("1.0.0-beta.0").to_s
  end

  def test_dotted_versions_round_trip_as_written
    %w[0.1.0.pre.4 1.0.0.beta1 1.0.0.beta.01 1.0 0.1.0].each do |text|
      assert_equal text, GemVersion.parse(text).to_s
    end
  end

  def test_a_label_that_sorts_backwards_is_refused
    error = assert_raises(ArgumentError) { bump("0.1.0-rc.1", :patch, "beta") }

    assert_equal "0.1.0-beta.1 would come before 0.1.0-rc.1; pick a label that sorts after rc", error.message
  end

  def test_to_s_writes_the_form_it_was_given
    assert_equal "1.0.0-beta.1", GemVersion.parse("1.0.0-beta.1").to_s
    assert_equal "0.1.0.pre.4", GemVersion.parse("0.1.0.pre.4").to_s
    assert_equal "0.1.0", GemVersion.parse("0.1.0").to_s
  end

  def test_rubygems_and_cargo_spell_the_other_forms
    assert_equal "1.0.0.pre.beta.1", GemVersion.parse("1.0.0-beta.1").rubygems
    assert_equal "0.2.0.pre.pre.1", GemVersion.parse("0.2.0-pre.1").rubygems
    assert_equal "1.0.0-beta.1", GemVersion.parse("1.0.0.beta.1").cargo
    assert_equal "0.1.0.pre.4", GemVersion.parse("0.1.0.pre.4").rubygems
  end

  def test_versions_order_as_rubygems_orders_them_across_forms
    assert_operator GemVersion.parse("0.1.0-pre.5"), :<, GemVersion.parse("0.1.0.pre.4")
    assert_operator GemVersion.parse("0.2.0-pre.1"), :>, GemVersion.parse("0.1.0.pre.4")
    assert_operator GemVersion.parse("0.1.0-pre.10"), :>, GemVersion.parse("0.1.0-pre.9")
    assert_operator GemVersion.parse("1.0.0-beta.1"), :>, GemVersion.parse("0.1.0.pre.4")
    assert_operator GemVersion.parse("1.0.0"), :>, GemVersion.parse("1.0.0-rc.1")
    assert_operator GemVersion.parse("1.0.0-rc.1"), :>, GemVersion.parse("1.0.0-beta.2")
  end

  def test_bad_input_is_refused
    assert_raises(ArgumentError) { GemVersion.parse("0.1.0-2") }
    assert_raises(ArgumentError) { GemVersion.parse("0.1.0-pre-2") }
    assert_raises(ArgumentError) { GemVersion.parse("0.1.0-pre+build") }
    assert_raises(ArgumentError) { GemVersion.parse("1.2.3.4") }
    assert_raises(ArgumentError) { GemVersion.parse("soon") }
    assert_raises(ArgumentError) { bump("0.1.0", :build) }
    assert_raises(ArgumentError) { bump("0.1.0", :patch, "pre-2") }
  end

  def test_versions_order_as_rubygems_orders_them
    assert_operator GemVersion.parse("0.1.0.pre.10"), :>, GemVersion.parse("0.1.0.pre.9")
    assert_operator GemVersion.parse("0.1.0"), :>, GemVersion.parse("0.1.0.pre.9")
  end

  def test_cargo_spells_a_prerelease_with_a_hyphen
    assert_equal "0.1.0-pre.2", GemVersion.parse("0.1.0.pre.2").cargo
    assert_equal "0.1.0-pre.2", GemVersion.parse("0.1.0-pre.2").cargo
    assert_equal "0.1.0", GemVersion.parse("0.1").cargo
  end

  def test_stable_means_one_point_oh_and_no_prerelease
    refute_predicate GemVersion.parse("0.9.0"), :stable?
    refute_predicate GemVersion.parse("1.0.0-rc.1"), :stable?
    assert_predicate GemVersion.parse("1.0.0"), :stable?
  end
end
