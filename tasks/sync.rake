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
    output_dir.mkpath
    event_banner = <<~JS
      // Auto-generated from Tauri source. Do not edit manually.
      // Source: vendor/tauri/crates/tauri/src/event/mod.rs
      // Regenerate with: rake sync:tauri
      //
      // SPDX-FileCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
      // SPDX-License-Identifier: Apache-2.0 OR MIT
    JS

    # Each event script is a format! string (event/mod.rs): its first
    # string literal becomes an ERB template, Rust's doubled braces
    # unescaped and each named {placeholder} an ERB tag. emit_js_script's
    # three positional {} name the emit function, the event, and the
    # payload, in the order its arguments give them (Plan 047).
    {
      "emit_js_script" => ["emit.js.erb", %w[function_name event payload]],
      "listen_js_script" => ["listen.js.erb", []],
      "unlisten_js_script" => ["unlisten.js.erb", []],
      "event_initialization_script" => ["event_init.js.erb", []],
    }.each do |function, (file, positional)|
      match = content.match(/fn #{function}\b.*?format!\(\s*"([^"]+)"/m)
      abort "Could not find #{function} in #{tauri_event}" unless match

      names = positional.dup
      # One left-to-right pass, as Rust's format parser reads it.
      template = match[1].gsub(/\{\{|\}\}|\{(\w*)\}/) do |token|
        case token
        when "{{" then "{"
        when "}}" then "}"
        else "<%= #{Regexp.last_match(1).to_s.empty? ? names.shift : Regexp.last_match(1)} %>"
        end
      end
      target = output_dir.join(file)
      target.write("#{event_banner}\n#{template}\n")
      puts "Generated #{target}"
    end

    # The event plugin's init script (event/init.js), whose one RAW marker
    # takes the unregister function event/plugin.rs builds.
    plugin_init = Pathname("vendor/tauri/crates/tauri/src/event/init.js")
    plugin_init_file = output_dir.join("event_plugin_init.js.erb")
    plugin_init_file.write(<<~JS)
      // Auto-generated from Tauri source. Do not edit manually.
      // Source: vendor/tauri/crates/tauri/src/event/init.js
      // Regenerate with: rake sync:tauri
      //
      // SPDX-FileCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
      // SPDX-License-Identifier: Apache-2.0 OR MIT

      #{plugin_init.read.gsub(/__RAW_(\w+)__/) { "<%= #{Regexp.last_match(1)} %>" }}
    JS
    puts "Generated #{plugin_init_file}"

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
