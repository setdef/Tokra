# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Declared lint exceptions with justifications.
class Lint
  def self.load(path) = new(path)

  def initialize(path)
    @path = path
    instance_eval(File.read(path))
  end

  def allow(path, line: nil, lines: nil, lint: nil, reason:)
    line_numbers = lines || [line]
    line_numbers.each { |n| list << "#{path}:#{n}" }
  end

  # Enforce no violations. Aborts with message if any found, otherwise prints success.
  def enforce!(glob:, pattern:, reject_pattern: nil, violation_name:)
    found = violations(glob:, pattern:, reject_pattern:)

    abort <<~ERROR if found.any?
      ❌ Unapproved #{violation_name} found:
      #{found.join("\n")}

      Add to #{File.basename(@path)} with justification if truly unavoidable.
    ERROR

    puts "✅ No unapproved #{violation_name} found"
  end

  def violations(glob:, pattern:, reject_pattern: nil)
    Dir.glob(glob)
      .reject { |f| f.include?("/target/") }
      .flat_map { |file| File.readlines(file).map.with_index(1) { |line, n| [file, n, line] } }
      .select { |_, _, line| pattern.match?(line) }
      .reject { |_, _, line| reject_pattern&.match?(line) }
      .reject { |file, n, _| include?("#{file}:#{n}") }
      .map { |file, n, line| "  #{file}:#{n}: #{line.strip}" }
  end

  def include?(location) = list.any? { |ex| location.start_with?(ex) }
  def to_a = list
  def list = @list ||= []
end
