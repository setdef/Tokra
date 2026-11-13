# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rubygems"

# A gem's version, and the version a bump moves it to.
#
# Tokra writes versions as SemVer: <tt>0.1.0</tt>, or a prerelease such as
# <tt>1.0.0-beta.1</tt>, in version.rb, in tags, and in CHANGELOG headings
# (Plan 059, Versions). RubyGems stores that version as
# <tt>1.0.0.pre.beta.1</tt>, which is how Gemfile.lock and the built
# package's file name spell it. Versions released before that rule, such
# as tokra's <tt>0.0.1.pre.2</tt>, were written in RubyGems' form, and
# still are wherever they are tagged. This class reads either form, remembers which
# one it was given, and writes it back unchanged with #to_s; #rubygems and
# #cargo write the other two spellings. Ordering is RubyGems', which is
# what users' Bundler applies: it reads the hyphen of <tt>0.1.0-pre.5</tt>
# as <tt>.pre.</tt>, giving <tt>0.1.0.pre.pre.5</tt>, which sorts before
# <tt>0.1.0.pre.4</tt>, because a text segment sorts before a number.
#
# A bump always writes the SemVer form. This class is Ferro's
# <tt>tasks/gem_version.rb</tt>, unchanged but for this comment; Ferro
# ported its bump rules from ratatui_ruby-devtools 0.4.1
# (<tt>lib/ratatui_ruby/devtools/tasks/bump/sem_ver.rb</tt>). All three are
# by the same author under the same license.
#
# === Example
#
#   GemVersion.parse("0.1.0-pre.1").next(:patch, "pre").to_s  # => "0.1.0-pre.2"
#   GemVersion.parse("0.1.0-pre.2").next(:patch).to_s         # => "0.1.0"
#   GemVersion.parse("1.0.0-beta.1").rubygems                 # => "1.0.0.pre.beta.1"
#   GemVersion.parse("0.1.0.pre.2").cargo                     # => "0.1.0-pre.2"
class GemVersion
  include Comparable

  # The segments a bump can raise.
  SEGMENTS = %i[major minor patch].freeze

  # A prerelease label: a letter, then letters or digits.
  LABEL = /\A[a-zA-Z][a-zA-Z0-9]*\z/

  # SemVer's hyphenated form: three release numbers and a prerelease that
  # starts with a label, with no leading zeros in a numeric identifier.
  SEMVER = /\A(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*)){2}-[a-zA-Z][a-zA-Z0-9]*(?:\.(?:0|[1-9][0-9]*|[0-9]*[a-zA-Z][a-zA-Z0-9]*))*\z/

  # Parses +string+, such as <tt>"0.1.0"</tt>, <tt>"1.0.0-beta.1"</tt>, or
  # RubyGems' <tt>"0.1.0.pre.2"</tt>. Raises ArgumentError for anything
  # else. A hyphenated version must be SemVer: three release numbers, a
  # prerelease that starts with a label (RubyGems would read
  # <tt>1.0.0-1</tt> as a different version than it looks), and no leading
  # zeros. The result writes the string back exactly as given with #to_s.
  def self.parse(string)
    raise ArgumentError, "#{string.inspect} is not a version" unless Gem::Version.correct?(string)

    hyphenated = string.include?("-")
    raise ArgumentError, "#{string} is not SemVer. Write a prerelease like 1.0.0-beta.1." if hyphenated && !string.match?(SEMVER)

    if hyphenated
      base, label = string.split("-", 2)
      release = Gem::Version.new(base).segments
      prerelease = label.split(".").map { |identifier| identifier.match?(/\A\d+\z/) ? identifier.to_i : identifier }
    else
      segments = Gem::Version.new(string).segments
      release = segments.take_while { |segment| segment.is_a?(Integer) }
      prerelease = segments.drop(release.size)
    end
    raise ArgumentError, "#{string} has more than three release segments" if release.size > 3

    new((release + [0, 0, 0]).first(3), prerelease, semver: hyphenated || prerelease.empty?, text: (string unless hyphenated))
  end

  # [release] Three Integers: major, minor, patch.
  # [prerelease] The prerelease identifiers, such as <tt>["pre", 2]</tt>, or
  #   none.
  # [semver] Whether #to_s writes a prerelease with a hyphen (SemVer) rather
  #   than RubyGems' <tt>.pre.</tt> dots.
  # [text] The exact string a dotted version was parsed from, which #to_s
  #   returns unchanged, or nil.
  def initialize(release, prerelease = [], semver: true, text: nil)
    @text = text
    @release = release
    @prerelease = prerelease
    @semver = semver
  end

  # The major segment.
  def major
    @release[0]
  end

  # Whether this is a prerelease, such as <tt>0.1.0.pre.2</tt>.
  def prerelease?
    !@prerelease.empty?
  end

  # Whether this version promises a stable API: 1.0 or later, and not a
  # prerelease.
  def stable?
    major >= 1 && !prerelease?
  end

  # The version after bumping +segment+, which resets the segments after
  # it. A prerelease comes before its release, so bumping it to a segment
  # it already leads up to releases it: <tt>0.1.0.pre.2</tt> becomes
  # <tt>0.1.0</tt> on <tt>:patch</tt> or <tt>:minor</tt>.
  #
  # With a +label+, the result is a prerelease of that version instead.
  # Its number counts up from the prerelease you are on when that leads to
  # the same version under the same label, and starts at 1 otherwise:
  # <tt>0.1.0-pre.1</tt> becomes <tt>0.1.0-pre.2</tt> on <tt>:patch</tt>
  # with <tt>"pre"</tt>, and <tt>0.1.0-beta.3</tt> becomes
  # <tt>0.1.0-rc.1</tt> with <tt>"rc"</tt>.
  #
  # The result is always written as SemVer.
  #
  # Raises ArgumentError for an unknown segment, an invalid label, or a
  # labelled version that would come before this one in RubyGems' order
  # (labels sort as text, so <tt>beta</tt> cannot follow <tt>rc</tt>, and no
  # hyphenated prerelease can follow a dotted one of the same release, like
  # <tt>0.1.0.pre.4</tt>).
  def next(segment, label = nil)
    release = release_after(segment)
    return release unless label
    raise ArgumentError, "#{label.inspect} is not a prerelease label; use letters and digits, like pre" unless label.match?(LABEL)

    candidate = GemVersion.new(release.release, [label, count_toward(release, label) + 1])
    return candidate if candidate > self

    raise ArgumentError, dotted_conflict(candidate) if !@semver && @release == release.release

    raise ArgumentError, "#{candidate} would come before #{self}; pick a label that sorts after #{@prerelease.first}"
  end

  # Orders versions as RubyGems does.
  def <=>(other)
    to_gem_version <=> other.to_gem_version if other.is_a?(GemVersion)
  end

  # The version as RubyGems reads it.
  def to_gem_version
    Gem::Version.new(to_s)
  end

  # The version as it was written: SemVer's <tt>1.0.0-beta.1</tt>, or
  # RubyGems' <tt>0.1.0.pre.2</tt> if it was parsed in that form. This is
  # what version.rb, tags, and CHANGELOG headings hold.
  def to_s
    @text || (@semver ? cargo : [*@release, *@prerelease].join("."))
  end

  # The version as RubyGems stores it: <tt>1.0.0.pre.beta.1</tt>. This is
  # what Gemfile.lock and the built package's file name hold. RubyGems
  # reads a hyphen as <tt>.pre.</tt> whatever follows it, so the label
  # <tt>pre</tt> becomes <tt>0.1.0.pre.pre.2</tt>.
  def rubygems
    to_gem_version.to_s
  end

  # The version as Cargo writes it, which is SemVer: <tt>0.1.0-pre.2</tt>.
  def cargo
    prerelease? ? "#{@release.join('.')}-#{@prerelease.join('.')}" : @release.join(".")
  end

  protected attr_reader :release

  # Why no label helps a dotted prerelease reach a hyphenated one of its
  # own release, and the choices the maintainer has. The plain release
  # sorts above every prerelease of it, dotted or not.
  private def dotted_conflict(candidate)
    counted = @prerelease.last.is_a?(Integer) ? [*@prerelease[0...-1], @prerelease.last + 1] : [*@prerelease, 1]
    stay = GemVersion.new(@release, counted, semver: false)
    later = GemVersion.new([@release[0], @release[1], @release[2] + 1], ["pre", 1])
    "#{candidate} would come before #{self}, and no label changes that: RubyGems sorts every hyphenated " \
      "#{candidate.release.join('.')} prerelease below the dotted #{self}. Release it as #{candidate.release.join('.')} with a bump and " \
      "no label, stay dotted with exact[#{stay}], or move to a later release in SemVer form, like exact[#{later}]"
  end

  private def release_after(segment)
    index = SEGMENTS.index(segment) or raise ArgumentError, "#{segment.inspect} is not one of #{SEGMENTS.join(', ')}"
    return GemVersion.new(@release) if prerelease? && @release[(index + 1)..].all?(&:zero?)

    raised = @release.dup
    raised[index] += 1
    raised.fill(0, (index + 1)..2)
    GemVersion.new(raised)
  end

  # How many prereleases labelled +label+ this one has counted toward
  # +release+: 1 for pre.1, none for beta.3 or another version's pre.
  private def count_toward(release, label)
    return 0 unless @release == release.release && @prerelease.first == label

    (@prerelease[1].is_a?(Integer) && @prerelease.size == 2) ? @prerelease[1] : 0
  end
end
