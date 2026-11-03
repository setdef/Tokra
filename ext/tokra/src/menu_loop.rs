// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Hands the GVL to other Ruby threads while a Windows menu tracks
//! (plan 053).
//!
//! A menu's modal loop runs on the main thread until the menu closes:
//! tray-icon's `TrackPopupMenu`, inside its own window procedure
//! (tray-icon 0.21.0 `platform_impl/windows/mod.rs:459-464`, `509-523`),
//! and the menu bar's and the system menu's, inside `DefWindowProc`. tao's
//! pump dispatches those window procedures outside its event handler, while
//! the main thread holds the GVL (ADR 012). Windows CI showed every other
//! Ruby thread frozen there (plan 051, run 41617252499), although tao's own
//! path to `MainEventsCleared` looks open in the source (plan 053, "What is
//! confirmed and what is guessed").
//!
//! So a thread-level `WH_MSGFILTER` hook hears each message the menu loop
//! peeks, which it passes to `CallMsgFilter(&msg, MSGF_MENU)` before acting
//! on it (Wine `dlls/win32u/menu.c:4169-4173`, `ReactOS`
//! `win32ss/user/ntuser/menu.c:4111-4115`). The poll ticker marks a
//! hand-off owed and posts a message every 10 ms (`gvl_handoff::poll_tick`),
//! so the hook hears one each tick, and the interrupt ticker posts one
//! every 100 ms (`interrupt_check.rs`). [`hand_over`] decides what the
//! hook does with it: `Thread.pass`, but only when a hand-off is owed or
//! Ruby has an interrupt pending, this thread holds the GVL, and the hook
//! is not already inside its own hand-off; and `EndMenu` once a hand-off
//! raised. The context menu runs inside `without_gvl`, so there the hook
//! passes nothing.

use std::cell::Cell;

use crate::gvl_handoff::Pending;

/// Resets the busy flag however the hand-off ends.
struct Busy<'a>(&'a Cell<bool>);

impl Drop for Busy<'_> {
    fn drop(&mut self) {
        self.0.set(false);
    }
}

/// What the hook did with one menu message.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MenuTurn {
    /// Nothing: no hand-off was owed or possible.
    Skipped,
    /// It handed the GVL over.
    Passed,
    /// An exception waits for the loop, so the menu must end: the hook
    /// calls `EndMenu`, and passes no more, until `MainEventsCleared`
    /// takes the exception.
    Ending,
}

/// Whether `raised` holds an exception, leaving it there.
fn holds<E>(raised: &Cell<Option<E>>) -> bool {
    let error = raised.take();
    let held = error.is_some();
    raised.set(error);
    held
}

/// What the hook does with one menu message.
///
/// Inside its own `pass` (`busy`) it does nothing. While an exception
/// waits in `raised` it answers [`MenuTurn::Ending`], so the menu ends and
/// the loop reaches `MainEventsCleared`, which takes it and ends, as plan
/// 053's decision 1 says; a menu that kept tracking would hold the
/// exception, and the loop, until someone dismissed it. Otherwise, when
/// this thread holds the GVL (`has_gvl`), it calls `pass` if a hand-off is
/// owed (`pending`, which it clears) or Ruby has an interrupt pending
/// (`interrupted`), as `MainEventsCleared` hands over for either. A
/// hand-off that cannot be made stays owed. An error `pass` returns, which
/// is an interrupt's exception, goes into `raised`.
pub fn hand_over<E>(
    pending: &Pending,
    busy: &Cell<bool>,
    raised: &Cell<Option<E>>,
    has_gvl: impl FnOnce() -> bool,
    interrupted: impl FnOnce() -> bool,
    pass: impl FnOnce() -> Result<(), E>,
) -> MenuTurn {
    if busy.get() {
        return MenuTurn::Skipped;
    }
    if holds(raised) {
        return MenuTurn::Ending;
    }
    if !has_gvl() {
        return MenuTurn::Skipped;
    }
    let owed = pending.take();
    if !owed && !interrupted() {
        return MenuTurn::Skipped;
    }
    busy.set(true);
    let _reset = Busy(busy);
    match pass() {
        Ok(()) => MenuTurn::Passed,
        Err(error) => {
            raised.set(Some(error));
            MenuTurn::Ending
        }
    }
}

#[cfg(windows)]
pub use hook::{end_menu, MenuLoopHook};

/// The hook itself, which exists only on Windows.
#[cfg(windows)]
mod hook {
    use std::cell::{Cell, RefCell};
    use std::marker::PhantomData;
    use std::panic;
    use std::ptr;
    use std::sync::Arc;

    use magnus::{prelude::*, Error, Ruby, Value};
    use windows::Win32::Foundation::{LPARAM, LRESULT, WPARAM};
    use windows::Win32::System::Threading::GetCurrentThreadId;
    use windows::Win32::UI::WindowsAndMessaging::{
        CallNextHookEx, EndMenu, SetWindowsHookExW, UnhookWindowsHookEx, HHOOK, MSGF_MENU,
        WH_MSGFILTER,
    };

    use super::{hand_over, MenuTurn};
    use crate::gvl_handoff::{Pending, COUNTS};

    /// What the hook reads on the loop's thread while it is installed.
    struct State {
        /// Set by the poll ticker each tick, cleared by a hand-off.
        pending: Arc<Pending>,
        /// Set while the hook's own `Thread.pass` runs.
        busy: Cell<bool>,
        /// The cell in `EventLoop#run`'s frame that takes an exception
        /// `Thread.pass` raised. [`MenuLoopHook`] borrows it for as long
        /// as this pointer is here.
        raised: *const Cell<Option<Error>>,
        /// The Ruby calls the hook makes.
        ruby: RubyCalls,
    }

    /// The three Ruby calls the hook makes, which a test replaces.
    #[derive(Clone, Copy)]
    struct RubyCalls {
        /// Whether this thread holds the GVL.
        has_gvl: fn() -> bool,
        /// Whether Ruby has an interrupt pending for the main thread.
        interrupted: fn() -> bool,
        /// Hands the GVL over.
        pass: fn() -> Result<(), Error>,
    }

    /// The calls into Ruby itself.
    const RUBY: RubyCalls = RubyCalls {
        has_gvl: ruby_has_gvl,
        interrupted: ruby_interrupted,
        pass: ruby_pass,
    };

    thread_local! {
        /// The hook's state on the thread it watches, or `None` while no
        /// hook is installed there.
        static STATE: RefCell<Option<State>> = const { RefCell::new(None) };
    }

    /// An installed hook. Dropping it removes the hook and its state.
    pub struct MenuLoopHook<'a> {
        hook: HHOOK,
        /// The borrow of the cell [`State::raised`] points to.
        raised: PhantomData<&'a Cell<Option<Error>>>,
    }

    impl<'a> MenuLoopHook<'a> {
        /// Installs the hook on this thread, which must be the loop's
        /// and hold the GVL. `pending` is the poll ticker's mark, and
        /// `raised` takes an exception a hand-off raised. Answers `None`
        /// if a hook is already installed on this thread or Windows
        /// refuses one; the loop then runs as it did before plan 053.
        pub fn install(pending: Arc<Pending>, raised: &'a Cell<Option<Error>>) -> Option<Self> {
            Self::install_with(pending, raised, RUBY)
        }

        /// [`install`](Self::install) with the Ruby calls given, so a
        /// test can run a real menu without Ruby.
        fn install_with(
            pending: Arc<Pending>,
            raised: &'a Cell<Option<Error>>,
            ruby: RubyCalls,
        ) -> Option<Self> {
            let state = State {
                pending,
                busy: Cell::new(false),
                raised: ptr::from_ref(raised),
                ruby,
            };
            let placed = STATE
                .try_with(|cell| match cell.try_borrow_mut() {
                    Ok(mut slot) if slot.is_none() => {
                        *slot = Some(state);
                        true
                    }
                    _ => false,
                })
                .unwrap_or(false);
            if !placed {
                return None;
            }
            // SAFETY: `msg_filter` has `HOOKPROC`'s signature
            // (windows 0.61.3 `Win32/UI/WindowsAndMessaging/mod.rs:4011`).
            // A thread hook needs no module handle, and the thread id is
            // this thread's own, so Windows calls `msg_filter` only on this
            // thread (`SetWindowsHookExW`, `dwThreadId`). The state it reads
            // is in place above.
            #[allow(unsafe_code)]
            let hook = unsafe {
                SetWindowsHookExW(WH_MSGFILTER, Some(msg_filter), None, GetCurrentThreadId())
            };
            hook.map_or_else(
                |_| {
                    clear();
                    None
                },
                |hook| {
                    Some(Self {
                        hook,
                        raised: PhantomData,
                    })
                },
            )
        }
    }

    impl Drop for MenuLoopHook<'_> {
        fn drop(&mut self) {
            // SAFETY: `hook` is the handle `SetWindowsHookExW` returned
            // and nothing has removed it. It runs on the thread the hook
            // watches, where `EventLoop#run` made the guard, so no call of
            // `msg_filter` is in progress elsewhere, and after it returns
            // Windows calls it no more.
            #[allow(unsafe_code)]
            let _ = unsafe { UnhookWindowsHookEx(self.hook) };
            clear();
        }
    }

    /// Empties this thread's state, unless the hook is reading it, which
    /// it never is once the hook is gone.
    fn clear() {
        let _ = STATE.try_with(|cell| {
            if let Ok(mut slot) = cell.try_borrow_mut() {
                *slot = None;
            }
        });
    }

    /// The hook. It looks only at a menu's messages and always passes
    /// each one on, claiming none, so the menu loop goes on as before.
    #[allow(unsafe_code)]
    unsafe extern "system" fn msg_filter(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
        if u32::try_from(code) == Ok(MSGF_MENU) {
            // A panic must not unwind into user32's frames.
            let _ = panic::catch_unwind(on_menu_message);
        }
        // SAFETY: Windows passes the hook these three arguments to hand
        // on; the first argument is ignored (`CallNextHookEx`).
        unsafe { CallNextHookEx(None, code, wparam, lparam) }
    }

    /// One message of a menu's modal loop.
    fn on_menu_message() {
        COUNTS.menu_message();
        let _ = STATE.try_with(|cell| {
            let Ok(slot) = cell.try_borrow() else {
                return;
            };
            let Some(state) = slot.as_ref() else {
                return;
            };
            // SAFETY: `raised` came from the `&'a Cell` that the
            // installed `MenuLoopHook<'a>` still borrows: its `Drop`
            // removes the hook and then this state, before the cell's
            // frame ends, and the hook runs only on this thread while it
            // is installed. A `Cell` is only ever shared, never borrowed
            // mutably.
            #[allow(unsafe_code)]
            let raised = unsafe { &*state.raised };
            let ruby = state.ruby;
            let turn = hand_over(
                &state.pending,
                &state.busy,
                raised,
                ruby.has_gvl,
                ruby.interrupted,
                || crate::event_loop_target::outside_callbacks(ruby.pass),
            );
            match turn {
                MenuTurn::Skipped => {}
                MenuTurn::Passed => COUNTS.menu_handoff(),
                MenuTurn::Ending => end_menu(),
            }
        });
    }

    /// Ends this thread's active menu, if any, so that a loop an exception
    /// must end gets back to `MainEventsCleared` instead of waiting for
    /// someone to dismiss the menu (plan 053, decision 1).
    pub fn end_menu() {
        // SAFETY: `EndMenu` takes no arguments and ends the calling
        // thread's active menu (Microsoft's `EndMenu` reference: "Ends the
        // calling thread's active menu"), so it touches only this thread's
        // menu, from this thread; with none active it does nothing.
        #[allow(unsafe_code)]
        let _ = unsafe { EndMenu() };
    }

    /// Whether this thread holds the GVL: a Ruby thread outside a blocking
    /// region (Ruby v4.0.9 `thread.c:2103-2113`).
    fn ruby_has_gvl() -> bool {
        // SAFETY: `ruby_thread_has_gvl_p` is public
        // (`include/ruby/thread.h:336-341`) and only reads this thread's
        // Ruby thread, if it has one; it may be called without the GVL.
        #[allow(unsafe_code)]
        let held = unsafe { rb_sys::ruby_thread_has_gvl_p() };
        held != 0
    }

    /// Whether Ruby has an interrupt pending for the main thread, as
    /// `MainEventsCleared` asks (`event_loop::interrupt_pending`). Called
    /// only with the GVL held.
    fn ruby_interrupted() -> bool {
        Ruby::get().is_ok_and(|ruby| crate::event_loop::interrupt_pending(&ruby))
    }

    /// `Thread.pass`, through magnus's protected `funcall`, so an
    /// interrupt's exception comes back as an `Err` instead of unwinding
    /// through the menu loop. Called only with the GVL held.
    fn ruby_pass() -> Result<(), Error> {
        let Ok(ruby) = Ruby::get() else {
            return Ok(());
        };
        ruby.class_thread()
            .funcall::<_, _, Value>("pass", ())
            .map(|_| ())
    }

    #[cfg(test)]
    mod tests {
        use std::cell::Cell;
        use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
        use std::sync::Arc;
        use std::thread;
        use std::time::Duration;

        use magnus::Error;
        use windows::core::w;
        use windows::Win32::Foundation::{GetLastError, HWND, LPARAM, LRESULT, WPARAM};
        use windows::Win32::System::LibraryLoader::GetModuleHandleW;
        use windows::Win32::System::Threading::GetCurrentThreadId;
        use windows::Win32::UI::WindowsAndMessaging::{
            AppendMenuW, CallNextHookEx, CreatePopupMenu, CreateWindowExW, DefWindowProcW,
            DestroyMenu, DestroyWindow, PostMessageW, RegisterClassW, SendMessageTimeoutW,
            SetWindowsHookExW, TrackPopupMenu, UnhookWindowsHookEx, MF_STRING, MSG, MSGF_MENU,
            SMTO_ABORTIFHUNG, TPM_LEFTALIGN, WH_MSGFILTER, WINDOW_EX_STYLE, WM_APP, WM_CANCELMODE,
            WNDCLASSW, WS_OVERLAPPED,
        };

        use super::{MenuLoopHook, RubyCalls};
        use crate::gvl_handoff::Pending;

        /// The message the poster thread posts, as the poll ticker posts
        /// its wake-up.
        const POSTED: u32 = WM_APP + 1;

        /// The stub `pass`'s calls.
        static PASSES: AtomicUsize = AtomicUsize::new(0);

        /// The posted messages a second filter heard under `MSGF_MENU`.
        static POSTED_HEARD: AtomicUsize = AtomicUsize::new(0);

        /// Set once `TrackPopupMenu` has returned.
        static ENDED: AtomicBool = AtomicBool::new(false);

        /// How many posted messages the menu loop must show the filters
        /// before the poster ends the menu.
        const WANTED: usize = 3;

        /// How many messages the poster sends before it gives up and ends
        /// the menu anyway, so a filter that never hears one fails the test
        /// instead of hanging it.
        const MAX_POSTS: usize = 1000;

        #[allow(unsafe_code)]
        unsafe extern "system" fn owner_proc(
            hwnd: HWND,
            msg: u32,
            wparam: WPARAM,
            lparam: LPARAM,
        ) -> LRESULT {
            // SAFETY: Windows calls a window procedure with its own
            // window's message, which `DefWindowProcW` takes as is.
            unsafe { DefWindowProcW(hwnd, msg, wparam, lparam) }
        }

        /// A second filter, which counts only the posted messages a menu
        /// loop shows it, so the test knows those, and not some other menu
        /// message, reach a `WH_MSGFILTER` hook.
        #[allow(unsafe_code)]
        unsafe extern "system" fn count_posted(
            code: i32,
            wparam: WPARAM,
            lparam: LPARAM,
        ) -> LRESULT {
            if u32::try_from(code) == Ok(MSGF_MENU) {
                // SAFETY: for a `WH_MSGFILTER` hook `lparam` points to the
                // `MSG` the menu loop is about to process (`MessageProc`).
                let message = unsafe { (*(lparam.0 as *const MSG)).message };
                if message == POSTED {
                    POSTED_HEARD.fetch_add(1, Ordering::SeqCst);
                }
            }
            // SAFETY: the hook's own arguments, handed on.
            unsafe { CallNextHookEx(None, code, wparam, lparam) }
        }

        // A real menu loop, with the hook installed and its Ruby calls
        // stubbed: another thread does what the poll ticker does, marking
        // a hand-off owed and posting a message, and the menu loop must
        // show those posted messages, which are not input, to a filter,
        // and the hook must hand over for them.
        #[test]
        #[allow(unsafe_code)]
        fn a_menus_modal_loop_shows_the_hook_the_messages_another_thread_posts() {
            let pending = Arc::new(Pending::default());
            let raised: Cell<Option<Error>> = Cell::new(None);
            let stub = RubyCalls {
                has_gvl: || true,
                interrupted: || false,
                pass: || {
                    PASSES.fetch_add(1, Ordering::SeqCst);
                    Ok(())
                },
            };
            let hook = MenuLoopHook::install_with(Arc::clone(&pending), &raised, stub)
                .expect("Windows installs a thread hook");
            // SAFETY: `count_posted` has `HOOKPROC`'s signature, and the
            // hook watches this thread only; it is removed below.
            let counter = unsafe {
                SetWindowsHookExW(WH_MSGFILTER, Some(count_posted), None, GetCurrentThreadId())
            }
            .expect("a second thread hook");

            // SAFETY: a window class and a window of this test's own, made
            // and destroyed on this thread, and a popup menu with one item;
            // each handle is checked before use.
            let (hwnd, menu) = unsafe {
                let instance = GetModuleHandleW(None).expect("this module's handle");
                let class = WNDCLASSW {
                    lpfnWndProc: Some(owner_proc),
                    hInstance: instance.into(),
                    lpszClassName: w!("TokraMenuLoopHookTest"),
                    ..Default::default()
                };
                RegisterClassW(&raw const class);
                let hwnd = CreateWindowExW(
                    WINDOW_EX_STYLE::default(),
                    w!("TokraMenuLoopHookTest"),
                    w!(""),
                    WS_OVERLAPPED,
                    0,
                    0,
                    0,
                    0,
                    None,
                    None,
                    Some(instance.into()),
                    None,
                )
                .expect("the owner window");
                let menu = CreatePopupMenu().expect("a popup menu");
                AppendMenuW(menu, MF_STRING, 1, w!("Item")).expect("its item");
                (hwnd, menu)
            };

            let target = hwnd.0 as isize;
            let ticker_pending = Arc::clone(&pending);
            let poster = thread::spawn(move || {
                let hwnd = HWND(target as _);
                let mut posts = 0;
                while POSTED_HEARD.load(Ordering::SeqCst) < WANTED
                    && !ENDED.load(Ordering::SeqCst)
                    && posts < MAX_POSTS
                {
                    ticker_pending.request();
                    // SAFETY: posting to a window of the test's thread is
                    // allowed from any thread; a failed post only skips a
                    // tick.
                    let _ = unsafe { PostMessageW(Some(hwnd), POSTED, WPARAM(0), LPARAM(0)) };
                    posts += 1;
                    thread::sleep(Duration::from_millis(1));
                }
                if !ENDED.load(Ordering::SeqCst) {
                    // SAFETY: a sent WM_CANCELMODE is handled inside the
                    // menu loop's next peek, and DefWindowProc ends the
                    // menu on it; the timeout bounds the wait if the menu
                    // ended meanwhile.
                    unsafe {
                        SendMessageTimeoutW(
                            hwnd,
                            WM_CANCELMODE,
                            WPARAM(0),
                            LPARAM(0),
                            SMTO_ABORTIFHUNG,
                            2000,
                            None,
                        );
                    }
                }
                posts
            });

            // SAFETY: `menu` and `hwnd` are this thread's and alive; the
            // call returns once the poster ends the menu, or at once if
            // Windows cannot show it.
            let shown = unsafe { TrackPopupMenu(menu, TPM_LEFTALIGN, 0, 0, None, hwnd, None) };
            // SAFETY: reads this thread's last error, right after the call.
            let error = unsafe { GetLastError() };
            ENDED.store(true, Ordering::SeqCst);
            let posts = poster.join().expect("the poster thread");
            drop(hook);
            // SAFETY: the counter is the handle `SetWindowsHookExW` gave,
            // removed once; the menu has closed and both handles are this
            // thread's.
            unsafe {
                let _ = UnhookWindowsHookEx(counter);
                let _ = DestroyMenu(menu);
                let _ = DestroyWindow(hwnd);
            }

            assert!(
                shown.as_bool(),
                "TrackPopupMenu could not show the menu: {error:?}"
            );
            assert!(
                POSTED_HEARD.load(Ordering::SeqCst) >= WANTED,
                "a filter heard {} of {posts} posted messages",
                POSTED_HEARD.load(Ordering::SeqCst)
            );
            assert!(
                PASSES.load(Ordering::SeqCst) >= 1,
                "the hook never handed over in {posts} posted messages"
            );
            assert!(raised.take().is_none());
        }
    }
}

#[cfg(test)]
mod tests {
    use std::cell::Cell;

    use super::{hand_over, MenuTurn};
    use crate::gvl_handoff::Pending;

    fn owed() -> Pending {
        let pending = Pending::default();
        pending.request();
        pending
    }

    #[test]
    fn an_owed_hand_off_passes_once_and_clears_the_mark() {
        let pending = owed();
        let busy = Cell::new(false);
        let raised: Cell<Option<&str>> = Cell::new(None);
        let mut passes = 0;
        let turn = hand_over(
            &pending,
            &busy,
            &raised,
            || true,
            || false,
            || {
                passes += 1;
                Ok(())
            },
        );
        assert_eq!(turn, MenuTurn::Passed);
        assert_eq!(passes, 1);
        assert!(!pending.take(), "the hand-off cleared the mark");
        assert!(!busy.get(), "and is no longer busy");
        let turn = hand_over(
            &pending,
            &busy,
            &raised,
            || true,
            || false,
            || {
                passes += 1;
                Ok(())
            },
        );
        assert_eq!(turn, MenuTurn::Skipped);
        assert_eq!(passes, 1, "nothing owed, nothing passed");
    }

    #[test]
    fn a_pending_interrupt_passes_with_no_hand_off_owed() {
        let pending = Pending::default();
        let busy = Cell::new(false);
        let raised: Cell<Option<&str>> = Cell::new(None);
        let mut passes = 0;
        let turn = hand_over(
            &pending,
            &busy,
            &raised,
            || true,
            || true,
            || {
                passes += 1;
                Ok(())
            },
        );
        assert_eq!(
            turn,
            MenuTurn::Passed,
            "the main thread alone still runs its trap"
        );
        assert_eq!(passes, 1);
    }

    #[test]
    fn without_the_gvl_nothing_is_asked_or_passed_and_the_hand_off_stays_owed() {
        let pending = owed();
        let busy = Cell::new(false);
        let raised: Cell<Option<&str>> = Cell::new(None);
        let turn = hand_over(
            &pending,
            &busy,
            &raised,
            || false,
            || panic!("asked Ruby for interrupts without the GVL"),
            || panic!("passed without the GVL"),
        );
        assert_eq!(turn, MenuTurn::Skipped);
        assert!(pending.take(), "still owed for a hook call that holds it");
    }

    #[test]
    fn inside_its_own_hand_off_the_hook_does_nothing() {
        let pending = owed();
        let busy = Cell::new(true);
        let raised = Cell::new(Some("waiting"));
        let turn = hand_over(
            &pending,
            &busy,
            &raised,
            || panic!("asked for the GVL while busy"),
            || panic!("asked for interrupts while busy"),
            || panic!("passed while busy"),
        );
        assert_eq!(turn, MenuTurn::Skipped, "not even ending the menu");
        assert!(busy.get());
        assert!(pending.take(), "still owed");
    }

    #[test]
    fn the_hook_is_busy_while_it_passes() {
        let pending = owed();
        let busy = Cell::new(false);
        let raised: Cell<Option<&str>> = Cell::new(None);
        let mut seen = false;
        hand_over(
            &pending,
            &busy,
            &raised,
            || true,
            || false,
            || {
                seen = busy.get();
                Ok(())
            },
        );
        assert!(seen);
    }

    #[test]
    fn an_exception_is_kept_and_ends_the_menu() {
        let busy = Cell::new(false);
        let raised = Cell::new(None);
        let turn = hand_over(&owed(), &busy, &raised, || true, || false, || Err("first"));
        assert_eq!(turn, MenuTurn::Ending);
        assert!(!busy.get(), "a failed pass is no longer busy");
        assert_eq!(raised.take(), Some("first"));
    }

    #[test]
    fn while_an_exception_waits_the_hook_ends_the_menu_and_passes_no_more() {
        let pending = owed();
        let busy = Cell::new(false);
        let raised = Cell::new(Some("first"));
        let turn = hand_over(&pending, &busy, &raised, || true, || true, || Err("second"));
        assert_eq!(turn, MenuTurn::Ending);
        assert_eq!(raised.take(), Some("first"), "the first exception stays");
        assert!(pending.take(), "the owed hand-off waits for the loop");
    }

    #[test]
    fn a_panicking_pass_leaves_the_hook_free() {
        let pending = owed();
        let busy = Cell::new(false);
        let raised: Cell<Option<&str>> = Cell::new(None);
        let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            hand_over(
                &pending,
                &busy,
                &raised,
                || true,
                || false,
                || panic!("pass failed"),
            )
        }));
        assert!(outcome.is_err());
        assert!(!busy.get());
    }
}
