// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Cookies as they cross between Ruby and wry (plan 052, 052e-2).
//!
//! `Tokra::Cookie#native_fields` hands a cookie over as a Hash of plain
//! values, and `Tokra::Cookie.from_native` reads one back. Between the
//! Hash and wry's `cookie::Cookie` (the cookie crate 0.18.1, which wry
//! re-exports at `src/lib.rs:408`) sits [`Fields`], plain Rust values, so
//! the conversions both ways are pure functions with Rust tests, and Ruby
//! values exist only while one Hash is built or read.

use magnus::{prelude::*, Error, RArray, RHash, RString, Ruby, Value};
use wry::cookie::time::{Duration, OffsetDateTime};
use wry::cookie::{Cookie, CookieBuilder, Expiration, SameSite};

/// When a cookie expires, as `Tokra::Cookie#native_fields` writes it:
/// `"Session"`, or whole Unix seconds, as wry reads and writes an
/// expiration (`src/wkwebview/mod.rs:1003-1013`, `:1043-1051`;
/// `src/webview2/mod.rs:1538-1552`, `:1574-1584`;
/// `src/webkitgtk/mod.rs:955-964`, `:981-983`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Expires {
    /// The cookie crate's `Expiration::Session`.
    Session,
    /// The cookie crate's `Expiration::DateTime`, in Unix seconds.
    At(i64),
}

/// A cookie's fields as plain values, each optional one `None` until set,
/// as the cookie crate keeps them (`src/lib.rs:215-239`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Fields {
    pub name: String,
    pub value: String,
    pub expires: Option<Expires>,
    /// Whole seconds, as Max-Age counts them.
    pub max_age: Option<i64>,
    pub domain: Option<String>,
    pub path: Option<String>,
    pub secure: Option<bool>,
    pub http_only: Option<bool>,
    pub same_site: Option<SameSite>,
    pub partitioned: Option<bool>,
}

impl Fields {
    /// The fields of `cookie`, through the cookie crate's getters, so a
    /// domain has no leading dot (`src/lib.rs:777-785`).
    #[must_use]
    pub fn of(cookie: &Cookie<'_>) -> Self {
        Self {
            name: cookie.name().to_owned(),
            value: cookie.value().to_owned(),
            expires: cookie.expires().map(|expiration| match expiration {
                Expiration::Session => Expires::Session,
                Expiration::DateTime(moment) => Expires::At(moment.unix_timestamp()),
            }),
            max_age: cookie.max_age().map(Duration::whole_seconds),
            domain: cookie.domain().map(str::to_owned),
            path: cookie.path().map(str::to_owned),
            secure: cookie.secure(),
            http_only: cookie.http_only(),
            same_site: cookie.same_site(),
            partitioned: cookie.partitioned(),
        }
    }

    /// The cookie crate's cookie holding these fields, each unset one
    /// left unset.
    ///
    /// # Errors
    ///
    /// Returns the time crate's message for an expiration outside the
    /// years it can hold.
    pub fn into_cookie(self) -> Result<Cookie<'static>, String> {
        let mut builder = CookieBuilder::new(self.name, self.value);
        if let Some(expires) = self.expires {
            builder = builder.expires(match expires {
                Expires::Session => Expiration::Session,
                Expires::At(seconds) => Expiration::DateTime(
                    OffsetDateTime::from_unix_timestamp(seconds).map_err(|e| e.to_string())?,
                ),
            });
        }
        if let Some(seconds) = self.max_age {
            builder = builder.max_age(Duration::seconds(seconds));
        }
        if let Some(domain) = self.domain {
            builder = builder.domain(domain);
        }
        if let Some(path) = self.path {
            builder = builder.path(path);
        }
        if let Some(secure) = self.secure {
            builder = builder.secure(secure);
        }
        if let Some(http_only) = self.http_only {
            builder = builder.http_only(http_only);
        }
        if let Some(same_site) = self.same_site {
            builder = builder.same_site(same_site);
        }
        if let Some(partitioned) = self.partitioned {
            builder = builder.partitioned(partitioned);
        }
        Ok(builder.build())
    }
}

/// The name `Tokra::Cookie::SameSite` gives `policy`, the cookie crate's
/// `Display` (`src/same_site.rs:101-107`).
#[must_use]
pub const fn same_site_name(policy: SameSite) -> &'static str {
    match policy {
        SameSite::Strict => "Strict",
        SameSite::Lax => "Lax",
        SameSite::None => "None",
    }
}

/// The policy `Tokra::Cookie::SameSite` names `name`.
///
/// # Errors
///
/// Returns a message naming `name` when no policy has it.
pub fn same_site(name: &str) -> Result<SameSite, String> {
    match name {
        "Strict" => Ok(SameSite::Strict),
        "Lax" => Ok(SameSite::Lax),
        "None" => Ok(SameSite::None),
        other => Err(format!("unknown same site policy: {other}")),
    }
}

/// The expiration `Tokra::Cookie#native_fields` wrote as `value`.
///
/// # Errors
///
/// Returns a message for a String other than `"Session"`.
fn expires(value: Result<String, i64>) -> Result<Expires, String> {
    match value {
        Ok(name) if name == "Session" => Ok(Expires::Session),
        Ok(name) => Err(format!("unknown cookie expiration: {name}")),
        Err(seconds) => Ok(Expires::At(seconds)),
    }
}

/// Reads the cookie `Tokra::Cookie#native_fields` made into `hash`. A
/// flag is read by its truthiness, as magnus reads a `bool`; `Tokra::Cookie`
/// takes only `true`, `false`, or `nil` for one.
///
/// # Errors
///
/// Returns `KeyError` without a name or value, `TypeError` for a field of
/// the wrong type, `ArgumentError` for an expiration or a same-site policy
/// no variant names, and `RangeError` for an Integer no `i64` holds or an
/// expiration the time crate cannot hold.
pub fn cookie_from_hash(ruby: &Ruby, hash: RHash) -> Result<Cookie<'static>, Error> {
    let key = |name: &str| ruby.to_symbol(name);
    let argument = |message: String| Error::new(ruby.exception_arg_error(), message);
    let expiration: Option<Value> = hash.lookup(key("expires"))?;
    let expiration = expiration
        .map(|value| {
            RString::from_value(value).map_or_else(
                || i64::try_convert(value).map(Err),
                |name| name.to_string().map(Ok),
            )
        })
        .transpose()?
        .map(expires)
        .transpose()
        .map_err(argument)?;
    let policy: Option<String> = hash.lookup(key("same_site"))?;
    let fields = Fields {
        name: hash.fetch(key("name"))?,
        value: hash.fetch(key("value"))?,
        expires: expiration,
        max_age: hash.lookup(key("max_age"))?,
        domain: hash.lookup(key("domain"))?,
        path: hash.lookup(key("path"))?,
        secure: hash.lookup(key("secure"))?,
        http_only: hash.lookup(key("http_only"))?,
        same_site: policy
            .map(|name| same_site(&name))
            .transpose()
            .map_err(argument)?,
        partitioned: hash.lookup(key("partitioned"))?,
    };
    fields
        .into_cookie()
        .map_err(|message| Error::new(ruby.exception_range_error(), message))
}

/// `cookies` as an Array of the Hashes `Tokra::Cookie.from_native` reads.
/// Each Hash goes into the Array as it is built, so no Ruby value waits
/// in a Rust collection while Ruby allocates.
///
/// # Errors
///
/// Returns an error if Ruby fails to build a Hash or the Array.
pub fn cookies_to_array(ruby: &Ruby, cookies: &[Cookie<'static>]) -> Result<RArray, Error> {
    let array = ruby.ary_new_capa(cookies.len());
    for cookie in cookies {
        array.push(fields_to_hash(ruby, Fields::of(cookie))?)?;
    }
    Ok(array)
}

/// `fields` as the Hash `Tokra::Cookie.from_native` reads.
fn fields_to_hash(ruby: &Ruby, fields: Fields) -> Result<RHash, Error> {
    let hash = ruby.hash_new();
    let key = |name: &str| ruby.to_symbol(name);
    hash.aset(key("name"), fields.name)?;
    hash.aset(key("value"), fields.value)?;
    match fields.expires {
        None => hash.aset(key("expires"), ruby.qnil())?,
        Some(Expires::Session) => hash.aset(key("expires"), "Session")?,
        Some(Expires::At(seconds)) => hash.aset(key("expires"), seconds)?,
    }
    hash.aset(key("max_age"), fields.max_age)?;
    hash.aset(key("domain"), fields.domain)?;
    hash.aset(key("path"), fields.path)?;
    hash.aset(key("secure"), fields.secure)?;
    hash.aset(key("http_only"), fields.http_only)?;
    hash.aset(key("same_site"), fields.same_site.map(same_site_name))?;
    hash.aset(key("partitioned"), fields.partitioned)?;
    Ok(hash)
}

#[cfg(test)]
mod tests {
    use super::{expires, same_site, same_site_name, Expires, Fields};
    use wry::cookie::time::{Duration, OffsetDateTime};
    use wry::cookie::{Cookie, CookieBuilder, Expiration, SameSite};

    fn fields() -> Fields {
        Fields {
            name: "n".into(),
            value: "v".into(),
            expires: Some(Expires::At(1_800_000_000)),
            max_age: Some(60),
            domain: Some("localhost".into()),
            path: Some("/a".into()),
            secure: Some(true),
            http_only: Some(false),
            same_site: Some(SameSite::Strict),
            partitioned: Some(true),
        }
    }

    #[test]
    fn every_field_reaches_the_cookie_and_comes_back() {
        let cookie = fields().into_cookie().unwrap();

        assert_eq!(
            cookie
                .expires_datetime()
                .map(OffsetDateTime::unix_timestamp),
            Some(1_800_000_000)
        );
        assert_eq!(cookie.max_age(), Some(Duration::seconds(60)));
        assert_eq!(cookie.same_site(), Some(SameSite::Strict));
        assert_eq!(cookie.partitioned(), Some(true));
        assert_eq!(cookie.http_only(), Some(false));
        assert_eq!(Fields::of(&cookie), fields());
    }

    #[test]
    fn an_unset_field_stays_unset() {
        let bare = Fields {
            name: "n".into(),
            value: "v".into(),
            expires: None,
            max_age: None,
            domain: None,
            path: None,
            secure: None,
            http_only: None,
            same_site: None,
            partitioned: None,
        };
        let cookie = bare.clone().into_cookie().unwrap();

        assert_eq!(cookie.to_string(), "n=v");
        assert_eq!(Fields::of(&cookie), bare);
    }

    #[test]
    fn a_session_cookie_and_a_dotted_domain_read_as_the_cookie_crate_answers_them() {
        let cookie = CookieBuilder::new("n", "v")
            .expires(Expiration::Session)
            .domain(".tauri.app")
            .build();
        let read = Fields::of(&cookie);

        assert_eq!(read.expires, Some(Expires::Session));
        assert_eq!(read.domain.as_deref(), Some("tauri.app"));
    }

    #[test]
    fn an_expiration_the_time_crate_cannot_hold_is_refused() {
        let far = Fields {
            expires: Some(Expires::At(i64::MAX)),
            ..fields()
        };

        assert!(far.into_cookie().is_err());
    }

    #[test]
    fn each_policy_and_expiration_name_reads_as_its_variant() {
        for policy in [SameSite::Strict, SameSite::Lax, SameSite::None] {
            assert_eq!(same_site(same_site_name(policy)), Ok(policy));
            assert_eq!(same_site_name(policy), policy.to_string());
        }
        assert_eq!(
            same_site("Loose"),
            Err("unknown same site policy: Loose".into())
        );
        assert_eq!(expires(Ok("Session".into())), Ok(Expires::Session));
        assert_eq!(expires(Err(5)), Ok(Expires::At(5)));
        assert!(expires(Ok("Forever".into())).is_err());
        assert_eq!(Cookie::parse("a=b").unwrap().expires(), None);
    }
}
