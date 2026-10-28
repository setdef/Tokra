# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  # A Data class whose constants are its only values.
  #
  # Tauri's unit enums, such as Theme or CursorIcon, have a fixed set of
  # variants, and Rust can build no other. Tokra ports each as a Data
  # class with one constant per variant. Data still offers three ways to
  # build a value no variant names: +new+, <tt>[]</tt>, and #with. A class
  # that extends ClosedEnum hides the first two and gets a #with that
  # answers only one of its own constants.
  #
  # === Example
  #
  #   class Theme < Data.define(:name)
  #     extend ClosedEnum
  #     Light = new(name: "Light")
  #     close
  #   end
  module ClosedEnum # :nodoc: internal; Tauri has no such type
    # Makes +new+ and <tt>[]</tt> private, once every constant exists, and
    # closes #with.
    def close
      private_class_method :new, :[]
      include With
      nil
    end

    # The #with a closed enum's values answer.
    module With
      # The constant that differs from this value by +changes+, as
      # Data#with would build it. Raises ArgumentError when no constant
      # of the class is that value.
      def with(**changes)
        value = super
        klass = self.class
        klass.constants.map { |name| klass.const_get(name, false) }.find { |constant| constant == value } ||
          raise(ArgumentError, "no #{klass.name} has #{changes.inspect}")
      end
    end
  end
end
