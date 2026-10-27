# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Tauri compiles these only for macOS (tauri-runtime src/lib.rs:245-256,
# tauri src/app.rs:1149-1166), and tao defines the loop method under them
# only there (src/platform/macos.rs:310-345), so they exist only where the
# native loop has it.
return unless Tokra::Native::EventLoop.method_defined?(:set_activation_policy)

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: ActivationPolicy adapted from tauri-runtime src/lib.rs:245-256,
#                      App::set_activation_policy from tauri src/app.rs:1149-1166

module Tokra
  # How your app shows itself on macOS: in the Dock and the menu bar, or not.
  #
  # Most desktop apps show a Dock icon, own the menu bar while they are in
  # front, and come to the front when they launch. A menu bar utility or a
  # helper has no Dock icon, and an app that runs in the background never
  # comes to the front at all. AppKit calls the choice an activation policy.
  #
  # ActivationPolicy names the three AppKit policies. Pass one to
  # App#set_activation_policy. Use it to build a menu bar app (Accessory),
  # or an app whose windows never take the keyboard from the app you are
  # typing in (Prohibited). Regular is the default. These three are the
  # only policies, as in Tauri's enum, so ActivationPolicy.new is private.
  #
  # Defined only on macOS, as in Tauri.
  #
  # Mirrors Tauri's <tt>tauri::ActivationPolicy</tt> (tauri-runtime
  # src/lib.rs:245-256).
  #
  # === Examples
  #
  #   setup = Ractor.shareable_proc do |app|
  #     app.set_activation_policy(Tokra::ActivationPolicy::Accessory)
  #   end
  #   Tokra::Builder.default.setup(&setup).run
  #
  #   Tokra::ActivationPolicy::Prohibited.name  #=> "Prohibited"
  class ActivationPolicy < Data.define(:name)
    ##
    # Corresponds to NSApplicationActivationPolicyRegular: a Dock icon and
    # the menu bar, the way most apps run.
    Regular = new(name: "Regular")
    # Corresponds to NSApplicationActivationPolicyAccessory: no Dock icon
    # and no menu bar, but your windows can still come to the front.
    Accessory = new(name: "Accessory")
    # Corresponds to NSApplicationActivationPolicyProhibited: no Dock icon,
    # and the app never becomes the active app, so its windows never take
    # the keyboard.
    Prohibited = new(name: "Prohibited")

    # The three are the only policies, as Tauri's enum has only its three
    # variants, so no other can be made.
    private_class_method :new
  end

  class App
    # Sets the activation policy for the application. It is set to
    # <tt>NSApplicationActivationPolicyRegular</tt> by default.
    #
    # Call it in your setup hook, or on a built App before App#run. The
    # policy takes effect as the app finishes launching, before it would
    # come to the front, so a Prohibited app never takes focus from the app
    # you are using. Tokra has no AppHandle#set_activation_policy yet, so a
    # call after App#run has started its event loop changes nothing.
    #
    # Defined only on macOS, as in Tauri. Mirrors Tauri's
    # App::set_activation_policy (app.rs:1149-1166).
    #
    # === Examples
    #
    #   setup = Ractor.shareable_proc do |app|
    #     app.set_activation_policy(Tokra::ActivationPolicy::Accessory)
    #   end
    #   Tokra::Builder.default.setup(&setup).run
    #
    #   app = Tokra::Builder.default.build
    #   app.set_activation_policy(Tokra::ActivationPolicy::Prohibited)
    #   app.run
    def set_activation_policy(activation_policy)
      @activation_policy = activation_policy
      nil
    end
  end
end

# SPDX-SnippetEnd
