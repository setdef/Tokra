// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! muda's menus: `Tokra::Native::Menu`, `Submenu`, `MenuItem`,
//! `CheckMenuItem`, and `PredefinedMenuItem` (plan 042).
//!
//! Each class holds one muda value in a [`ThreadBound`]: muda's items are
//! `Rc`s over platform objects, usable only on the main thread, where
//! Tauri also keeps them (`run_item_main_thread!`, `menu/mod.rs:25-39`).
//! The classes expose muda's own methods; Tauri's logic around them (the
//! stash, the listeners, the builders, the default menu, the plugin) is
//! Ruby's, in `lib/tokra/menu`.
//!
//! The calls that attach a menu to the app or to a window are where a
//! test's stub can stand in for them: the module functions
//! `Native.init_menu_for_nsapp` and its siblings on macOS, and
//! `Native::Window#init_menu` and its siblings on Windows and Linux. Each
//! is defined only where Tauri calls it (plan 042, decision 1).
//!
//! muda reports a click through one event handler per process
//! (`src/lib.rs:445-487`). Tauri sets it once, to send the event through
//! its loop's proxy (`app.rs:2196-2201`); Tokra does the same, through the
//! proxy of the loop that runs now ([`attach_loop`]).

use std::sync::{Mutex, Once};

use magnus::{
    function, method, prelude::*, rb_sys::AsRawValue, Error, RArray, RHash, RModule, RString, Ruby,
    TryConvert, Value,
};
use muda::{IsMenuItem, MenuId, MenuItemKind};
use tao::event_loop::EventLoopProxy;

use crate::runtime_error;
use crate::thread_bound::{wrong_thread, ThreadBound};
use crate::user_event::{Released, UserEvent};

/// The proxy of the event loop that runs now, which muda's event handler
/// and off-thread drops send through.
static LOOP_PROXY: Mutex<Option<EventLoopProxy<UserEvent>>> = Mutex::new(None);

/// Sets muda's event handler, once per process: muda keeps the first
/// handler it is given (`MENU_EVENT_HANDLER`, a `OnceCell`).
static EVENT_HANDLER: Once = Once::new();

/// Makes `proxy`'s loop the one menu events and released menus go to.
///
/// Called as each `Native::EventLoop` is built, as Tauri sets its handler
/// right after its runtime exists (`app.rs:2196-2201`). The handler sends
/// `UserEvent::MenuEvent` with the item's id, and calls no Ruby.
///
/// The proxy stays after its loop ends, until the next loop replaces it.
/// That is harmless: a send to an ended loop fails and hands the event
/// back, and a released menu inside it drops here, where its
/// `ThreadBound` forgets it rather than drop it on the wrong thread.
pub fn attach_loop(proxy: EventLoopProxy<UserEvent>) {
    if let Ok(mut current) = LOOP_PROXY.lock() {
        *current = Some(proxy);
    }
    EVENT_HANDLER.call_once(|| {
        muda::MenuEvent::set_event_handler(Some(|event: muda::MenuEvent| {
            if let Some(proxy) = loop_proxy() {
                let _ = proxy.send_event(UserEvent::MenuEvent(event.id.0));
            }
        }));
    });
}

/// A copy of the running loop's proxy, taken out of the lock before
/// anything is sent through it.
fn loop_proxy() -> Option<EventLoopProxy<UserEvent>> {
    LOOP_PROXY.lock().ok().and_then(|proxy| proxy.clone())
}

/// Sends a menu value Ruby freed on another thread to the main thread to
/// be dropped there, as Tauri's wrappers do (`menu/mod.rs:96-104`). With
/// no loop to take it, the `ThreadBound` leaks it.
fn release<T: 'static>(inner: &mut ThreadBound<T>) {
    if inner.owner().is_current() {
        return;
    }
    let value = inner.take();
    if let Some(proxy) = loop_proxy() {
        let _ = proxy.send_event(UserEvent::Release(Released::Menu(Box::new(value))));
    }
}

/// Raises `ThreadError` unless Ruby's main thread calls. muda's macOS
/// menus panic off the main thread (`MainThreadMarker`,
/// `platform_impl/macos/mod.rs:82-83`) and GTK's belong to the thread that
/// started GTK, the one tao's loop runs on.
fn on_main_thread(ruby: &Ruby, class: &str) -> Result<(), Error> {
    if ruby.thread_current().as_raw() == ruby.thread_main().as_raw() {
        Ok(())
    } else {
        Err(Error::new(
            ruby.exception_thread_error(),
            format!("{class} can only be created on the main thread"),
        ))
    }
}

/// A muda error as a `RuntimeError` with muda's text, which Ruby raises as
/// `Error::Menu` ("menu error: …", Tauri `error.rs:98-101`).
fn menu_error(error: &muda::Error) -> Error {
    Error::new(runtime_error(), error.to_string())
}

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: Accelerator parsing adapted from tauri/crates/tauri/src/menu/normal.rs

/// An accelerator string parsed as muda parses it, or `None` when it does
/// not parse: Tauri drops a bad accelerator without an error
/// (`menu/normal.rs:34`, `menu/check.rs:35`).
fn accelerator(text: Option<String>) -> Option<muda::accelerator::Accelerator> {
    text.and_then(|text| text.parse().ok())
}

// SPDX-SnippetEnd

/// Defines a Ruby class around one muda type, with its thread guard and
/// its drop on the main thread.
macro_rules! menu_class {
    ($rb:ident, $muda:ty, $class:literal) => {
        #[magnus::wrap(class = $class, free_immediately, size)]
        pub struct $rb {
            inner: ThreadBound<$muda>,
        }

        impl $rb {
            const CLASS: &'static str = $class;

            fn wrap(value: $muda) -> Self {
                Self {
                    inner: ThreadBound::new(value),
                }
            }

            /// The muda value, on its own thread.
            pub(crate) fn get(&self) -> Result<&$muda, Error> {
                self.inner.get().ok_or_else(|| wrong_thread(Self::CLASS))
            }

            fn id(&self) -> Result<String, Error> {
                Ok(self.get()?.id().0.clone())
            }
        }

        impl Drop for $rb {
            /// Ruby frees this object on whichever thread sweeps it; off
            /// the main thread the muda value goes home to be dropped
            /// ([`release`]). No Ruby API is called, as
            /// `free_immediately` requires.
            fn drop(&mut self) {
                release(&mut self.inner);
            }
        }
    };
}

menu_class!(RbMenu, muda::Menu, "Tokra::Native::Menu");
menu_class!(RbSubmenu, muda::Submenu, "Tokra::Native::Submenu");
menu_class!(RbMenuItem, muda::MenuItem, "Tokra::Native::MenuItem");
menu_class!(
    RbCheckMenuItem,
    muda::CheckMenuItem,
    "Tokra::Native::CheckMenuItem"
);
menu_class!(
    RbPredefinedMenuItem,
    muda::PredefinedMenuItem,
    "Tokra::Native::PredefinedMenuItem"
);

/// Runs `f` with the muda item a Ruby value wraps.
///
/// # Errors
///
/// Returns `TypeError` for a value that is no native item, as Rust's
/// `&dyn IsMenuItem` bound would not compile, and `ThreadError` on another
/// thread.
fn with_item<T>(item: Value, f: impl FnOnce(&dyn IsMenuItem) -> T) -> Result<T, Error> {
    if let Ok(item) = <&RbMenuItem>::try_convert(item) {
        return Ok(f(item.get()?));
    }
    if let Ok(item) = <&RbSubmenu>::try_convert(item) {
        return Ok(f(item.get()?));
    }
    if let Ok(item) = <&RbCheckMenuItem>::try_convert(item) {
        return Ok(f(item.get()?));
    }
    if let Ok(item) = <&RbPredefinedMenuItem>::try_convert(item) {
        return Ok(f(item.get()?));
    }
    let ruby = Ruby::get_with(item);
    Err(Error::new(
        ruby.exception_type_error(),
        format!(
            "wrong argument type {} (expected a native menu item)",
            item.class().inspect()
        ),
    ))
}

/// A muda item as the native object that wraps it.
fn item_value(ruby: &Ruby, item: MenuItemKind) -> Value {
    match item {
        MenuItemKind::MenuItem(item) => ruby.obj_wrap(RbMenuItem::wrap(item)).as_value(),
        MenuItemKind::Submenu(item) => ruby.obj_wrap(RbSubmenu::wrap(item)).as_value(),
        MenuItemKind::Predefined(item) => {
            ruby.obj_wrap(RbPredefinedMenuItem::wrap(item)).as_value()
        }
        MenuItemKind::Check(item) => ruby.obj_wrap(RbCheckMenuItem::wrap(item)).as_value(),
        // Tokra makes no icon items yet (plan 042, phase 2), so no tree
        // holds one; muda's id is all there is to answer with.
        MenuItemKind::Icon(item) => ruby.str_new(&item.id().0).as_value(),
    }
}

/// The native objects for a list of muda items.
fn item_values(ruby: &Ruby, items: Vec<MenuItemKind>) -> RArray {
    let array = ruby.ary_new_capa(items.len());
    for item in items {
        // Pushing onto a new array never fails.
        let _ = array.push(item_value(ruby, item));
    }
    array
}

/// Whether `submenu` holds an item with `id`, at any depth.
fn holds(submenu: &muda::Submenu, id: &MenuId) -> bool {
    submenu.items().iter().any(|item| match item {
        MenuItemKind::Submenu(child) => child.id() == id || holds(child, id),
        other => other.id() == id,
    })
}

/// Refuses an add that would put a submenu inside itself.
///
/// muda borrows the target's `RefCell` while it builds the item's platform
/// menus, which walk the item's children; if the target is among them, the
/// second borrow panics (`platform_impl/macos/mod.rs:531-560`), and a cycle
/// that got in would recurse without end. A panic would end Ruby's VM, so
/// Tokra refuses it first (plan 042, decision 8). Tauri has no such check.
fn refuse_cycle(target: &MenuId, item: Value) -> Result<(), Error> {
    if let Ok(submenu) = <&RbSubmenu>::try_convert(item) {
        let submenu = submenu.get()?;
        if submenu.id() == target || holds(submenu, target) {
            return Err(Error::new(
                Ruby::get_with(item).exception_arg_error(),
                "a submenu cannot be added to itself or to a menu inside it",
            ));
        }
    }
    Ok(())
}

/// Refuses a position past the end, where muda's `Vec::insert` panics and
/// `AppKit` raises `NSRangeException`. It raises `IndexError`, Ruby's word
/// for that panic, with std's panic message, the one Tauri would end with.
fn refuse_position(ruby: &Ruby, len: usize, position: usize) -> Result<(), Error> {
    if position > len {
        return Err(Error::new(
            ruby.exception_index_error(),
            format!("insertion index (is {position}) should be <= len (is {len})"),
        ));
    }
    Ok(())
}

/// The menu tree methods `Menu` and `Submenu` share.
macro_rules! menu_tree {
    ($rb:ident) => {
        impl $rb {
            fn append(&self, item: Value) -> Result<(), Error> {
                let menu = self.get()?;
                refuse_cycle(menu.id(), item)?;
                with_item(item, |item| menu.append(item))?.map_err(|e| menu_error(&e))
            }

            fn prepend(&self, item: Value) -> Result<(), Error> {
                let menu = self.get()?;
                refuse_cycle(menu.id(), item)?;
                with_item(item, |item| menu.prepend(item))?.map_err(|e| menu_error(&e))
            }

            fn insert(
                ruby: &Ruby,
                rb_self: &Self,
                item: Value,
                position: usize,
            ) -> Result<(), Error> {
                let menu = rb_self.get()?;
                refuse_cycle(menu.id(), item)?;
                refuse_position(ruby, menu.items().len(), position)?;
                with_item(item, |item| menu.insert(item, position))?.map_err(|e| menu_error(&e))
            }

            fn remove(&self, item: Value) -> Result<(), Error> {
                let menu = self.get()?;
                with_item(item, |item| menu.remove(item))?.map_err(|e| menu_error(&e))
            }

            fn remove_at(
                ruby: &Ruby,
                rb_self: &Self,
                position: usize,
            ) -> Result<Option<Value>, Error> {
                Ok(rb_self
                    .get()?
                    .remove_at(position)
                    .map(|item| item_value(ruby, item)))
            }

            fn items(ruby: &Ruby, rb_self: &Self) -> Result<RArray, Error> {
                Ok(item_values(ruby, rb_self.get()?.items()))
            }
        }
    };
}

menu_tree!(RbMenu);
menu_tree!(RbSubmenu);

impl RbMenu {
    fn new(ruby: &Ruby) -> Result<Self, Error> {
        on_main_thread(ruby, Self::CLASS)?;
        Ok(Self::wrap(muda::Menu::new()))
    }

    fn with_id(ruby: &Ruby, id: String) -> Result<Self, Error> {
        on_main_thread(ruby, Self::CLASS)?;
        Ok(Self::wrap(muda::Menu::with_id(id)))
    }
}

/// The text, enabled state, and accelerator methods items share.
macro_rules! text_methods {
    ($rb:ident) => {
        impl $rb {
            fn text(&self) -> Result<String, Error> {
                Ok(self.get()?.text())
            }

            fn set_text(&self, text: String) -> Result<(), Error> {
                self.get()?.set_text(text);
                Ok(())
            }
        }
    };
}

macro_rules! enabled_methods {
    ($rb:ident) => {
        impl $rb {
            fn is_enabled(&self) -> Result<bool, Error> {
                Ok(self.get()?.is_enabled())
            }

            fn set_enabled(&self, enabled: bool) -> Result<(), Error> {
                self.get()?.set_enabled(enabled);
                Ok(())
            }
        }
    };
}

macro_rules! accelerator_methods {
    ($rb:ident) => {
        impl $rb {
            fn set_accelerator(&self, text: Option<String>) -> Result<(), Error> {
                self.get()?
                    .set_accelerator(accelerator(text))
                    .map_err(|e| menu_error(&e))
            }
        }
    };
}

text_methods!(RbSubmenu);
text_methods!(RbMenuItem);
text_methods!(RbCheckMenuItem);
text_methods!(RbPredefinedMenuItem);
enabled_methods!(RbSubmenu);
enabled_methods!(RbMenuItem);
enabled_methods!(RbCheckMenuItem);
accelerator_methods!(RbMenuItem);
accelerator_methods!(RbCheckMenuItem);

impl RbSubmenu {
    fn new(ruby: &Ruby, text: String, enabled: bool) -> Result<Self, Error> {
        on_main_thread(ruby, Self::CLASS)?;
        Ok(Self::wrap(muda::Submenu::new(text, enabled)))
    }

    fn with_id(ruby: &Ruby, id: String, text: String, enabled: bool) -> Result<Self, Error> {
        on_main_thread(ruby, Self::CLASS)?;
        Ok(Self::wrap(muda::Submenu::with_id(id, text, enabled)))
    }
}

impl RbMenuItem {
    fn new(
        ruby: &Ruby,
        text: String,
        enabled: bool,
        accelerator_text: Option<String>,
    ) -> Result<Self, Error> {
        on_main_thread(ruby, Self::CLASS)?;
        Ok(Self::wrap(muda::MenuItem::new(
            text,
            enabled,
            accelerator(accelerator_text),
        )))
    }

    fn with_id(
        ruby: &Ruby,
        id: String,
        text: String,
        enabled: bool,
        accelerator_text: Option<String>,
    ) -> Result<Self, Error> {
        on_main_thread(ruby, Self::CLASS)?;
        Ok(Self::wrap(muda::MenuItem::with_id(
            id,
            text,
            enabled,
            accelerator(accelerator_text),
        )))
    }
}

impl RbCheckMenuItem {
    fn new(
        ruby: &Ruby,
        text: String,
        enabled: bool,
        checked: bool,
        accelerator_text: Option<String>,
    ) -> Result<Self, Error> {
        on_main_thread(ruby, Self::CLASS)?;
        Ok(Self::wrap(muda::CheckMenuItem::new(
            text,
            enabled,
            checked,
            accelerator(accelerator_text),
        )))
    }

    fn with_id(
        ruby: &Ruby,
        id: String,
        text: String,
        enabled: bool,
        checked: bool,
        accelerator_text: Option<String>,
    ) -> Result<Self, Error> {
        on_main_thread(ruby, Self::CLASS)?;
        Ok(Self::wrap(muda::CheckMenuItem::with_id(
            id,
            text,
            enabled,
            checked,
            accelerator(accelerator_text),
        )))
    }

    fn is_checked(&self) -> Result<bool, Error> {
        Ok(self.get()?.is_checked())
    }

    fn set_checked(&self, checked: bool) -> Result<(), Error> {
        self.get()?.set_checked(checked);
        Ok(())
    }
}

impl RbPredefinedMenuItem {
    /// muda's predefined item named `kind`, one of the 17 Tauri offers
    /// (`menu/predefined.rs`), with `text` in place of the platform's own
    /// where given, and `about` for the About item: a Hash of
    /// `AboutMetadata`'s fields, its `:icon` an `[rgba, width, height]`.
    fn new(
        ruby: &Ruby,
        kind: RString,
        text: Option<RString>,
        about: Option<RHash>,
    ) -> Result<Self, Error> {
        on_main_thread(ruby, Self::CLASS)?;
        let kind = kind.to_string()?;
        let text = text.map(RString::to_string).transpose()?;
        let text = text.as_deref();
        let item = match kind.as_str() {
            "separator" => muda::PredefinedMenuItem::separator(),
            "copy" => muda::PredefinedMenuItem::copy(text),
            "cut" => muda::PredefinedMenuItem::cut(text),
            "paste" => muda::PredefinedMenuItem::paste(text),
            "select_all" => muda::PredefinedMenuItem::select_all(text),
            "undo" => muda::PredefinedMenuItem::undo(text),
            "redo" => muda::PredefinedMenuItem::redo(text),
            "minimize" => muda::PredefinedMenuItem::minimize(text),
            "maximize" => muda::PredefinedMenuItem::maximize(text),
            "fullscreen" => muda::PredefinedMenuItem::fullscreen(text),
            "hide" => muda::PredefinedMenuItem::hide(text),
            "hide_others" => muda::PredefinedMenuItem::hide_others(text),
            "show_all" => muda::PredefinedMenuItem::show_all(text),
            "close_window" => muda::PredefinedMenuItem::close_window(text),
            "quit" => muda::PredefinedMenuItem::quit(text),
            "about" => muda::PredefinedMenuItem::about(text, about_metadata(ruby, about)?),
            "services" => muda::PredefinedMenuItem::services(text),
            _ => {
                return Err(Error::new(
                    ruby.exception_arg_error(),
                    format!("unknown predefined menu item: {kind:?}"),
                ))
            }
        };
        Ok(Self::wrap(item))
    }
}

/// muda's `AboutMetadata` from the Hash `PredefinedMenuItem.new` takes.
///
/// # Errors
///
/// Returns `TypeError` for a field of the wrong type, and a
/// `RuntimeError` with muda's `BadIcon` text for an icon muda refuses,
/// which Ruby raises as `Error::BadMenuIcon` (Tauri `error.rs:102-105`).
fn about_metadata(ruby: &Ruby, about: Option<RHash>) -> Result<Option<muda::AboutMetadata>, Error> {
    let Some(about) = about else {
        return Ok(None);
    };
    let text = |key: &str| about.lookup::<_, Option<String>>(ruby.to_symbol(key));
    let icon = match about.lookup::<_, Option<(RString, u32, u32)>>(ruby.to_symbol("icon"))? {
        Some((rgba, width, height)) => Some(menu_icon(rgba, width, height)?),
        None => None,
    };
    Ok(Some(muda::AboutMetadata {
        name: text("name")?,
        version: text("version")?,
        short_version: text("short_version")?,
        authors: about.lookup::<_, Option<Vec<String>>>(ruby.to_symbol("authors"))?,
        comments: text("comments")?,
        copyright: text("copyright")?,
        license: text("license")?,
        website: text("website")?,
        website_label: text("website_label")?,
        credits: text("credits")?,
        icon,
    }))
}

/// muda's `Icon::from_rgba`, after muda's own checks.
///
/// muda's GTK icon checks nothing and hands the bytes to
/// `Pixbuf::from_mut_slice`, which panics on the main thread when they are
/// short (muda 0.17.1 `platform_impl/gtk/icon.rs:27-38`), as tao's did
/// (plan 041, decision 4); and its checks multiply the dimensions as `u32`,
/// which overflows. So Tokra runs muda's `RgbaIcon` checks first on every
/// platform, in 64 bits, with muda's texts.
fn menu_icon(rgba: RString, width: u32, height: u32) -> Result<muda::Icon, Error> {
    let rgba = rgba.to_bytes().to_vec();
    if let Some(message) = bad_menu_icon(rgba.len(), width, height) {
        return Err(Error::new(runtime_error(), message));
    }
    muda::Icon::from_rgba(rgba, width, height)
        .map_err(|e| Error::new(runtime_error(), e.to_string()))
}

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2022-2022 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: The RGBA checks and their texts adapted from muda 0.17.1 src/icon.rs

/// Why muda would refuse `byte_count` bytes as a `width` by `height` icon,
/// in its own words (`src/icon.rs:27-45`, `82-103`), or `None`.
fn bad_menu_icon(byte_count: usize, width: u32, height: u32) -> Option<String> {
    if !byte_count.is_multiple_of(4) {
        return Some(format!(
            "The length of the `rgba` argument ({byte_count:?}) isn't divisible by 4, making it impossible to interpret as 32bpp RGBA pixels."
        ));
    }
    let pixel_count = byte_count / 4;
    let width_x_height = u64::from(width) * u64::from(height);
    if u64::try_from(pixel_count).ok() == Some(width_x_height) {
        None
    } else {
        Some(format!(
            "The specified dimensions ({width:?}x{height:?}) don't match the number of pixels supplied by the `rgba` argument ({pixel_count:?}). For those dimensions, the expected pixel count is {width_x_height:?}."
        ))
    }
}

// SPDX-SnippetEnd

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: The app menu calls adapted from tauri/crates/tauri/src/app.rs
//                      (init_app_menu, remove_menu) and menu/submenu.rs

/// `-[NSApp setMainMenu:]` with `menu`, muda's `init_for_nsapp`
/// (`app.rs:2336-2337`).
#[cfg(target_os = "macos")]
fn init_menu_for_nsapp(menu: &RbMenu) -> Result<(), Error> {
    menu.get()?.init_for_nsapp();
    Ok(())
}

/// Takes `menu` off `NSApp`, muda's `remove_for_nsapp` (`app.rs:955-960`).
#[cfg(target_os = "macos")]
fn remove_menu_for_nsapp(menu: &RbMenu) -> Result<(), Error> {
    menu.get()?.remove_for_nsapp();
    Ok(())
}

/// Makes `submenu` `NSApp`'s Window menu (`menu/submenu.rs`).
#[cfg(target_os = "macos")]
fn set_windows_menu_for_nsapp(submenu: &RbSubmenu) -> Result<(), Error> {
    submenu.get()?.set_as_windows_menu_for_nsapp();
    Ok(())
}

/// Makes `submenu` `NSApp`'s Help menu (`menu/submenu.rs`).
#[cfg(target_os = "macos")]
fn set_help_menu_for_nsapp(submenu: &RbSubmenu) -> Result<(), Error> {
    submenu.get()?.set_as_help_menu_for_nsapp();
    Ok(())
}

// SPDX-SnippetEnd

#[cfg(windows)]
pub use accelerators::translate_accelerator;

/// The Windows message hook that makes keyboard accelerators work, as
/// Tauri's does (`app.rs:2145-2162`, plan 042, decision 10).
#[cfg(windows)]
mod accelerators {
    use std::cell::RefCell;

    use windows::Win32::UI::WindowsAndMessaging::{TranslateAcceleratorW, HACCEL, MSG};

    thread_local! {
        /// The menus in Ruby's stash, the main thread's copy.
        pub static MENUS: RefCell<Vec<muda::Menu>> = const { RefCell::new(Vec::new()) };
    }

    // SPDX-SnippetBegin
    // SPDX-License-Identifier: Apache-2.0 OR MIT
    // SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    // SPDX-SnippetComment: The message hook adapted from tauri/crates/tauri/src/app.rs

    /// Whether one of the stashed menus' accelerator tables translated
    /// `msg`, which tao then does not dispatch.
    pub fn translate_accelerator(msg: *const std::ffi::c_void) -> bool {
        let msg = msg.cast::<MSG>();
        MENUS.with(|menus| {
            let Ok(menus) = menus.try_borrow() else {
                return false;
            };
            menus.iter().any(|menu| {
                // SAFETY: tao calls the hook with the `MSG` it is about to
                // dispatch, valid for the call (tao 0.34.5
                // `platform_impl/windows/event_loop.rs`, `with_msg_hook`);
                // `TranslateAcceleratorW` only reads it and the table
                // muda owns, as Tauri's hook does (`app.rs:2148-2156`).
                #[allow(unsafe_code)]
                let translated =
                    unsafe { TranslateAcceleratorW((*msg).hwnd, HACCEL(menu.haccel() as _), msg) };
                translated == 1
            })
        })
    }

    // SPDX-SnippetEnd
}

/// Replaces the main thread's copy of the stash with `menus`
/// (`Native.set_accelerator_menus`, Windows only).
#[cfg(windows)]
fn set_accelerator_menus(menus: RArray) -> Result<(), Error> {
    let mut list = Vec::with_capacity(menus.len());
    for menu in menus {
        list.push(<&RbMenu>::try_convert(menu)?.get()?.clone());
    }
    accelerators::MENUS.with(|menus| {
        if let Ok(mut menus) = menus.try_borrow_mut() {
            *menus = list;
        }
    });
    Ok(())
}

/// Defines the menu classes and the app menu functions.
///
/// # Errors
///
/// Returns an error if class or method definition fails.
pub fn define_classes(ruby: &Ruby, native: RModule) -> Result<(), Error> {
    let menu = native.define_class("Menu", ruby.class_object())?;
    menu.define_singleton_method("new", function!(RbMenu::new, 0))?;
    menu.define_singleton_method("with_id", function!(RbMenu::with_id, 1))?;
    menu.define_method("id", method!(RbMenu::id, 0))?;
    menu.define_method("append", method!(RbMenu::append, 1))?;
    menu.define_method("prepend", method!(RbMenu::prepend, 1))?;
    menu.define_method("insert", method!(RbMenu::insert, 2))?;
    menu.define_method("remove", method!(RbMenu::remove, 1))?;
    menu.define_method("remove_at", method!(RbMenu::remove_at, 1))?;
    menu.define_method("items", method!(RbMenu::items, 0))?;

    let submenu = native.define_class("Submenu", ruby.class_object())?;
    submenu.define_singleton_method("new", function!(RbSubmenu::new, 2))?;
    submenu.define_singleton_method("with_id", function!(RbSubmenu::with_id, 3))?;
    submenu.define_method("id", method!(RbSubmenu::id, 0))?;
    submenu.define_method("append", method!(RbSubmenu::append, 1))?;
    submenu.define_method("prepend", method!(RbSubmenu::prepend, 1))?;
    submenu.define_method("insert", method!(RbSubmenu::insert, 2))?;
    submenu.define_method("remove", method!(RbSubmenu::remove, 1))?;
    submenu.define_method("remove_at", method!(RbSubmenu::remove_at, 1))?;
    submenu.define_method("items", method!(RbSubmenu::items, 0))?;
    submenu.define_method("text", method!(RbSubmenu::text, 0))?;
    submenu.define_method("set_text", method!(RbSubmenu::set_text, 1))?;
    submenu.define_method("is_enabled", method!(RbSubmenu::is_enabled, 0))?;
    submenu.define_method("set_enabled", method!(RbSubmenu::set_enabled, 1))?;

    let item = native.define_class("MenuItem", ruby.class_object())?;
    item.define_singleton_method("new", function!(RbMenuItem::new, 3))?;
    item.define_singleton_method("with_id", function!(RbMenuItem::with_id, 4))?;
    item.define_method("id", method!(RbMenuItem::id, 0))?;
    item.define_method("text", method!(RbMenuItem::text, 0))?;
    item.define_method("set_text", method!(RbMenuItem::set_text, 1))?;
    item.define_method("is_enabled", method!(RbMenuItem::is_enabled, 0))?;
    item.define_method("set_enabled", method!(RbMenuItem::set_enabled, 1))?;
    item.define_method("set_accelerator", method!(RbMenuItem::set_accelerator, 1))?;

    let check = native.define_class("CheckMenuItem", ruby.class_object())?;
    check.define_singleton_method("new", function!(RbCheckMenuItem::new, 4))?;
    check.define_singleton_method("with_id", function!(RbCheckMenuItem::with_id, 5))?;
    check.define_method("id", method!(RbCheckMenuItem::id, 0))?;
    check.define_method("text", method!(RbCheckMenuItem::text, 0))?;
    check.define_method("set_text", method!(RbCheckMenuItem::set_text, 1))?;
    check.define_method("is_enabled", method!(RbCheckMenuItem::is_enabled, 0))?;
    check.define_method("set_enabled", method!(RbCheckMenuItem::set_enabled, 1))?;
    check.define_method(
        "set_accelerator",
        method!(RbCheckMenuItem::set_accelerator, 1),
    )?;
    check.define_method("is_checked", method!(RbCheckMenuItem::is_checked, 0))?;
    check.define_method("set_checked", method!(RbCheckMenuItem::set_checked, 1))?;

    let predefined = native.define_class("PredefinedMenuItem", ruby.class_object())?;
    predefined.define_singleton_method("new", function!(RbPredefinedMenuItem::new, 3))?;
    predefined.define_method("id", method!(RbPredefinedMenuItem::id, 0))?;
    predefined.define_method("text", method!(RbPredefinedMenuItem::text, 0))?;
    predefined.define_method("set_text", method!(RbPredefinedMenuItem::set_text, 1))?;

    #[cfg(target_os = "macos")]
    {
        native.define_module_function("init_menu_for_nsapp", function!(init_menu_for_nsapp, 1))?;
        native
            .define_module_function("remove_menu_for_nsapp", function!(remove_menu_for_nsapp, 1))?;
        native.define_module_function(
            "set_windows_menu_for_nsapp",
            function!(set_windows_menu_for_nsapp, 1),
        )?;
        native.define_module_function(
            "set_help_menu_for_nsapp",
            function!(set_help_menu_for_nsapp, 1),
        )?;
    }
    #[cfg(windows)]
    native.define_module_function("set_accelerator_menus", function!(set_accelerator_menus, 1))?;
    Ok(())
}

#[cfg(any(
    windows,
    target_os = "linux",
    target_os = "dragonfly",
    target_os = "freebsd",
    target_os = "netbsd",
    target_os = "openbsd"
))]
pub use window_menu::define_window_methods;

/// A window's own menu bar, on Windows and Linux; macOS has only the app's
/// (Tauri `window/mod.rs:1199-1363`, `manager/menu.rs:54-95`).
///
/// Each method does nothing for a closed window, as Tauri's does when the
/// window's `hwnd()` or `gtk_window()` fails, and ignores muda's answer,
/// as Tauri's `let _ =` does; `is_menu_visible` answers `false` there,
/// Tauri's `unwrap_or(false)`.
#[cfg(any(
    windows,
    target_os = "linux",
    target_os = "dragonfly",
    target_os = "freebsd",
    target_os = "netbsd",
    target_os = "openbsd"
))]
mod window_menu {
    use magnus::{method, prelude::*, Error, RClass};

    use super::RbMenu;
    use crate::window::RbWindow;

    // SPDX-SnippetBegin
    // SPDX-License-Identifier: Apache-2.0 OR MIT
    // SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    // SPDX-SnippetComment: Window menus adapted from tauri/crates/tauri/src/window/mod.rs
    //                      and manager/menu.rs

    /// Puts `menu` on the window: on Windows with `theme` ("Light",
    /// "Dark", or anything else for Auto), or with the window's own theme
    /// when `theme` is `nil`; on Linux in the window's default box, doing
    /// nothing without one.
    ///
    /// Tauri themes a new window's menu with the configured theme or Auto
    /// (`manager/menu.rs:74-79`), and `Window::set_menu` with the window's
    /// theme (`window/mod.rs:1205-1224`).
    fn init_menu(window: &RbWindow, menu: &RbMenu, theme: Option<String>) -> Result<(), Error> {
        let menu = menu.get()?;
        let Some(window) = window.open_window()? else {
            return Ok(());
        };
        #[cfg(windows)]
        {
            use tao::platform::windows::WindowExtWindows;
            let theme = theme.map_or_else(
                || match window.theme() {
                    tao::window::Theme::Light => muda::MenuTheme::Light,
                    tao::window::Theme::Dark => muda::MenuTheme::Dark,
                    _ => muda::MenuTheme::Auto,
                },
                |name| match name.as_str() {
                    "Light" => muda::MenuTheme::Light,
                    "Dark" => muda::MenuTheme::Dark,
                    _ => muda::MenuTheme::Auto,
                },
            );
            // SAFETY: `hwnd` is the open tao window's, read and used on
            // the thread that owns it; muda subclasses that window and
            // gives it a menu bar (muda 0.17.1 `src/menu.rs:226-256`).
            #[allow(unsafe_code)]
            let _ = unsafe { menu.init_for_hwnd_with_theme(window.hwnd(), theme) };
        }
        #[cfg(not(windows))]
        {
            use tao::platform::unix::WindowExtUnix;
            drop(theme);
            if let Some(vbox) = window.default_vbox() {
                let _ = menu.init_for_gtk_window(window.gtk_window(), Some(vbox));
            }
        }
        Ok(())
    }

    /// Takes `menu` off the window (`window/mod.rs:1244-1276`).
    fn remove_menu(window: &RbWindow, menu: &RbMenu) -> Result<(), Error> {
        let menu = menu.get()?;
        let Some(window) = window.open_window()? else {
            return Ok(());
        };
        #[cfg(windows)]
        {
            use tao::platform::windows::WindowExtWindows;
            // SAFETY: as in `init_menu`; muda removes the menu it put on
            // this window.
            #[allow(unsafe_code)]
            let _ = unsafe { menu.remove_for_hwnd(window.hwnd()) };
        }
        #[cfg(not(windows))]
        {
            use tao::platform::unix::WindowExtUnix;
            let _ = menu.remove_for_gtk_window(window.gtk_window());
        }
        Ok(())
    }

    /// Hides `menu` on the window (`window/mod.rs:1278-1304`).
    fn hide_menu(window: &RbWindow, menu: &RbMenu) -> Result<(), Error> {
        let menu = menu.get()?;
        let Some(window) = window.open_window()? else {
            return Ok(());
        };
        #[cfg(windows)]
        {
            use tao::platform::windows::WindowExtWindows;
            // SAFETY: as in `init_menu`.
            #[allow(unsafe_code)]
            let _ = unsafe { menu.hide_for_hwnd(window.hwnd()) };
        }
        #[cfg(not(windows))]
        {
            use tao::platform::unix::WindowExtUnix;
            let _ = menu.hide_for_gtk_window(window.gtk_window());
        }
        Ok(())
    }

    /// Shows `menu` on the window again (`window/mod.rs:1306-1332`).
    fn show_menu(window: &RbWindow, menu: &RbMenu) -> Result<(), Error> {
        let menu = menu.get()?;
        let Some(window) = window.open_window()? else {
            return Ok(());
        };
        #[cfg(windows)]
        {
            use tao::platform::windows::WindowExtWindows;
            // SAFETY: as in `init_menu`.
            #[allow(unsafe_code)]
            let _ = unsafe { menu.show_for_hwnd(window.hwnd()) };
        }
        #[cfg(not(windows))]
        {
            use tao::platform::unix::WindowExtUnix;
            let _ = menu.show_for_gtk_window(window.gtk_window());
        }
        Ok(())
    }

    /// Whether `menu` shows on the window (`window/mod.rs:1334-1363`).
    fn is_menu_visible(window: &RbWindow, menu: &RbMenu) -> Result<bool, Error> {
        let menu = menu.get()?;
        let Some(window) = window.open_window()? else {
            return Ok(false);
        };
        #[cfg(windows)]
        {
            use tao::platform::windows::WindowExtWindows;
            // SAFETY: as in `init_menu`; muda only reads the window's menu.
            #[allow(unsafe_code)]
            let visible = unsafe { menu.is_visible_on_hwnd(window.hwnd()) };
            Ok(visible)
        }
        #[cfg(not(windows))]
        {
            use tao::platform::unix::WindowExtUnix;
            Ok(menu.is_visible_on_gtk_window(window.gtk_window()))
        }
    }

    // SPDX-SnippetEnd

    /// Defines the window's menu methods.
    ///
    /// # Errors
    ///
    /// Returns an error if method definition fails.
    pub fn define_window_methods(class: RClass) -> Result<(), Error> {
        class.define_method("init_menu", method!(init_menu, 2))?;
        class.define_method("remove_menu", method!(remove_menu, 1))?;
        class.define_method("hide_menu", method!(hide_menu, 1))?;
        class.define_method("show_menu", method!(show_menu, 1))?;
        class.define_method("is_menu_visible", method!(is_menu_visible, 1))
    }
}

#[cfg(test)]
mod tests {
    use super::bad_menu_icon;

    #[test]
    fn a_menu_icon_is_refused_as_muda_refuses_it() {
        assert_eq!(bad_menu_icon(4, 1, 1), None);
        assert_eq!(
            bad_menu_icon(5, 1, 1).as_deref(),
            Some("The length of the `rgba` argument (5) isn't divisible by 4, making it impossible to interpret as 32bpp RGBA pixels.")
        );
        assert_eq!(
            bad_menu_icon(4, 2, 2).as_deref(),
            Some("The specified dimensions (2x2) don't match the number of pixels supplied by the `rgba` argument (1). For those dimensions, the expected pixel count is 4.")
        );
        assert!(bad_menu_icon(4, u32::MAX, u32::MAX).is_some());
    }
}
