// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! The config fixture generator (plan 054).
//!
//! Tokra's config loader and `Ipc::Serde` port Tauri's config reading by
//! hand. This program asks Tauri's own crates, at the versions Tauri's
//! lock pins, what they make of each case under `test/fixtures/config`,
//! and prints one JSON line per answer. `rake config:fixtures` builds it
//! twice (without and with the `formats` feature), runs it, and writes
//! the lines beside each case as `expected.jsonl`, the answer key Tokra's
//! tests read.
//!
//! Two kinds of case:
//!
//! - `from_value/cases.jsonl`: one JSON object per line, naming a
//!   tauri-utils config type and a JSON value. The answer is
//!   `serde_json::from_value` into that type: its error's `Display`, or
//!   the value serialized back (or only the JSON pointers in `probes`).
//! - `cases/<name>/`: a directory of config files under Tokra's names,
//!   with an optional `path.txt` (the path given to the macro, relative to
//!   the case) and `probes.txt` (JSON pointers, one per line). The answer
//!   is the macro's path check and `tauri_codegen::get_config` for each
//!   desktop target, run on a copy of the case under Tauri's names.
//!
//! Every string in an answer has the case's directory as `{dir}` (with
//! `{dir}/` for the directory and a separator), and Tauri's brand as
//! `{brand}` or `{Brand}` where it names a config file (`{brand}.conf.json`,
//! `{Brand}.toml`, "{Brand} config file") and in the default window title
//! (`{Brand} App`), so a Tokra test fills in its own directory and names.
//!
//! A config case's answer has `check` when `path.txt` gives a path: `null`
//! when the macro's check passes, its message when it fails. With no
//! `path.txt` the macro checks nothing and `check` is absent. Then come
//! `error`, `get_config`'s error, or `probes`, the values at the case's
//! pointers in the config serialized back.

use serde::{de::DeserializeOwned, Serialize};
use serde_json::{json, Map, Value};
use std::{
    env, fs,
    path::{Path, PathBuf, MAIN_SEPARATOR},
};
use tauri_utils::{
    config::{
        parse::does_supported_file_name_exist, AppConfig, AssetProtocolConfig, FsScope,
        PatternKind, PreventOverflowConfig, PreventOverflowMargin, RunnerConfig, TrayIconConfig,
    },
    platform::Target,
};

/// Which of the two builds this is, recorded in every answer.
const BUILD: &str = if cfg!(feature = "formats") {
    "formats"
} else {
    "json"
};

/// The desktop targets, as `TAURI_ENV_TARGET_TRIPLE` names them.
const TARGETS: [&str; 3] = [
    "aarch64-apple-darwin",
    "x86_64-pc-windows-msvc",
    "x86_64-unknown-linux-gnu",
];

/// The files a case may hold that are not config files.
const CASE_FILES: [&str; 3] = ["expected.jsonl", "path.txt", "probes.txt"];

fn main() {
    let root = env::args_os()
        .nth(1)
        .map(PathBuf::from)
        .expect("usage: tokra-config-fixtures <test/fixtures/config>");
    // get_config merges TAURI_CONFIG over every case (tauri-codegen
    // lib.rs:83-87); no answer may depend on the shell it ran in.
    env::remove_var("TAURI_CONFIG");
    // The from_value answers do not depend on the formats, so only the
    // JSON build gives them.
    if BUILD == "json" {
        from_value_cases(&root.join("from_value"));
    }
    let cases = root.join("cases");
    if cases.is_dir() {
        for case in sorted_entries(&cases) {
            config_case(&root, &case);
        }
    }
}

fn from_value_cases(dir: &Path) {
    let cases = fs::read_to_string(dir.join("cases.jsonl")).expect("from_value/cases.jsonl");
    for line in cases.lines().filter(|line| !line.trim().is_empty()) {
        let case: Value = serde_json::from_str(line).expect("a JSON object per line");
        let name = case["name"].as_str().expect("a case name");
        let kind = case["type"].as_str().expect("a type name");
        let value = case["value"].clone();
        let result = match kind {
            "AppConfig" => read::<AppConfig>(value),
            "AssetProtocolConfig" => read::<AssetProtocolConfig>(value),
            "FsScope" => read::<FsScope>(value),
            "PatternKind" => read::<PatternKind>(value),
            "PreventOverflowConfig" => read::<PreventOverflowConfig>(value),
            "PreventOverflowMargin" => read::<PreventOverflowMargin>(value),
            "RunnerConfig" => read::<RunnerConfig>(value),
            "TrayIconConfig" => read::<TrayIconConfig>(value),
            other => panic!("{name}: no type {other} in the generator"),
        };
        let mut answer =
            json!({ "case": "from_value", "name": name, "build": BUILD, "type": kind });
        match result {
            Ok(read) => answer["ok"] = probed(&read, case.get("probes")),
            Err(error) => answer["error"] = Value::String(error.to_string()),
        }
        println!("{answer}");
    }
}

/// `value` read into `T` as Tauri's codegen reads its config
/// (`serde_json::from_value`, tauri-codegen lib.rs:92), then written back.
fn read<T: DeserializeOwned + Serialize>(value: Value) -> Result<Value, serde_json::Error> {
    serde_json::from_value::<T>(value).map(|read| serde_json::to_value(read).expect("serializes"))
}

/// The whole value, or only the JSON pointers `probes` names.
fn probed(value: &Value, probes: Option<&Value>) -> Value {
    let Some(probes) = probes.and_then(Value::as_array) else {
        return value.clone();
    };
    let mut found = Map::new();
    for probe in probes.iter().filter_map(Value::as_str) {
        let at = value.pointer(probe).cloned().unwrap_or(Value::Null);
        found.insert(probe.to_owned(), at);
    }
    Value::Object(found)
}

fn config_case(root: &Path, case: &Path) {
    let name = case
        .strip_prefix(root)
        .expect("under the root")
        .to_string_lossy()
        .replace('\\', "/");
    let given = fs::read_to_string(case.join("path.txt"))
        .ok()
        .map(|path| path.trim().to_owned());
    let probes: Vec<String> = fs::read_to_string(case.join("probes.txt"))
        .unwrap_or_default()
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(ToOwned::to_owned)
        .collect();
    let cwd = env::current_dir().expect("a working directory");
    for target in TARGETS {
        let dir = scratch_dir();
        copy_under_tauri_names(case, &dir, &CASE_FILES);
        let path = dir.join(
            given
                .as_deref()
                .map_or("tauri.conf.json".to_owned(), tauri_name),
        );
        let mut answer = json!({ "case": name, "build": BUILD, "target": target, "path": given });
        let checked = given
            .is_some()
            .then(|| check(Target::from_triple(target), &path));
        if let Some(check) = &checked {
            answer["check"] = check.clone().err().map_or(Value::Null, Value::String);
        }
        if checked.is_none_or(|check| check.is_ok()) {
            env::set_var("TAURI_ENV_TARGET_TRIPLE", target);
            match tauri_codegen::get_config(&path) {
                Ok((config, _)) => {
                    let config = serde_json::to_value(&config).expect("serializes");
                    let mut found = Map::new();
                    for probe in &probes {
                        found.insert(
                            probe.clone(),
                            config.pointer(probe).cloned().unwrap_or(Value::Null),
                        );
                    }
                    answer["probes"] = Value::Object(found);
                }
                Err(error) => answer["error"] = Value::String(error.to_string()),
            }
            // get_config returns a schema error before it moves the working
            // directory back (tauri-codegen lib.rs:89-96).
            env::set_current_dir(&cwd).expect("the working directory back");
        }
        println!("{}", placeholders(&answer, &dir));
        fs::remove_dir_all(&dir).expect("the scratch directory removed");
    }
}

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: tauri-macros src/context.rs:45-55 at vendor/tauri 9f0306fbc

/// The macro's check of a path it was given, and its compile error.
fn check(target: Target, path: &Path) -> Result<(), String> {
    if does_supported_file_name_exist(target, path) {
        Ok(())
    } else {
        Err(format!(
            "no file at path {} exists, expected tauri config file",
            path.display()
        ))
    }
}

// SPDX-SnippetEnd

/// An empty directory for one run, by its canonical path, so the path in
/// a message is the one the placeholder replaces.
fn scratch_dir() -> PathBuf {
    let dir = env::temp_dir().join(format!("tokra-config-fixtures-{}", std::process::id()));
    if dir.exists() {
        fs::remove_dir_all(&dir).expect("the old scratch directory removed");
    }
    fs::create_dir_all(&dir).expect("a scratch directory");
    dir.canonicalize().expect("a canonical scratch directory")
}

/// Copies `from` into `to` under Tauri's names, leaving out the files
/// named in `skip`.
fn copy_under_tauri_names(from: &Path, to: &Path, skip: &[&str]) {
    for entry in sorted_entries(from) {
        let file_name = entry
            .file_name()
            .expect("a file name")
            .to_string_lossy()
            .into_owned();
        if skip.contains(&file_name.as_str()) {
            continue;
        }
        let target = to.join(tauri_name(&file_name));
        if entry.is_dir() {
            fs::create_dir_all(&target).expect("a directory");
            copy_under_tauri_names(&entry, &target, &[]);
        } else {
            fs::copy(&entry, &target).expect("a copied file");
        }
    }
}

/// A Tokra config file name under Tauri's brand (ADR 014 §3); any other
/// name as it is. A path's last component alone is renamed.
fn tauri_name(name: &str) -> String {
    let (dir, file) = name
        .rsplit_once('/')
        .map_or(("", name), |(dir, file)| (dir, file));
    let renamed = if is_config_name(file, "tokra.", "Tokra.") {
        file.replacen("tokra.", "tauri.", 1)
            .replacen("Tokra.", "Tauri.", 1)
    } else {
        file.to_owned()
    };
    if dir.is_empty() {
        renamed
    } else {
        format!("{dir}/{renamed}")
    }
}

/// Whether `file` is one of the config file names (parse.rs:30-76) under
/// the brand prefixes given.
fn is_config_name(file: &str, lower: &str, upper: &str) -> bool {
    let platforms = ["", "macos.", "windows.", "linux.", "android.", "ios."];
    platforms.iter().any(|platform| {
        file == format!("{lower}{platform}conf.json")
            || file == format!("{lower}{platform}conf.json5")
            || file == format!("{upper}{platform}toml")
    })
}

/// `answer` with every string's directory and brand as placeholders.
fn placeholders(answer: &Value, dir: &Path) -> Value {
    match answer {
        // The window's default title (config.rs:2061-2063), which ADR 014 §4
        // renames by the brand rule, as a whole value only. A case whose
        // own value is the string "Tauri App" reads it back as "{Brand} App"
        // too, so no case should hold one.
        Value::String(text) if text == "Tauri App" => Value::String("{Brand} App".to_owned()),
        Value::String(text) => Value::String(placeholder_text(text, dir)),
        Value::Array(items) => {
            Value::Array(items.iter().map(|item| placeholders(item, dir)).collect())
        }
        Value::Object(map) => Value::Object(
            map.iter()
                .map(|(key, value)| (key.clone(), placeholders(value, dir)))
                .collect(),
        ),
        other => other.clone(),
    }
}

fn placeholder_text(text: &str, dir: &Path) -> String {
    let dir = dir.display().to_string();
    let mut text = text
        .replace(&format!("{dir}{MAIN_SEPARATOR}"), "{dir}/")
        .replace(&dir, "{dir}");
    // A config file name holds only letters, digits, and dots, so any
    // other character ends a word, and a dot ending a sentence is not part
    // of the name.
    let words: Vec<String> = text
        .split_inclusive(|c: char| !is_name_char(c))
        .map(|word| {
            let bare = word
                .trim_end_matches(|c: char| !is_name_char(c))
                .trim_end_matches('.');
            if is_config_name(bare, "tauri.", "Tauri.") {
                word.replacen("tauri.", "{brand}.", 1)
                    .replacen("Tauri.", "{Brand}.", 1)
            } else {
                word.to_owned()
            }
        })
        .collect();
    text = words.concat();
    text.replace("Tauri config file", "{Brand} config file")
        .replace("tauri config file", "{brand} config file")
}

/// Whether `c` can appear in a config file name (parse.rs:30-76).
fn is_name_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '.'
}

fn sorted_entries(dir: &Path) -> Vec<PathBuf> {
    let mut entries: Vec<PathBuf> = fs::read_dir(dir)
        .expect("a readable directory")
        .map(|entry| entry.expect("an entry").path())
        .collect();
    entries.sort();
    entries
}
