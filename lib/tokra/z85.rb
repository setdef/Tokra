# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  # Z85 binary-to-text encoding (ZeroMQ RFC 32).
  #
  # Tauri encodes its per-app invoke key as Z85 text (via the z85 crate
  # in lib.rs). Ruby's stdlib has Base64 but no Z85, and using a
  # different encoding would diverge from Tauri's key format for no
  # reason.
  #
  # This module ports the encoder: every 4 input bytes become 5
  # characters from the 85-character alphabet. Only encoding is needed —
  # the key is generated, injected, and compared as text, never decoded.
  #
  # === Example
  #
  #   Tokra::Z85.encode("\x86\x4F\xD2\x6F\xB5\x59\xF7\x5B".b)  #=> "HelloWorld"
  module Z85
    # The 85-character alphabet from ZeroMQ RFC 32, in value order.
    ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz" \
      "ABCDEFGHIJKLMNOPQRSTUVWXYZ" \
      ".-:+=^!/*?&<>()[]{}@%$#".chars.freeze

    # Place values for the five output characters of each 4-byte frame:
    # 85**4, 85**3, 85**2, 85**1, 85**0.
    DIVISORS = [52_200_625, 614_125, 7_225, 85, 1].freeze

    # Encodes a binary string whose length is a multiple of 4.
    #
    # Raises ArgumentError otherwise, like the reference implementation.
    #
    # === Example
    #
    #   Tokra::Z85.encode("\x00\x00\x00\x00".b)  #=> "00000"
    def self.encode(bytes)
      unless (bytes.bytesize % 4).zero?
        raise ArgumentError, "input length must be a multiple of 4"
      end

      bytes.unpack("N*").flat_map do |word|
        frame = word.to_i
        DIVISORS.map { |divisor| ALPHABET[(frame / divisor) % 85] }
      end.join
    end
  end
end
