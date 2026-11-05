<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Tokra's hidden real-window tests under load

2026-11-05. Read-only investigation; nothing in any repository was
changed, and no gate, real-window test, Docker, or tokratest job was run.

The failure being explained: at load average about 400, all 11
`IpcTransportTest` checks failed with "the app hung and was killed"
(`timed_out=true seconds=60.06 activated=false`), in
`scratchpad/bundle_commit2.log` lines 156-266, while the same code
passed an hour earlier.

## Summary

- The page was not hung. It was slow. Its stderr shows the
  "`__TAURI_INVOKE_KEY__ expected ... but received not-the-key`" line,
  which only the seventh of the page's nine checks causes. So at 60 s the
  page was about two-thirds done. RealApp's 60 s bound turned a slow run
  into a "hang".
- What starves is mainly WebKit's helper processes, not Ruby. WebKit
  takes a RunningBoard *Foreground* assertion for a page's WebContent,
  GPU, and Networking processes only while `isViewVisible()` is true. On
  macOS that requires the window's `occlusionState` to contain
  `NSWindowOcclusionStateVisible`. The hidden session never has that,
  because WindowServer does not draw a session that is off the console.
  So once the page has loaded, all three processes sit on a *Background*
  assertion, and Plan 057 observed priority 4 (darwinbg) for those
  processes. `backgroundThrottling: disabled` (`inactiveSchedulingPolicy
  = None`) only prevents *suspension*. It does not bring back the
  foreground assertion.
- The fix that targets this cause is test-only and belongs to Tokra.
  WebKit's own layout-test runner does the same thing: call the WKWebView
  SPI `_setWindowOcclusionDetectionEnabled:NO` on each fixture webview.
  `isViewVisible()` is then true for an ordered-in window even in a
  hidden session, so WebKit keeps the foreground assertion it keeps on
  the console. A second, independent change, also Tokra's, makes the
  60 s bound a real hang backstop: fail on *no progress* for a window of
  time, with a much larger hard ceiling for livelocks.
- Lota's hidden-session tooling needs no change for the fix. It is
  already as good as it can be here (`ProcessType Interactive`,
  `NSAppSleepDisabled`). It could optionally gain a load generator and a
  priority sampler for the proof runs.

## 1. The mechanism

### 1a. What WebKit does (cited source)

WebKit `main` at 827737a4d7cc (fetched 2026-11-05 into
`scratchpad/webkit/`). macOS 27.0.1 ships its own build, so the line
numbers are approximate for that build. The unified log, below, shows
that the shipped build behaves this way.

- `Source/WebKit/UIProcess/WebPageProxy.cpp:4053-4078`,
  `updateThrottleState()`, inside `#if USE(RUNNINGBOARD)`: WebKit takes
  the visible activity ("UIProcess is taking a foreground assertion
  because the view is visible") only if `isViewVisible()`, and drops it
  otherwise.
- `Source/WebKit/UIProcess/mac/PageClientImplMac.mm:208-230`,
  `PageClientImpl::isViewVisible`: the view is not visible if
  `!viewWindow.isVisible`, or if `windowIsOccluded()`, which is
  `windowOcclusionDetectionEnabled() && (occlusionState &
  NSWindowOcclusionStateVisible) != NSWindowOcclusionStateVisible`
  (line 211).
- `Source/WebKit/UIProcess/ProcessThrottler.cpp:282-293`: throttle
  states map to assertion types (Foreground to `Foreground`, Background
  to `Background`, Suspended to `NearSuspended`).
- `Source/WebKit/UIProcess/Cocoa/ProcessAssertionCocoa.mm:338-382`: on
  macOS, `Background` is the RunningBoard assertion "IndefiniteBackground",
  `NearSuspended` is "Suspended" ("runs at the idle jetsam band"), and
  `Foreground` is "Foreground", all in the `com.apple.webkit` domain.
- `Source/WebKit/UIProcess/API/Cocoa/WKPreferences.mm:182-203`:
  `inactiveSchedulingPolicy = None`, which is what wry 0.54.1 sets for
  `BackgroundThrottlingPolicy::Disabled` (`src/wkwebview/mod.rs:430-450`),
  sets only `shouldTakeNearSuspendedAssertions = true`,
  `backgroundWebContentRunningBoardThrottlingEnabled = false`, and
  `shouldDropNearSuspendedAssertionAfterDelay = false`. That keeps the
  process from being suspended or CPU-limited, but it never takes a
  foreground assertion. The SDK header
  (`WKPreferences.h:84-99`, CommandLineTools SDK) says the same: the
  policy concerns a web view "idle and detached from all windows".
- `Source/WTF/wtf/PlatformUse.h:331-333`: `USE_RUNNINGBOARD` is on for
  macOS only with Apple's internal SDK, that is, in the system WebKit
  that ships with macOS.

### 1b. What this Mac shows (unified log, read-only)

`log show --last 20m --predicate 'subsystem == "com.apple.WebKit" AND
(category == "ProcessSuspension" OR category == "ActivityState")'`
(saved at `scratchpad/wk_log.txt`) covers 39 Ruby fixture processes from
the running gate:

- `PageClientImpl ... isViewVisible(): ... window visible 1, view
  hidden 0, window occluded 1` appears 976 times, against 19 times with
  `window occluded 0`.
- For one such fixture (ruby 55296), its WebContent (55336), GPU (55335),
  and Networking (55337) processes all go to `Updating process assertion
  type to 3` (Foreground) only while transient foreground activities
  are held: "Process initialization", "Client navigation",
  `runJavaScriptInFrameInScriptWorld`. Each then drops to `type to 1`
  (Background, `foregroundActivities=0`), and the Networking and GPU
  processes go with it ("Networking for background view(s)", "GPU for
  background view(s)").

This confirms that the shipped WebKit uses RunningBoard assertions keyed
on occlusion here. I could not attribute each logged pid to a session
after the fact, so the log alone does not prove which lines came from
tokratest.

### 1c. From assertion to priority 4 (observed result, inferred mapping)

Plan 057's sampler saw the hung dialog fixture's WebContent at `pri 4`
in tokratest for 55-70 s, and at 46-47 on the console at the same load.
Priority 4 is darwinbg (`MAXPRI_THROTTLE`). That RunningBoard turns
WebKit's "IndefiniteBackground" or "Suspended" assertion into the
background role and darwinbg is **inference**: RunningBoard's domain
definitions are not on disk to read. It fits the observation exactly.

Why darwinbg is so much worse than "slower" (**inference from Apple's
published QoS guidance and XNU's Clutch scheduler; not verified on this
Mac**):

- On Apple Silicon, background-QoS work runs on the efficiency cores.
  This Mac has only 2 of them (`hw.perflevel1.logicalcpu = 2`, out of
  10).
- The background bucket is the last served under Clutch.
- Its I/O is throttled too.

At load 400 on 10 cores, a default-priority thread already gets about
1/40 of a core. A darwinbg WebContent competes for 2 E-cores with
everything else that has spilled onto them. Plan 057's own table shows
the asymmetry: at the same load the console run passed in 10-13 s, and
the hidden run hung at 60 s.

### 1d. Is the Ruby fixture process demoted too?

Not by WebKit, and not by App Nap. As far as I can tell, not by launchd
either:

- The runner is a LaunchAgent with `ProcessType Interactive`
  (hidden_session `install-runner:119-120`). `launchd.plist(5)` says an
  unspecified type gets "light resource limits ... throttling its CPU
  usage and I/O bandwidth", and Interactive gets none.
- The runner sets `NSAppSleepDisabled` for the account
  (`install-runner:132`).
- Jobs start through `env -i ... perl exec` with no `nice`
  (`hidden-runner:127-132`). Children inherit this.

So Ruby runs at default priority and gets its fair share, about 1/40 of
a core at load 400, on the console and hidden alike. That costs real
time, but in Plan 057's evidence it was not the difference: the console
runs at the same load passed. **Not verified:** I did not sample a
tokratest Ruby fixture's `pri` during a job, because none was running and
starting one was not allowed.

### 1e. Which settings do not explain it

- `activated=false` only says the fixture never came to the front, as
  intended.
- `keep_in_sight` (always on top, ignore cursor) cannot help hidden.
  Nothing in that session is ever "visible" to macOS (hidden_session
  `SETUP.txt`, "What the hidden desktop cannot do: be seen", and
  `occlusion-probe.js`: `visible_to_system:false` at every window level).
- App Nap is already off.

### 1f. A diagnostic gap

`ipc_transport/app.rb` does not set `$stdout.sync = true`, and its
`EVENT ready` line goes through a block-buffered pipe. The SIGKILL
therefore threw it away: the run shows an empty `--- stdout`. Ten other
fixtures set `sync` themselves, and this one and others do not.

## 2. Is 60 s a backstop or a pass condition?

At load it is a pass condition.

`RealApp::TIMEOUT` says "A healthy launch takes one to two [seconds]".
The bound is therefore at most about 30-60x the healthy time. That is
roughly the slowdown that fair share alone imposes at load 400 on 10
cores, before darwinbg is added. This run proves the point: the page was
in check 7 of 9 when it was killed. The page also carries its own
wall-clock limits that turn slowness into failure:

- `harness.js:31`, 20 s per check;
- `ipc_transport/index.html:123` and `:168`, 5 s waits for an expected
  console error and for the channel's four messages;
- `event`, `menu_plugin`, `tray_plugin`, and `global-shortcut` fixtures,
  5-15 s `withTimeout`s;
- `dialog_test.rb:105`, 5 s;
- `restart_test.rb:122`, `PATIENCE`.

### A progress-based backstop

The aim is to fail when the fixture stops making progress, not when it
is slow. It must be *semantic* progress: a line produced by the thing
under test moving forward. A free-running Ruby thread or a page
`setInterval` that just beats would hide real hangs: an `await` that
never settles with the timer still ticking, or a blocked event loop with
a Ruby thread still printing. CPU time is a poor signal for the same
reason, and it also cannot see the WebContent process, which is an XPC
service under launchd, outside the fixture's process group.

The sketch, against `test/integration/support/real_app.rb`:

```ruby
STALL   = 90       # seconds with no new line from the fixture: a hang
CEILING = 15 * 60  # a run that never ends though it keeps printing: a livelock
POLL    = 1

# in launch:
last = now                                   # also counts the launch itself
out_thread = Thread.new do
  out_reader.each_line do |line|
    last = now
    stdout << line
    signalled_at = now if on_line&.call(line, pid)
  end
end
err_thread = Thread.new { err_reader.each_line { |line| last = now; stderr << line } }

waiter = Process.detach(pid)
watcher = watch_front(pid, waiter)
verdict = nil
until waiter.join(POLL)
  verdict = :stalled if now - last > STALL
  verdict = :ceiling if now - started > CEILING
  break if verdict
end
if verdict
  probe = HangProbe.call(pid)
  kill_group(pid)
  waiter.join(DRAIN)
end
# Run gains stalled_for: (now - last) and last_line:, and describe says
# "no progress for 90 s after <last line>" or "still running after 15 min".
```

`timed_out` can stay as `!verdict.nil?`, so `assert_finished` keeps its
message, and `describe` names which bound tripped. Pass `STALL` and
`CEILING` as keyword arguments to `launch`, so a test of RealApp itself
can use bounds of a few seconds.

To make "a new line" mean "the system under test advanced", add these
progress lines, all of them semantic:

1. `fixture_app.rb`: set `$stdout.sync = true` once, for every fixture,
   and print `PROGRESS loaded` at the end of the file. That is the first
   line once Ruby, Tokra, and the native extension have loaded, so a slow
   boot shows. `WholeLines` already makes each `puts` a single `write`,
   so `sync` is all that is missing.
2. `harness.js`: in `check()`, POST `/progress` with
   `{stage: "start"|"end", name}` around each check. `Site` prints
   `PROGRESS check-start <name> <s>` and `PROGRESS check-end <name> <s>`.
   A line therefore means the page's JS ran, the `tokra://` custom
   protocol carried a request through the main-thread event loop, and
   Ruby's Rack app answered. That is the whole chain a hang could
   stop. Long checks (the 1 MB channel, the dialog fixture's polling) can
   post an intermediate `step` line.
3. Raise or remove the page's own wall-clock waits, so that they no
   longer race starvation:
   - `withTimeout` in `check()` takes its bound from `/options.json`
     (Ruby passes `STALL`), so a never-settling promise still fails *a
     check*, with its name, at about the time RealApp would kill.
   - Positive waits ("wait up to 5 s for X to happen", as at
     `ipc_transport/index.html:123` and `:168`) become waits for the
     event itself, bounded only by the check's timeout.
   - Negative waits ("wait 1 s and show X did *not* happen",
     `index.html:150`) cannot fail falsely under load. They can only pass
     more easily, so they stay as they are.

Does this hide real hangs? No:

- A deadlock or a never-answered IPC stops all lines and fails within
  `STALL`, about the same time as today's 60 s from launch, with a better
  message (the last check started).
- A livelock that keeps printing is caught by `CEILING`, and by the
  check's own timeout if it is inside one check.
- What it gives up is failing a *slow but progressing* run, which is the
  false failure the maintainer asked to remove.

It is not a complete answer to load on its own. A darwinbg page
can go more than 90 s between two lines at load 900 (Plan 057 saw a 54 s
gap in the dialog fixture), and raising `STALL` without bound weakens the
hang detection. That is why it pairs with removing the demotion
(section 3).

Tests for it, following Freeman and Pryce: RealApp with
`STALL: 2, CEILING: 6` against throwaway fixtures under `test/`:

- one that prints a line every second for 4 s and exits 0 must pass,
  though it outlives `STALL`;
- one that prints once and blocks forever must fail as stalled in
  about 2 s, naming its last line;
- one that prints forever must fail at the ceiling.

Deleting the `last = now` update must fail the first test. Deleting the
stall check must fail the second.

## 3. Ways to keep the page from being demoted

| # | Lever | Works in a non-console session? | Owner | Risk |
|---|---|---|---|---|
| A | `-[WKWebView _setWindowOcclusionDetectionEnabled:NO]` on each fixture webview, then `setHidden:YES`/`NO` (or post `NSWindowDidChangeOcclusionStateNotification`) so WebKit re-evaluates | **Yes, by the code.** `isViewVisible()` then needs only `window.isVisible` and a view that is not hidden, which the log shows are both true hidden (`window visible 1, view hidden 0`). The setter only stores a flag (`WebViewImpl.h:395`), hence the nudge: `viewDidHide`/`viewDidUnhide` and `windowDidChangeOcclusionState` each call `activityStateDidChange(IsVisible)` (`WebViewImpl.mm:2394-2398, 2592-2604`). | Tokra, test-only (`test/integration/support/fixture_app.rb`, inside `keep_in_sight`, which every fixture window already passes through, plus the three plugin fixtures that use FixtureApp) | Private SPI, declared in `WKWebViewPrivate.h:939` and used by WebKit's own test runner (`Tools/WebKitTestRunner/mac/PlatformWebViewMac.mm:103`) for this exact reason. Guard with `respondsToSelector:` and print `PROGRESS occlusion-detection unavailable` if it is missing, so a future macOS fails loudly, not mysteriously. No library code changes, so no Tauri-fidelity issue: Tauri has no such API, and app users never see it. Reach the webview through `window.window_handle` (`AppKitWindowHandle#ns_view`) and Fiddle `objc_msgSend`, as `window_handle/app.rb:100-127` already does. Walk `[[ns_view window] contentView]` recursively for `isKindOfClass: WKWebView`, because wry may add a child webview. Run it on the main thread (`Ready`, or right after `build`), and again for webviews added to a window later. No current fixture checks `visibilityState`, `visibilitychange`, or rAF (searched), so no assertion changes meaning. |
| B | Progress-based backstop (section 2) | Yes; it is independent of the session | Tokra (`real_app.rb`, `fixture_app.rb`, `harness.js`) | Low. It moves the hang verdict from "60 s since launch" to "90 s since last progress, 15 min total". |
| C | Raise the fixture's own QoS: `pthread_set_qos_class_self_np(QOS_CLASS_USER_INITIATED)` on the main thread through Fiddle, or `NSProcessInfo beginActivityWithOptions: NSActivityUserInitiated \| NSActivityLatencyCritical` | Yes, any process may do it for itself without privileges. But it **does not touch WebContent**, whose priority RunningBoard sets from WebKit's assertions, not from its client's QoS (inference from 1a). | Tokra, test-only | Low. Optional, helps only the Ruby half. `beginActivity` overlaps App Nap, which is already off. Whether threads created afterwards inherit the QoS is **unverified**. |
| D | WKPreferences: `inactiveSchedulingPolicy` (already None), `_pageVisibilityBasedProcessSuppressionEnabled = NO`, `_hiddenPageDOMTimerThrottlingEnabled = NO` | Do not restore the foreground assertion (`WebPageProxy.cpp:4053-4078` keys only on `isViewVisible`). They only stop suspension and timer throttling, which `backgroundThrottling` already covers. | — | Ineffective for this cause. Changing them in Tokra's library for users would also break Tauri fidelity. |
| E | `taskpolicy`/`nice` on the hidden job | `taskpolicy` can only clamp down (`-c utility/background`, `-b`), and `nice` below 0 needs root. WebContent is launched by launchd through xpcproxy, not as a child of the job, so nothing inherits into it anyway. | Lota | Ineffective. |
| F | `taskpolicy -B -p <WebContent pid>` (clear PRIO_DARWIN_BG) from a sampler in tokratest | Possibly for the same uid, but RunningBoard reapplies the role on every assertion change, about every IPC burst according to the log. The sampler would race the system. | Lota or Tokra | Fragile and unsupported. Not recommended. |
| G | LaunchServices/RunningBoard attributes on the fixture launch (`open -a`, `LSUIElement`, `LSBackgroundOnly`, `ProcessType`) | Change how the *host* app is classified, not WebKit's per-WebContent assertions. In a session WindowServer does not draw, the windows stay occluded whatever the host is. | — | Ineffective for the page (inference). |
| H | Make the hidden session's windows count as seen | Not possible. WindowServer does not draw an off-console session (`SETUP.txt`). | Lota | n/a |

## 4. Recommendation

The smallest set, all in Tokra and all under `test/`:

1. **Lever A**: a `FixtureApp` helper that turns off WebKit's occlusion
   detection on every webview of each fixture window, called from
   `keep_in_sight` (already called for every fixture window, including
   `webview_rows`, `web_context`, `config_windows`, `multiwindow_routing`)
   and from the dialog, notification, and global-shortcut plugin
   fixtures. Its RDoc says why, citing `PageClientImplMac.mm:208-230` and
   WebKitTestRunner. This removes the cause: the page keeps the
   foreground assertion that WebKit gives it on the console.
2. **Lever B**: the progress-based backstop in `RealApp.launch`, with
   `$stdout.sync = true` and `PROGRESS loaded` in `fixture_app.rb`,
   check-start and check-end progress posts in `harness.js`, the
   per-check timeout taken from Ruby, and the positive 5 s waits in
   `ipc_transport/index.html` turned into event waits. This makes the
   remaining fair-share slowdown (about 40x at load 400 for
   default-priority work) a matter of time, not of failure, and keeps
   real hangs failing within `STALL`.
3. If A proves itself, update Plan 057: the console set
   (`plugins/dialog/test/test_dialog_window.rb`) can return to the hidden
   job, since its only evidence was the darwinbg page. Its
   `RealWindows::CONSOLE` comment and AGENTS.md's sentence ("Off the
   console macOS lowers WebKit's page process to background priority...")
   then describe a cause the fixtures work around. A file joins the list
   again only with new evidence. Amend Plan 056/057 and AGENTS.md
   together.

Optional, and only with evidence that the Ruby half still limits the run
after 1 and 2: lever C in `fixture_app.rb`.

**The hidden_session project:** nothing is required for the fix.
Useful for the proof, and generally:

- a `hidden-load N SECONDS` helper, or a documented recipe, that starts
  N default-QoS spinners in a test account and stops them, so every
  project measures with the same load;
- a priority sampler beside `window-sampler.js`: `ps -U ACCOUNT -o
  pid,pri,comm` once a second, filtered to `com.apple.WebKit.*`;
- a paragraph in `SETUP.txt`'s "What the hidden desktop cannot do": on
  an unseen desktop WebKit drops each page's processes to the
  background, and test fixtures that need a live page can turn off
  `WKWebView`'s occlusion detection (`_setWindowOcclusionDetectionEnabled:`),
  as WebKitTestRunner does.

### How to prove it (later, when the gate and tokratest are free)

1. **Mechanism first, in tokratest.** Run `ipc_transport` and the dialog
   fixture once each, through `hidden-run`, with a 1 Hz `ps -o pri`
   sampler of tokratest's `com.apple.WebKit.WebContent`, with and without
   lever A (A/B with a temporary environment switch in the experiment
   only, not committed). Expected: the WebContent spends the run at 4
   without A, and at about 46-47 with A, as on the console. Also check
   the unified log for `window occluded 0` lines and
   `Updating process assertion type to 3` held for the run. If WebContent
   still drops to 4 with a foreground assertion, then RunningBoard
   demotes off-console sessions regardless, lever A is not enough, and
   the console set stays.
2. **Load.** Generate about load 400 the way it happened: 400 spinners
   (`yes > /dev/null`) at default QoS in a second `hidden-run` job, or in
   the maintainer's account, which is the same scheduler. Add one cold
   `cargo build -j 20` for I/O. Confirm with `uptime` before and during
   the runs. Plan 057's 12 `yes` processes are far too few for 400.
3. **Repetitions.** With the load held, run `bundle exec rake
   test:real_windows` 20 times hidden with A and B. Run the dialog
   window test 20 times hidden. Run the same 20 without A (B only), to
   show A is causal and B alone is not enough at this load. The pass
   criterion is 20 of 20 with A and B. With 0 failures in 20, the 95%
   upper bound on the flake rate is about 14%, so run 60 if the
   maintainer wants under 5%.
4. **The backstop still catches hangs.** Use the RealApp unit tests
   above. Also run a mutation in a scratch copy: make `ipc_transport`'s
   `ping` handler `sleep` forever on the main thread. The run must fail
   as stalled about `STALL` seconds after the line `PROGRESS check-start
   invoke resolves`, with and without load.

## What I could not verify

- That macOS 27.0.1's shipped WebKit matches `main` line for line. The
  log confirms the throttler, its assertion types, and the occlusion
  check, but I did not confirm that the SPI exists on this build. The
  helper must check `respondsToSelector:`.
- That a `com.apple.webkit` Foreground assertion gives priority 46-47
  in a *non-console* session. RunningBoard could also consider the
  session. This is the one assumption step 1 of the proof decides.
- The RunningBoard mapping from assertion to darwinbg, and the claims
  about the Clutch scheduler and E-cores. These rest on Plan 057's
  observed priority 4 and on Apple's QoS guidance and XNU from memory,
  not on files on this Mac.
- The tokratest Ruby fixture's own priority during a job. None was
  running, and starting one was not allowed.
- Which session each logged pid in `scratchpad/wk_log.txt` belonged to.
- Whether pthreads created after `pthread_set_qos_class_self_np` inherit
  the QoS (lever C).
