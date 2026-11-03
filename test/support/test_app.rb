# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "stub_native"

# The one place the suite turns a Builder into an app.
#
# Every test that needs an app asks for it here, so a change to how an app is
# built (plan 054, session 054a-3) changes this file and not seventy tests.
# The methods are available in every Minitest::Test, and on the test classes
# themselves for a constant built in a class body.
module TestApp
  extend self

  # Builds an app from +builder+, standing +native+ in for the Rust binding.
  # +title+ and +width+/+height+ are applied to the builder first when given.
  def build_test_app(builder = Tokra::Builder.default, native: StubNative, title: nil, width: nil, height: nil)
    prepared_test_builder(builder, title:, width:, height:).build(native:)
  end

  # Runs an app built as #build_test_app builds it, passing +block+ to
  # Builder#run.
  def run_test_app(builder = Tokra::Builder.default, native: StubNative, title: nil, width: nil, height: nil, &)
    prepared_test_builder(builder, title:, width:, height:).run(native:, &)
  end

  private def prepared_test_builder(builder, title:, width:, height:)
    builder = builder.title(title) if title
    builder = builder.size(width, height) if width && height
    builder
  end
end

Minitest::Test.include(TestApp)
Minitest::Test.extend(TestApp)
