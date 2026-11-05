# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# WebKit's occlusion detection, turned off for a fixture's webviews on
# macOS (Plan 060), through the Objective-C runtime with Fiddle, as the
# window_handle fixture reads its window. FixtureApp.keep_page_awake
# calls it for every fixture that builds on FixtureApp, and the
# native_loop fixture, which drives Tokra::Native without it, calls it
# for its own windows.
#
# WebKit gives a page's WebContent, GPU, and Networking processes a
# foreground RunningBoard assertion only while the view is visible, and
# on macOS a view whose window is occluded is not
# (PageClientImplMac.mm:208-230 and WebPageProxy.cpp:4053-4078, WebKit
# main 827737a4d7cc). WindowServer never draws a session off the
# console, so there each window counts as occluded, the processes drop
# to background priority, and on a busy machine a page starves mid-check.
# WebKit's own test runner turns occlusion detection off for the same
# reason (Tools/WebKitTestRunner/mac/PlatformWebViewMac.mm:103), and then
# the view is visible while its window is ordered in and the view is not
# hidden. The setter only stores the flag (WebViewImpl.h:395), so each
# webview is hidden and put back as it was, which has WebKit look at its
# visibility once more (WebViewImpl.mm:2592-2604).
#
# The calls are WebKit's private API, so only the test fixtures make
# them; an app's windows never do. Call it on the main thread.
#
#   WebKitOcclusion.stage(WebKitOcclusion.ignore(ns_view))  #=> "occlusion-detection off 1"
module WebKitOcclusion
  # The private WKWebView setter and getter (WKWebViewPrivate.h:939).
  SETTER = "_setWindowOcclusionDetectionEnabled:"
  GETTER = "_windowOcclusionDetectionEnabled"

  # Has every WKWebView in the window of +ns_view+, an NSView's address,
  # ignore occlusion, and answers how many now do, by the getter; or,
  # when WebKit lacks the calls, a String that says so. wry puts a
  # window's webview inside a view of its own, and a window can hold
  # several, so it looks through the whole content view.
  def self.ignore(ns_view)
    load
    root = object(ns_view, "window")
    root = object(root, "contentView") unless root.null?
    webviews = root.null? ? [] : find(root)
    return "no webview in the window" if webviews.empty?

    [SETTER, GETTER].each do |selector|
      return "WKWebView does not respond to #{selector}" unless webviews.all? { |webview| responds?(webview, selector) }
    end
    webviews.each do |webview|
      hidden = @bool.call(webview, @sel.call("isHidden"))
      @set_flag.call(webview, @sel.call(SETTER), 0)
      @set_flag.call(webview, @sel.call("setHidden:"), 1)
      @set_flag.call(webview, @sel.call("setHidden:"), hidden)
    end
    webviews.count { |webview| @bool.call(webview, @sel.call(GETTER)).zero? }
  end

  # The PROGRESS stage for what ::ignore answered.
  def self.stage(answer)
    answer.is_a?(Integer) ? "occlusion-detection off #{answer}" : "occlusion-detection unavailable, #{answer}"
  end

  # +view+ and every view inside it that is a WKWebView.
  def self.find(view)
    found = @flag.call(view, @sel.call("isKindOfClass:"), @web_view).zero? ? [] : [view]
    subviews = object(view, "subviews")
    found + Array.new(@count.call(subviews, @sel.call("count"))) do |index|
      find(@at.call(subviews, @sel.call("objectAtIndex:"), index))
    end.flatten
  end

  def self.responds?(object, selector)
    !@flag.call(object, @sel.call("respondsToSelector:"), @sel.call(selector)).zero?
  end

  def self.object(receiver, selector)
    @get.call(receiver, @sel.call(selector))
  end

  # The runtime's functions, typed for each message sent: objc_msgSend
  # must be called with the method's own signature.
  def self.load
    return if @sel

    require "fiddle"
    objc = Fiddle.dlopen("/usr/lib/libobjc.A.dylib")
    Fiddle.dlopen("/System/Library/Frameworks/WebKit.framework/WebKit")
    send = objc["objc_msgSend"]
    @web_view = Fiddle::Function.new(objc["objc_getClass"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP).call("WKWebView")
    @get = Fiddle::Function.new(send, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
    @count = Fiddle::Function.new(send, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_LONG)
    @at = Fiddle::Function.new(send, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG], Fiddle::TYPE_VOIDP)
    @bool = Fiddle::Function.new(send, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_CHAR)
    @flag = Fiddle::Function.new(send, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_CHAR)
    @set_flag = Fiddle::Function.new(send, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_CHAR], Fiddle::TYPE_VOIDP)
    @sel = Fiddle::Function.new(objc["sel_registerName"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
  end
end
