# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Extracts JavaScript templates from Tauri source code.
#
# This task reads Tauri's Rust source files and extracts the JavaScript
# format strings used for WebView communication, generating .js files
# that Ruby can load at runtime.
#
# Run after updating the Tauri submodule:
#   rake sync:tauri
namespace :sync do
  desc "Extract JavaScript templates from Tauri submodule"
  task :tauri do
    tauri_event = Pathname("vendor/tauri/crates/tauri/src/event/mod.rs")
    output_dir = Pathname("lib/tokra/js")

    abort "Tauri submodule not found. Run: git submodule update --init" unless tauri_event.exist?

    content = tauri_event.read

    # Extract emit_js_script format string
    # Pattern: format!("(function () { const fn = window['{}']...
    emit_match = content.match(/fn emit_js_script.*?format!\(\s*"([^"]+)"/m)
    abort "Could not find emit_js_script in #{tauri_event}" unless emit_match

    # Original format: "(function () {{ const fn = window['{}']; fn && fn({{event: '{}', payload: {}}}, {ids}) }})()"
    # Placeholders in order: emit_function_name, event, payload, ids
    emit_template = emit_match[1]
      .gsub('\n', "\n")
      .sub("window['{}']", "window['%<emit_fn>s']")       # First '{}' is emit_fn
      .sub("event: '{}'", "event: '%<event>s'")           # Second '{}' is event
      .sub("payload: {}", "payload: %<payload>s")         # Third {} is payload
      .gsub("{ids}", "%<ids>s")

    output_dir.mkpath
    emit_file = output_dir.join("emit.js.erb")
    emit_file.write(<<~JS)
      // Auto-generated from Tauri source. Do not edit manually.
      // Source: vendor/tauri/crates/tauri/src/event/mod.rs
      // Regenerate with: rake sync:tauri
      //
      // SPDX-FileCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
      // SPDX-License-Identifier: Apache-2.0 OR MIT

      #{emit_template}
    JS

    puts "Generated #{emit_file}"

    # Extract event_initialization_script (a plain format! string with
    # named interpolations, not a raw string literal)
    init_match = content.match(/fn event_initialization_script.*?format!\(\s*"([^"]+)"/m)
    abort "Could not find event_initialization_script in #{tauri_event}" unless init_match

    init_template = init_match[1]
      .gsub("{{", "\x00").gsub("}}", "\x01")
      .gsub("{function_name}", "<%= function_name %>")
      .gsub("{listeners}", "<%= listeners %>")
      .gsub("\x00", "{").gsub("\x01", "}")

    init_file = output_dir.join("event_init.js.erb")
    init_file.write(<<~JS)
      // Auto-generated from Tauri source. Do not edit manually.
      // Source: vendor/tauri/crates/tauri/src/event/mod.rs
      // Regenerate with: rake sync:tauri
      //
      // SPDX-FileCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
      // SPDX-License-Identifier: Apache-2.0 OR MIT

      #{init_template}
    JS

    puts "Generated #{init_file}"

    # Vendor the webview initialization scripts verbatim, converting
    # Tauri's serialize-to-javascript markers into ERB tags. Template
    # values render as JS literals (JSON-encoded by the caller); raw
    # values splice scripts. See plan 014 and ADR 009.
    scripts_dir = Pathname("vendor/tauri/crates/tauri/scripts")
    banner = lambda do |name|
      <<~JS
        // Auto-generated from Tauri source. Do not edit manually.
        // Source: vendor/tauri/crates/tauri/scripts/#{name}
        // Regenerate with: rake sync:tauri
        //
        // SPDX-FileCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
        // SPDX-License-Identifier: Apache-2.0 OR MIT
      JS
    end

    %w[init.js pattern.js ipc.js ipc-protocol.js core.js].each do |name|
      source = scripts_dir.join(name)
      abort "Missing Tauri script: #{source}" unless source.exist?

      body = source.read
        .gsub(/__TEMPLATE_(\w+)__/) { "<%= #{Regexp.last_match(1)} %>" }
        .gsub(/__RAW_(\w+)__/) { "<%= #{Regexp.last_match(1)} %>" }
      target = output_dir.join("#{name}.erb")
      target.write("#{banner.call(name)}\n#{body}")
      puts "Generated #{target}"
    end

    # Vendor plain scripts verbatim (no template markers). bundle.global.js
    # is the prebuilt @tauri-apps/api IIFE that with_global_tauri injects as
    # window.__TAURI__ (Plan 015 D6); the API package's own rollup build
    # produces it, so we consume it and never hand-bundle Tauri's JavaScript.
    %w[process-ipc-message-fn.js bundle.global.js].each do |name|
      source = scripts_dir.join(name)
      abort "Missing Tauri script: #{source}" unless source.exist?

      target = output_dir.join(name)
      target.write("#{banner.call(name)}\n#{source.read}")
      puts "Generated #{target}"
    end

    puts "Done. Tauri JavaScript templates extracted."
  end
end
