# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Color adapted from tauri-utils/src/config.rs

module Tokra
  # An RGBA color, each component a byte from 0 to 255.
  #
  # Window#set_background_color and Webview#set_background_color take
  # one. Color.from_str reads the hex notation CSS uses, such as
  # <tt>"#1e1e1e"</tt>.
  #
  # Mirrors Tauri's <tt>tauri::window::Color</tt>, a tuple struct of four
  # <tt>u8</tt>s (tauri-utils src/config.rs:1415-1490). Ruby's Data needs
  # names, so the components take the ones Tauri's own object form reads:
  # +red+, +green+, +blue+, and +alpha+ (plan 041, decision 2). A
  # component that is not an Integer raises TypeError, and one outside a
  # byte raises RangeError, where Rust would not compile.
  #
  # === Example
  #
  #   Tokra::Color.new(30, 30, 30, 255) == Tokra::Color.from_str("#1e1e1e")  #=> true
  class Color < Data.define(:red, :green, :blue, :alpha)
    ##
    # Tauri's error for hex text of any length but 3, 6, or 8.
    INVALID_LENGTH =
      "Invalid hex color length, must be either 3, 6 or 8, for example: #fff, #ffffff, or #ffffffff"

    # Rust's ParseIntError text for a digit u8::from_str_radix rejects.
    INVALID_DIGIT = "invalid digit found in string"

    # Reads +text+ as hex digits, with or without a leading <tt>#</tt>:
    # three digits are doubled and opaque, six are opaque, and eight end
    # with the alpha. Raises ArgumentError with Tauri's text for any other
    # length, and with Rust's for a pair of digits that is not hex.
    #
    # As Tauri does, it trims the whitespace around a <tt>#</tt> but reads
    # text without one as given, so <tt>" fff"</tt> is four characters
    # long and fails.
    #
    # Mirrors Tauri's <tt>FromStr for Color</tt> (config.rs:1468-1490).
    #
    # === Example
    #
    #   Tokra::Color.from_str("#f0a")  #=> #<data Tokra::Color red=255, green=0, blue=170, alpha=255>
    def self.from_str(text)
      text = text.to_str
      trimmed = text.strip
      digits = (trimmed.delete_prefix("#") if trimmed.start_with?("#")) || text
      digits = case digits.bytesize
      when 3 then "#{digits.chars.map { |char| char * 2 }.join}ff"
      when 6 then "#{digits}FF"
      when 8 then digits
      else raise ArgumentError, INVALID_LENGTH
      end
      new(
        red: byte(digits.byteslice(0, 2).to_s),
        green: byte(digits.byteslice(2, 2).to_s),
        blue: byte(digits.byteslice(4, 2).to_s),
        alpha: byte(digits.byteslice(6, 2).to_s)
      )
    end

    # The byte two hex digits name, as u8::from_str_radix reads them: a
    # leading + is allowed, and anything else but hex digits is not.
    private_class_method def self.byte(pair)
      raise ArgumentError, INVALID_DIGIT unless pair.match?(/\A\+?\h+\z/)

      Integer(pair.delete_prefix("+"), 16)
    end

    # Creates a color, raising TypeError for a component that is not an
    # Integer and RangeError for one outside 0..255.
    # A Data class validating in initialize: its RBS declares self.new, as
    # AGENTS.md asks, and Steep cannot see that self.new reaches this.
    def initialize(red:, green:, blue:, alpha:) # steep:ignore MethodParameterMismatch
      [red, green, blue, alpha].each do |component|
        raise TypeError, "wrong argument type #{component.class} (expected Integer)" unless component.is_a?(Integer)
        raise RangeError, "integer #{component} out of range of u8" unless component.between?(0, 255)
      end
      super
    end
  end
end

# SPDX-SnippetEnd
