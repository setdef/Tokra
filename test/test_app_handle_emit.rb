# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Native.load_js_template's error for a template rake sync:tauri has not
# made yet. AppHandle#emit's own tests are in test/event/ (plan 047).
class TestLoadJsTemplate < Minitest::Test
  def test_load_js_template_development_error_mentions_rake
    # Stub File.exist? to simulate missing template in development checkout
    error = nil
    File.stub(:exist?, -> (path) { path.include?("Rakefile") }) do
      error = assert_raises(LoadError) do
        Tokra::Native.load_js_template("nonexistent.js.erb")
      end
    end

    assert_includes error.message, "bundle exec rake sync:tauri"
  end
end
