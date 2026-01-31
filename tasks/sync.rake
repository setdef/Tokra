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

    # Extract event_initialization_script
    init_match = content.match(/fn event_initialization_script.*?format!\(\s*r#"([^#]+)"#/m)
    if init_match
      init_template = init_match[1]
        .gsub("'{}'", "'%<emit_fn>s'")
        .gsub("{}", "%<listeners_obj>s")

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
    end

    puts "Done. Tauri JavaScript templates extracted."
  end
end
