# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "test_helper"

# Tests for Tokra::Z85 against the ZeroMQ RFC 32 reference vector.
class TestZ85 < Minitest::Test
  def test_encodes_rfc_reference_vector
    # The RFC 32 test case: 0x86 0x4F 0xD2 0x6F 0xB5 0x59 0xF7 0x5B
    assert_equal "HelloWorld", Tokra::Z85.encode("\x86\x4F\xD2\x6F\xB5\x59\xF7\x5B".b)
  end

  def test_encodes_zero_frame_to_first_alphabet_character
    assert_equal "00000", Tokra::Z85.encode("\x00\x00\x00\x00".b)
  end

  def test_encodes_max_frame_to_last_alphabet_character
    assert_equal "%nSc0", Tokra::Z85.encode("\xFF\xFF\xFF\xFF".b)
  end

  def test_sixteen_bytes_encode_to_twenty_characters
    assert_equal 20, Tokra::Z85.encode("\x00" * 16).length
  end

  def test_rejects_length_not_divisible_by_four
    error = assert_raises(ArgumentError) { Tokra::Z85.encode("abc") }
    assert_equal "input length must be a multiple of 4", error.message
  end

  def test_generate_invoke_key_is_twenty_z85_characters
    key = Tokra.generate_invoke_key
    assert_equal 20, key.length
    assert(key.chars.all? { |c| Tokra::Z85::ALPHABET.include?(c) },
      "key should only contain Z85 alphabet characters")
  end

  def test_generate_invoke_key_is_unpredictable
    refute_equal Tokra.generate_invoke_key, Tokra.generate_invoke_key,
      "two generated keys should differ"
  end
end
