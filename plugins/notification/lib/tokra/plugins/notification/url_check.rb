# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: MIT OR Apache-2.0
# SPDX-SnippetCopyrightText: 2013-2022 The rust-url developers
# SPDX-SnippetComment: The failures of Url::parse adapted from url 2.5.4
#                      src/parser.rs (parse_url, parse_scheme,
#                      parse_with_scheme, parse_non_special, parse_file,
#                      after_double_slash, parse_userinfo,
#                      parse_host_and_port, parse_host, file_host,
#                      parse_port) and src/host.rs (Host::parse,
#                      parse_opaque, ends_in_a_number, parse_ipv4number,
#                      parse_ipv4addr, parse_ipv6addr), and idna 1.0.3
#                      src/uts46.rs (AsciiDenyList::URL and the ASCII path
#                      of process_innermost)

module Tokra
  module Plugins
    module Notification
      # Checks a URL the way Tauri's notification plugin reads one.
      #
      # An attachment names its file by URL, and Tauri reads it with the
      # url crate, which follows the WHATWG URL Standard. A URL it cannot
      # parse rejects the whole notification with url's words: "relative
      # URL without a base", "invalid port number", and the rest.
      #
      # UrlCheck.check walks the same steps as url's parser where they can
      # fail: the scheme, the authority, the port, and the host, IPv4,
      # IPv6, opaque, or a domain name through idna's ASCII rules. It
      # raises UrlCheck::Error with url's message, or returns the string.
      #
      # *Deviation*: a domain with non-ASCII characters, or a label that
      # starts with <tt>xn--</tt>, passes without idna's Unicode (UTS 46)
      # processing, which Ruby has no tables for. url would reject some of
      # them as an invalid international domain name.
      #
      # Mirrors url 2.5.4's <tt>Url::parse</tt> (parser.rs:370-394) as
      # Tauri's <tt>Attachment</tt> deserializes it (models.rs:11-16).
      #
      # === Examples
      #
      #   UrlCheck.check("file:///tmp/image.png")  #=> "file:///tmp/image.png"
      #   UrlCheck.check("image.png")
      #   # raises UrlCheck::Error: relative URL without a base
      module UrlCheck
        # A URL url's parser refuses, with url's message
        # (parser.rs:82-93).
        class Error < StandardError; end

        # url's messages for the failures this check finds.
        EMPTY_HOST = "empty host"
        # The message for a domain idna refuses.
        IDNA = "invalid international domain name"
        # The message for a bad port.
        INVALID_PORT = "invalid port number"
        # The message for a bad IPv4 address.
        INVALID_IPV4 = "invalid IPv4 address"
        # The message for a bad IPv6 address.
        INVALID_IPV6 = "invalid IPv6 address"
        # The message for a bad opaque host.
        INVALID_DOMAIN_CHARACTER = "invalid domain character"
        # The message for a string with no scheme.
        RELATIVE = "relative URL without a base"

        # The special schemes other than file (parser.rs:170-178).
        SPECIAL = %w[http https ws wss ftp].freeze

        # The default port of each special scheme (parser.rs:180-187).
        DEFAULT_PORTS = { "http" => 80, "ws" => 80, "https" => 443, "wss" => 443, "ftp" => 21 }.freeze

        # The code points an opaque host refuses (host.rs:113-136).
        OPAQUE_FORBIDDEN = "\0\t\n\r #/:<>?@[\\]^|"

        # The ASCII idna refuses in a domain for a URL: the forbidden
        # domain code points and every glyphless one (uts46.rs:72-85,
        # 351).
        DENIED = "%#/:<>?@[\\]^|".bytes.to_set.merge((0..0x20).to_a << 0x7F).freeze

        # +string+, or UrlCheck::Error with url's message.
        #
        # === Example
        #
        #   UrlCheck.check("asset://localhost/icon.png")  #=> "asset://localhost/icon.png"
        def self.check(string)
          input = string.gsub(/\A[\u0000- ]+|[\u0000- ]+\z/, "").delete("\t\n\r")
          scheme = input[/\A[A-Za-z][A-Za-z0-9+\-.]*(?=:)/] or raise Error, RELATIVE
          rest = input[(scheme.length + 1)..]
          scheme = scheme.downcase
          if scheme == "file"
            file(rest)
          elsif SPECIAL.include?(scheme)
            authority(rest.sub(%r{\A[/\\]*}, ""), scheme, special: true)
          elsif rest.start_with?("//")
            authority(rest[2..], scheme, special: false)
          end
          string
        end

        # A file URL's host, after two slashes (parser.rs:504-520,
        # 1045-1102).
        private_class_method def self.file(rest)
          return unless rest.match?(%r{\A[/\\]{2}})

          host = rest[2..][%r{\A[^/\\?#]*}]
          return if host.empty? || host.match?(/\A[A-Za-z][:|]\z/)

          domain(host)
        end

        # The authority after the slashes: user information, host, and
        # port (parser.rs:836-977).
        private_class_method def self.authority(rest, scheme, special:)
          rest, has_authority = userinfo(rest, special)
          host_text = host_text(rest, special)
          rest = rest[(host_text.length)..]
          raise Error, EMPTY_HOST if host_text.empty? && special

          host = special ? domain(host_text) : opaque(host_text)
          raise Error, EMPTY_HOST if host.empty? && rest.start_with?(":")

          port(rest[1..], DEFAULT_PORTS[scheme]) if rest.start_with?(":")
          raise Error, EMPTY_HOST if host.empty? && has_authority
        end

        # What follows the last @ before the path, and whether the user
        # information wrote anything (parser.rs:871-944).
        private_class_method def self.userinfo(rest, special)
          scope = rest[special ? %r{\A[^/?#\\]*} : %r{\A[^/?#]*}]
          at = scope.rindex("@")
          return [rest, false] unless at

          after = rest[(at + 1)..]
          if at.zero?
            raise Error, EMPTY_HOST if after.match?(special ? %r{\A[/?#\\]} : %r{\A[/?#]})

            return [after, false]
          end
          info = rest[0...at]
          username, password = info.split(":", 2)
          [after, !username.empty? || !password.to_s.empty?]
        end

        # The host's text, up to its port or path (parser.rs:979-1035).
        private_class_method def self.host_text(rest, special)
          inside = false
          length = rest.each_char.take_while do |char|
            break_char = (char == ":" && !inside) || (char == "\\" && special) || "/?#".include?(char)
            inside = true if char == "["
            inside = false if char == "]"
            !break_char
          end.length
          rest[0, length]
        end

        # A port of up to 65535, ended by a path, query, or fragment
        # (parser.rs:1104-1138).
        private_class_method def self.port(rest, _default)
          value = 0
          rest.each_char do |char|
            if char.match?(/\A[0-9]\z/)
              value = (value * 10) + char.to_i
              raise Error, INVALID_PORT if value > 65_535
            elsif "/\\?#".include?(char)
              break
            else
              raise Error, INVALID_PORT
            end
          end
        end

        # A special URL's host: an IPv6 address in brackets, or a domain
        # through idna, which may name an IPv4 address (host.rs:82-104).
        private_class_method def self.domain(text)
          return ipv6(text) if text.start_with?("[")

          bytes = text.b.gsub(/%(\h\h)/) { Regexp.last_match(1).hex.chr }
          domain = ascii_domain(bytes)
          raise Error, EMPTY_HOST if domain.empty?

          ipv4(domain) if ends_in_a_number?(domain)
          domain
        end

        # idna's ToASCII with the URL deny list, for what Ruby can check:
        # UTF-8 with no denied ASCII byte, no Punycode label ending in a
        # hyphen, and ASCII letters lowercased (uts46.rs:1075-1240).
        private_class_method def self.ascii_domain(bytes)
          text = bytes.dup.force_encoding(Encoding::UTF_8)
          raise Error, IDNA unless text.valid_encoding?
          raise Error, IDNA if text.bytes.any? { |byte| DENIED.include?(byte) }
          raise Error, IDNA if text.split(".").any? { |label| label.match?(/\Axn--/i) && label.end_with?("-") && label.ascii_only? }

          text.downcase(:ascii)
        end

        # A non-special URL's host: an IPv6 address in brackets, or any
        # text without a forbidden code point (host.rs:106-144).
        private_class_method def self.opaque(text)
          return ipv6(text) if text.start_with?("[")
          raise Error, INVALID_DOMAIN_CHARACTER if text.match?(/[#{Regexp.escape(OPAQUE_FORBIDDEN)}]/o)

          text
        end

        # Whether the last label is a number, so the host is an IPv4
        # address (host.rs:240-259).
        private_class_method def self.ends_in_a_number?(domain)
          labels = domain.split(".", -1)
          last = labels.pop
          if last.empty?
            return false if labels.empty?

            last = labels.pop
          end
          return true if !last.empty? && last.match?(/\A[0-9]+\z/)

          !ipv4_number(last).nil?
        end

        # The value of one IPv4 part, +:overflow+ for one past 32 bits, or
        # +nil+ when it is not a number (host.rs:261-296).
        private_class_method def self.ipv4_number(text)
          return nil if text.empty?

          radix = 10
          if text.start_with?("0x", "0X")
            text = text[2..]
            radix = 16
          elsif text.length >= 2 && text.start_with?("0")
            text = text[1..]
            radix = 8
          end
          return 0 if text.empty?

          valid = { 8 => /\A[0-7]+\z/, 10 => /\A[0-9]+\z/, 16 => /\A\h+\z/ }.fetch(radix)
          return nil unless text.match?(valid)

          value = text.to_i(radix)
          (value > 0xFFFF_FFFF) ? :overflow : value
        end

        # An IPv4 address of one to four parts (host.rs:298-326).
        private_class_method def self.ipv4(domain)
          parts = domain.split(".", -1)
          parts.pop if parts.last == ""
          raise Error, INVALID_IPV4 if parts.length > 4

          numbers = parts.map do |part|
            value = ipv4_number(part)
            raise Error, INVALID_IPV4 if value.nil? || value == :overflow

            value
          end
          last = numbers.pop
          raise Error, INVALID_IPV4 if last > (0xFFFF_FFFF >> (8 * numbers.length))
          raise Error, INVALID_IPV4 if numbers.any? { |number| number > 255 }
        end

        # An IPv6 address in brackets (host.rs:83-88, 328-470).
        private_class_method def self.ipv6(text)
          raise Error, INVALID_IPV6 unless text.end_with?("]")

          ipv6_address(text[1...-1].b)
          text
        end

        # The WHATWG IPv6 parser, failing where url's does
        # (host.rs:328-470).
        private_class_method def self.ipv6_address(input)
          invalid = -> { raise Error, INVALID_IPV6 }
          len = input.bytesize
          pieces = [0] * 8
          pointer = 0
          compress = nil
          i = 0
          invalid.call if len < 2
          if input.getbyte(0) == 58
            invalid.call unless input.getbyte(1) == 58
            i = 2
            pointer = 1
            compress = 1
          end
          ipv4 = false
          while i < len
            invalid.call if pointer == 8
            if input.getbyte(i) == 58
              invalid.call if compress
              i += 1
              pointer += 1
              compress = pointer
              next
            end
            start = i
            stop = [len, start + 4].min
            value = 0
            while i < stop && (digit = input.byteslice(i)&.then { |char| char.match?(/\A\h\z/) && char.hex })
              value = (value * 16) + digit
              i += 1
            end
            if i < len
              case input.getbyte(i)
              when 46
                invalid.call if i == start
                i = start
                invalid.call if pointer > 6
                ipv4 = true
              when 58
                i += 1
                invalid.call if i == len
              else invalid.call
              end
            end
            break if ipv4

            pieces[pointer] = value
            pointer += 1
          end

          if ipv4
            invalid.call if pointer > 6
            seen = 0
            while i < len
              if seen.positive?
                invalid.call unless seen < 4 && input.getbyte(i) == 46
                i += 1
              end
              piece = nil
              while i < len && (byte = input.getbyte(i)).between?(48, 57)
                invalid.call if piece&.zero?
                piece = ((piece || 0) * 10) + (byte - 48)
                invalid.call if piece > 255
                i += 1
              end
              invalid.call unless piece
              seen += 1
              pointer += 1 if seen == 2 || seen == 4
            end
            invalid.call unless seen == 4
          end
          invalid.call if i < len
          invalid.call if compress.nil? && pointer != 8
        end
      end
    end
  end
end

# SPDX-SnippetEnd
