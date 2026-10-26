# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: CC0-1.0 OR MIT-0 OR Apache-2.0
# SPDX-SnippetCopyrightText: Kornel Lesiński <kornel@geekhood.net>
# SPDX-SnippetComment: is_safe_to_strip_unc, is_valid_filename, is_reserved,
#                      and windows_char_len adapted from dunce 1.0.5 src/lib.rs

module Tokra
  module Plugins
    module Dialog
      # When a Windows path may drop its <tt>\\?\</tt> prefix.
      #
      # Windows hands some programs verbatim paths, such as
      # <tt>\\?\C:\Users\me</tt>, which many other programs cannot open.
      # Dropping the prefix is safe only when the shorter path means the
      # same file.
      #
      # This module answers that question as the dunce crate does, which
      # Tauri calls through <tt>FilePath::simplified</tt> before it returns a
      # picked path. Commands.simplified uses it on Windows.
      #
      # === Example
      #
      #   Dunce.safe_to_strip_unc?("\\\\?\\C:\\Users")  #=> true
      module Dunce
        # Windows file names dunce will not strip a prefix from
        # (dunce src/lib.rs:126-129).
        RESERVED_NAMES = %w[
          AUX
          NUL
          PRN
          CON
          COM1
          COM2
          COM3
          COM4
          COM5
          COM6
          COM7
          COM8
          COM9
          LPT1
          LPT2
          LPT3
          LPT4
          LPT5
          LPT6
          LPT7
          LPT8
          LPT9
        ].freeze

        # Whether dunce would strip the prefix of +path+ on Windows: a
        # verbatim disk path whose every component is a plain file name
        # Windows accepts and does not reserve, 260 units long at most
        # (dunce src/lib.rs:99-182).
        #
        # === Example
        #
        #   Dunce.safe_to_strip_unc?("\\\\?\\C:\\Users")  #=> true
        def self.safe_to_strip_unc?(path)
          return false unless path.match?(/\A\\\\\?\\[A-Za-z]:(?:\\|\z)/)

          rest = path[6..] || ""
          components = rest.split("\\").reject(&:empty?)
          return false unless components.all? { |name| !%w[. ..].include?(name) && valid_filename?(name) && !reserved?(name) }

          !(path.bytesize > 260 && windows_length(path) > 260)
        end

        # dunce's is_valid_filename (src/lib.rs:99-123).
        private_class_method def self.valid_filename?(name)
          return false if name.bytesize > 255 && windows_length(name) > 255
          return false if name.empty?
          return false if name.each_byte.any? { |byte| byte <= 31 || '<>:"/\\|?*'.include?(byte.chr) }

          !name.end_with?(" ", ".")
        end

        # dunce's is_reserved (src/lib.rs:131-143): the stem, without
        # trailing dots and spaces, is a DOS device name.
        private_class_method def self.reserved?(name)
          dot = name.rindex(".")
          stem = (dot && dot.positive?) ? name[0...dot] : name
          trimmed = stem.to_s.sub(/[ .]+\z/, "")
          trimmed.length <= 4 && RESERVED_NAMES.include?(trimmed.upcase)
        end

        # The length of +string+ in UTF-16 code units, as Windows counts.
        private_class_method def self.windows_length(string)
          string.each_char.sum { |char| (char.ord > 0xFFFF) ? 2 : 1 }
        end
      end
    end
  end
end

# SPDX-SnippetEnd
