// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Where each webview keeps its data: Tauri's web-context store.
//!
//! wry keeps a webview's data directory, and on Linux its `WebKitGTK`
//! context and the custom schemes registered on it, in a `WebContext`
//! (wry `src/web_context.rs:13-31`). Tauri's runtime keeps one per data
//! directory, `None` for the default, in a map on the main thread, shared
//! by every webview that names it, and drops it with its last webview,
//! except on Linux, where it lives as long as the app (plan 052, 052e-3).
//!
//! The map holds plain values: wry's context, labels, and scheme names. No
//! Ruby object and no webview enters it (plan 052, decision 3), so nothing
//! in it points into memory Ruby frees. It lives in a thread local of the
//! loop's thread, the only thread that builds or drops a webview
//! (`thread_bound.rs`), as Tauri's lives in its runtime's main-thread
//! context.

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: The web-context store adapted from tauri-runtime-wry/src/lib.rs

use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::marker::PhantomData;
use std::path::PathBuf;
use std::thread::AccessError;

/// Whether a context outlives its last webview: on Linux and the BSDs,
/// where `WebKit` keeps its network process running with no webview left,
/// so Tauri keeps the context to reuse that process (Tauri issue 14626;
/// tauri-runtime-wry `src/lib.rs:2444-2458`). macOS and Windows drop it.
const KEEPS_CONTEXTS: bool = cfg!(any(
    target_os = "linux",
    target_os = "dragonfly",
    target_os = "freebsd",
    target_os = "netbsd",
    target_os = "openbsd"
));

/// A context's data directory, `None` for the default, as Tauri keys its
/// store (tauri-runtime-wry `src/lib.rs:175`).
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct Key(Option<PathBuf>);

/// One data directory's context, as Tauri's `WebContext` holds it
/// (tauri-runtime-wry `src/lib.rs:166-173`).
struct Entry<C> {
    /// wry's context, or `None` while a build borrows it.
    inner: Option<C>,
    /// The labels of the webviews built with it.
    referenced_by_webviews: HashSet<String>,
    /// On Linux the custom schemes are registered on the context, and wry
    /// refuses a scheme registered twice (`src/lib.rs:1103-1116`).
    registered_custom_protocols: HashSet<String>,
}

/// The contexts by data directory, as Tauri's `WebContextStore`
/// (tauri-runtime-wry `src/lib.rs:175`). `C` is wry's `WebContext`; the
/// tests use a value that needs no platform.
pub struct Store<C> {
    contexts: HashMap<Key, Entry<C>>,
    keeps_contexts: bool,
}

impl<C> Store<C> {
    fn new(keeps_contexts: bool) -> Self {
        Self {
            contexts: HashMap::new(),
            keeps_contexts,
        }
    }

    /// Hands out the context of `key` for the webview `label` to build
    /// with, making it with `make` when no webview has it, and records the
    /// label, as `create_webview` finds or makes the store's entry
    /// (tauri-runtime-wry `src/lib.rs:4593-4622`). The caller gives it
    /// back with [`give_back`](Self::give_back).
    ///
    /// # Errors
    ///
    /// Answers the message for a context another build still holds,
    /// before recording anything. Tauri holds its store's lock for the
    /// whole build, so a build inside another would deadlock there.
    fn lend(
        &mut self,
        key: &Key,
        label: &str,
        make: impl FnOnce(Option<PathBuf>) -> C,
    ) -> Result<C, String> {
        let entry = self.contexts.entry(key.clone()).or_insert_with(|| Entry {
            inner: Some(make(key.0.clone())),
            referenced_by_webviews: HashSet::new(),
            registered_custom_protocols: HashSet::new(),
        });
        let context = entry
            .inner
            .take()
            .ok_or_else(|| "the web context is in use by another webview's build".to_string())?;
        entry.referenced_by_webviews.insert(label.to_string());
        Ok(context)
    }

    /// Puts back the context [`lend`](Self::lend) handed out, or drops it
    /// when its every webview has gone meanwhile and contexts are not
    /// kept, as [`release`](Self::release) would have.
    fn give_back(&mut self, key: &Key, context: C) {
        if let Some(entry) = self.contexts.get_mut(key) {
            if self.keeps_contexts || !entry.referenced_by_webviews.is_empty() {
                entry.inner = Some(context);
            } else {
                self.contexts.remove(key);
            }
        }
    }

    /// Whether a webview built with `key`'s context registers `scheme`:
    /// only the first does, as Tauri's runtime skips a scheme the context
    /// already has on Linux (tauri-runtime-wry `src/lib.rs:4964-4981`).
    fn registers(&mut self, key: &Key, scheme: &str) -> bool {
        self.contexts
            .get_mut(key)
            .is_some_and(|entry| entry.registered_custom_protocols.insert(scheme.to_string()))
    }

    /// Forgets the webview `label` built with `key`'s context, and drops
    /// the context with its last webview unless contexts are kept, as
    /// Tauri's `WebviewWrapper` does when its last reference drops
    /// (tauri-runtime-wry `src/lib.rs:2437-2461`).
    fn release(&mut self, key: &Key, label: &str) {
        let Some(entry) = self.contexts.get_mut(key) else {
            return;
        };
        entry.referenced_by_webviews.remove(label);
        if !self.keeps_contexts && entry.referenced_by_webviews.is_empty() && entry.inner.is_some()
        {
            self.contexts.remove(key);
        }
    }
}

thread_local! {
    /// The loop thread's store.
    static STORE: RefCell<Store<wry::WebContext>> = RefCell::new(Store::new(KEEPS_CONTEXTS));
}

/// Where a [`Lent`] and a [`Lease`] find their thread's store, and how a
/// context is made for it: [`Wry`] for the app's webviews, and in the
/// tests a store of plain values, so a lease is tested with no window.
pub trait Home {
    /// The context the store keeps.
    type Context;

    /// Calls `f` with this thread's store.
    ///
    /// # Errors
    ///
    /// Answers the error of a store already gone, at the thread's end.
    fn with<R>(f: impl FnOnce(&RefCell<Store<Self::Context>>) -> R) -> Result<R, AccessError>;

    /// A new context for `data_directory`, `None` for the default.
    fn make(data_directory: Option<PathBuf>) -> Self::Context;
}

/// The loop thread's store of wry's contexts.
#[derive(Debug)]
pub struct Wry;

impl Home for Wry {
    type Context = wry::WebContext;

    fn with<R>(f: impl FnOnce(&RefCell<Store<wry::WebContext>>) -> R) -> Result<R, AccessError> {
        STORE.try_with(f)
    }

    /// wry's context with that directory (wry `src/web_context.rs:33-45`).
    fn make(data_directory: Option<PathBuf>) -> wry::WebContext {
        wry::WebContext::new(data_directory)
    }
}

/// The context of one data directory, lent to one webview's build.
///
/// Dropping it gives the context back to the store; a build that never
/// called [`built`](Self::built) also forgets its label, so a failed
/// build leaves no webview counted.
pub struct Lent<H: Home = Wry> {
    key: Key,
    label: String,
    context: Option<H::Context>,
    built: bool,
}

impl Lent {
    /// The context of `data_directory`, `None` for the default, for the
    /// webview `label` to build with: the store's, or a new one wry makes
    /// with that directory (wry `src/web_context.rs:33-45`).
    ///
    /// # Errors
    ///
    /// Answers a message when another build holds the context, or the
    /// store is in use.
    pub fn take(data_directory: Option<PathBuf>, label: &str) -> Result<Self, String> {
        Self::lend(data_directory, label)
    }
}

impl<H: Home> Lent<H> {
    /// The context of `data_directory` in `H`'s store, for the webview
    /// `label` to build with, as [`take`](Lent::take) answers it.
    ///
    /// # Errors
    ///
    /// Answers a message when another build holds the context, the store
    /// is in use, or the store is gone.
    fn lend(data_directory: Option<PathBuf>, label: &str) -> Result<Self, String> {
        let key = Key(data_directory);
        let context = H::with(|store| {
            store
                .try_borrow_mut()
                .map_err(|_| "the web context store is in use".to_string())?
                .lend(&key, label, H::make)
        })
        .map_err(|error| error.to_string())??;
        Ok(Self {
            key,
            label: label.to_string(),
            context: Some(context),
            built: false,
        })
    }

    /// The context, for `WebViewBuilder::new_with_web_context` to borrow
    /// for the length of the build.
    ///
    /// # Panics
    ///
    /// Never: the context is taken out only by `Drop`.
    pub const fn context(&mut self) -> &mut H::Context {
        self.context
            .as_mut()
            .expect("a lent context is held until drop")
    }

    /// Whether this webview registers `scheme` on its context: on Linux
    /// only the context's first webview does; elsewhere each webview has
    /// its own handlers, and every one does.
    #[must_use]
    pub fn registers(&self, scheme: &str) -> bool {
        !cfg!(any(
            target_os = "linux",
            target_os = "dragonfly",
            target_os = "freebsd",
            target_os = "netbsd",
            target_os = "openbsd"
        )) || H::with(|store| {
            store
                .try_borrow_mut()
                .is_ok_and(|mut store| store.registers(&self.key, scheme))
        })
        .unwrap_or(false)
    }

    /// Marks the webview built, and answers the lease the webview keeps
    /// for as long as it lives.
    #[must_use]
    pub fn built(mut self) -> Lease<H> {
        self.built = true;
        Lease {
            key: self.key.clone(),
            label: self.label.clone(),
            home: PhantomData,
        }
    }
}

impl<H: Home> Drop for Lent<H> {
    fn drop(&mut self) {
        let context = self.context.take();
        let _ = H::with(|store| {
            if let Ok(mut store) = store.try_borrow_mut() {
                if let Some(context) = context {
                    store.give_back(&self.key, context);
                }
                if !self.built {
                    store.release(&self.key, &self.label);
                }
            }
        });
    }
}

/// A built webview's place in its context, held beside the webview and
/// dropped after it, which forgets the webview in the store.
///
/// It is dropped only on the loop's thread: it lives in the webview's
/// `ThreadBound`, which forgets it anywhere else.
#[derive(Debug)]
pub struct Lease<H: Home = Wry> {
    key: Key,
    label: String,
    home: PhantomData<fn() -> H>,
}

impl<H: Home> Drop for Lease<H> {
    fn drop(&mut self) {
        // A store already gone, at the thread's end, or in use, which no
        // caller allows, keeps the label counted: only memory.
        let _ = H::with(|store| {
            if let Ok(mut store) = store.try_borrow_mut() {
                store.release(&self.key, &self.label);
            }
        });
    }
}

// SPDX-SnippetEnd

#[cfg(test)]
mod tests {
    use super::{Home, Key, Lent, Store};
    use std::cell::{Cell, RefCell};
    use std::collections::HashSet;
    use std::panic;
    use std::path::PathBuf;
    use std::thread::AccessError;

    /// A context that records the directory it was made for.
    #[derive(Debug, PartialEq, Eq)]
    struct Context(Option<PathBuf>);

    thread_local! {
        /// The test thread's store, which drops a context with its last
        /// webview, as macOS and Windows do. Each test runs on a thread of
        /// its own, so each starts with an empty store.
        static TEST_STORE: RefCell<Store<Context>> = RefCell::new(Store::new(false));
    }

    /// The test thread's store of plain contexts, for a [`Lent`] and a
    /// [`super::Lease`] with no window.
    #[derive(Debug)]
    struct Test;

    impl Home for Test {
        type Context = Context;

        fn with<R>(f: impl FnOnce(&RefCell<Store<Context>>) -> R) -> Result<R, AccessError> {
            TEST_STORE.try_with(f)
        }

        fn make(data_directory: Option<PathBuf>) -> Context {
            Context(data_directory)
        }
    }

    fn lend(label: &str) -> Lent<Test> {
        Lent::<Test>::lend(dir("a").0, label).expect("the context is free")
    }

    /// The labels the test store counts for directory "a", and whether it
    /// holds the context, or `None` when it has no entry.
    fn entry() -> Option<(HashSet<String>, bool)> {
        TEST_STORE.with_borrow(|store| {
            store
                .contexts
                .get(&dir("a"))
                .map(|entry| (entry.referenced_by_webviews.clone(), entry.inner.is_some()))
        })
    }

    fn labels(names: &[&str]) -> HashSet<String> {
        names.iter().map(ToString::to_string).collect()
    }

    fn dir(name: &str) -> Key {
        Key(Some(PathBuf::from(name)))
    }

    /// Lends `key`'s context to `label` and gives it straight back, as a
    /// build that succeeds does, counting each context made.
    fn build(store: &mut Store<Context>, key: &Key, label: &str, made: &Cell<usize>) {
        let context = store
            .lend(key, label, |directory| {
                made.set(made.get() + 1);
                Context(directory)
            })
            .expect("the context is free");
        assert_eq!(context.0, key.0, "the context is made for its directory");
        store.give_back(key, context);
    }

    #[test]
    fn webviews_naming_one_directory_share_one_context() {
        let mut store = Store::new(false);
        let made = Cell::new(0);
        build(&mut store, &dir("a"), "first", &made);
        build(&mut store, &dir("a"), "second", &made);
        assert_eq!(
            made.get(),
            1,
            "the second webview reuses the first's context"
        );

        build(&mut store, &dir("b"), "third", &made);
        build(&mut store, &Key(None), "fourth", &made);
        assert_eq!(
            made.get(),
            3,
            "another directory, and the default, each get their own"
        );
    }

    #[test]
    fn a_context_drops_with_its_last_webview_unless_contexts_are_kept() {
        for keeps in [false, true] {
            let mut store = Store::new(keeps);
            let made = Cell::new(0);
            build(&mut store, &dir("a"), "first", &made);
            build(&mut store, &dir("a"), "second", &made);

            store.release(&dir("a"), "first");
            assert!(
                store.contexts.contains_key(&dir("a")),
                "one webview still has it"
            );
            store.release(&dir("a"), "second");
            assert_eq!(
                store.contexts.contains_key(&dir("a")),
                keeps,
                "keeps: {keeps}"
            );

            build(&mut store, &dir("a"), "again", &made);
            assert_eq!(made.get(), if keeps { 1 } else { 2 }, "keeps: {keeps}");
        }
    }

    #[test]
    fn a_label_counts_once_and_an_unknown_one_is_ignored() {
        let mut store = Store::new(false);
        let made = Cell::new(0);
        build(&mut store, &dir("a"), "same", &made);
        build(&mut store, &dir("a"), "same", &made);
        store.release(&dir("a"), "other");
        store.release(&dir("b"), "same");
        assert!(store.contexts.contains_key(&dir("a")));
        store.release(&dir("a"), "same");
        assert!(
            !store.contexts.contains_key(&dir("a")),
            "a set of labels, as Tauri's"
        );
    }

    #[test]
    fn a_lent_context_is_refused_to_another_build_and_never_dropped() {
        let mut store = Store::new(false);
        let made = Cell::new(0);
        build(&mut store, &dir("a"), "first", &made);
        let context = store.lend(&dir("a"), "second", |_| Context(None)).unwrap();
        assert_eq!(
            store.lend(&dir("a"), "third", |_| Context(None)),
            Err("the web context is in use by another webview's build".to_string())
        );
        assert!(
            !store.contexts[&dir("a")]
                .referenced_by_webviews
                .contains("third"),
            "a refused build is not counted"
        );

        store.release(&dir("a"), "first");
        store.release(&dir("a"), "second");
        assert!(
            store.contexts.contains_key(&dir("a")),
            "the entry waits for its context"
        );
        store.give_back(&dir("a"), context);
        assert!(
            !store.contexts.contains_key(&dir("a")),
            "given back with no webview, it drops"
        );

        let mut kept = Store::new(true);
        build(&mut kept, &dir("a"), "first", &made);
        let context = kept.lend(&dir("a"), "second", |_| Context(None)).unwrap();
        kept.release(&dir("a"), "second");
        kept.give_back(&dir("a"), context);
        assert_eq!(
            kept.contexts[&dir("a")].inner,
            Some(Context(dir("a").0)),
            "a kept context stays"
        );
    }

    #[test]
    fn a_context_registers_each_scheme_once() {
        let mut store = Store::new(true);
        let made = Cell::new(0);
        assert!(
            !store.registers(&dir("a"), "tokra"),
            "no context, nothing to register on"
        );
        build(&mut store, &dir("a"), "first", &made);
        assert!(store.registers(&dir("a"), "tokra"));
        assert!(store.registers(&dir("a"), "ipc"));
        build(&mut store, &dir("a"), "second", &made);
        assert!(!store.registers(&dir("a"), "tokra"), "the context has it");
        assert!(!store.registers(&dir("a"), "ipc"));
        build(&mut store, &dir("b"), "third", &made);
        assert!(
            store.registers(&dir("b"), "tokra"),
            "another context registers its own"
        );
    }

    #[test]
    fn a_failed_build_forgets_its_label_and_gives_the_context_back() {
        let first = lend("first").built();
        let failed = lend("failed");
        assert_eq!(
            entry(),
            Some((labels(&["first", "failed"]), false)),
            "the build holds the context"
        );

        drop(failed);
        assert_eq!(
            entry(),
            Some((labels(&["first"]), true)),
            "a build never marked built is not counted"
        );
        drop(first);
    }

    #[test]
    fn a_built_lease_keeps_its_label_until_it_drops() {
        let lease = lend("built").built();
        assert_eq!(
            entry(),
            Some((labels(&["built"]), true)),
            "built, the label stays counted and the context is back"
        );

        drop(lease);
        assert_eq!(entry(), None, "its last webview gone, the context drops");
    }

    #[test]
    fn a_lent_context_is_given_back_even_while_a_build_unwinds() {
        let kept = lend("kept").built();
        let unwound = panic::catch_unwind(|| {
            let _lent = lend("panicking");
            panic!("the build panics");
        });
        assert!(unwound.is_err(), "the build panicked");
        assert_eq!(
            entry(),
            Some((labels(&["kept"]), true)),
            "the context is back, and the panicking build not counted"
        );
        assert_eq!(
            TEST_STORE.with_borrow(|store| store.contexts[&dir("a")]
                .inner
                .as_ref()
                .map(|c| c.0.clone())),
            Some(dir("a").0),
            "the same context, made for its directory"
        );
        drop(kept);
    }
}
