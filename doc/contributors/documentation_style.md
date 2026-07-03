<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Documentation Style Guide

This project follows a strict and specific documentation style designed to be helpful, readable, and consistent. It combines the structural clarity of Christopher Alexander's Pattern Language with the prose style of William Zinsser's *On Writing Well* and the usability of the U.S. Federal Plain Language Guidelines.

**All agents and contributors must adhere to these standards.**

## 1. Core Philosophy

*   **Context, Problem, Solution (Alexandrian Form):** Do not just say *what* a class does. Explain *why* it exists. Start with the context, state the problem (the pain point without this tool), and then present the class as the solution.
*   **Prose Style (Zinsser/Klinkenborg):** Use short, punchy sentences. Use active voice. Cut unnecessary words. Avoid "allow," "enable," "provide," "support," "functionality," and "capability" where possible. Weak verbs hide the action. Strong verbs drive the sentence.
*   **User-Centric (Plain Language):** Speak directly to the user ("You"). Don't abstract them away ("The developer"). Focus on their goals and how this tool helps them achieve those goals.
*   **Tone (Supportive and Authoritative, not Hostile or Prescriptive):** Avoid "must," "requires," "need to," or "mandatory." These words sound bossy. Treat the user as a capable peer. Instead of "You must do X," use imperative "Do X" or cause-and-effect "X ensures Y."

## 2. Tauri Parity in Documentation

Tokra is a 1:1 port of Tauri. Code parity is mechanical: names, structures, and error messages map one-to-one, and tests verify the mapping. Documentation parity is not mechanical, so it works in two tiers.

### Behavioral Contracts: Port Faithfully

Every behavioral claim, caveat, and edge case in Tauri's docs has a counterpart truth. State it. A parity reviewer should be able to read the rustdoc and the RDoc side by side and find no contradiction.

Some Tauri doc sentences *define* semantics rather than describe them. Port those near-verbatim — paraphrasing a specification risks changing it. For example, Tauri's `PluginStore::extend_api` doc reads "The message is not handled when the plugin exists **and** the command does not." That sentence is the contract; keep its substance intact.

### Explanatory Prose: Write for Rubyists

Everything else follows this guide's voice, not Tauri's. Do not port sentences about Rust machinery — ownership, `Arc<Mutex<...>>`, trait bounds, lifetimes, Cargo features. Translate the fact and drop the machinery: "requires `Send + Sync`" becomes a statement about Ractor-shareability, or nothing at all.

Tauri's doc coverage is a floor, not a ceiling. Where Tauri has a one-line comment (their prose lives on a docs site Tokra doesn't have), write the full Context-Problem-Solution narrative anyway.

### Deliberately Unimplemented APIs

When Tokra declines to port something (raising `NotImplementedError` or rejecting an invoke), the docs say *why*, point to the alternative, and leave the door open when Tauri itself supports the feature. See `level_for` and `with_colors` in the log plugin.

### Citations

When a class or method mirrors Tauri source, say so and cite the file (and lines when they matter):

```ruby
# Routes an invoke to the named plugin's extend_api hook.
#
# ... matching Tauri's PluginStore#extend_api (plugin.rs).
```

These citations are for contributors verifying parity. Keep them short, place them after the user-facing prose, and never let them replace the Context-Problem-Solution narrative. A citation answers "where did this shape come from?" — it does not answer "why would I call this?"

Files adapted from Tauri already carry SPDX snippet markers; doc sentences ported from Tauri's rustdoc fall under the same markers.

## 3. Class Documentation

Every public class must begin with a **Context-Problem-Solution** narrative.

### Structure

1.  **Summary Line:** A single line explaining the class's role.
2.  **Context (Narrative):** A short paragraph establishing the domain or situation.
3.  **Problem (Narrative):** A sentence or two identifying the specific difficulty, complexity, or "pain" the user faces in this context without the class.
4.  **Solution (Narrative):** A sentence explaining how this class solves that problem, often starting with "This class..." or "Use it to...".
5.  **Usage (Narrative):** A concrete "Use it to..." sentence listing common applications.
6.  **Example:** A comprehensive, copy-pasteable code example using `=== Examples`. Provide **multiple** examples to cover different use cases (e.g., basic usage vs. advanced configuration).

### Example

**Bad (Generic/Descriptive):**
<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2025 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
```ruby
# A class for managing resources.
# It allows the user to store objects by integer ID.
# Supports adding, fetching, and closing.
```
<!-- SPDX-SnippetEnd -->

**Good (Alexandrian/Zinsser/Plain Language):**
<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2025 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
```ruby
# Stores managed objects behind integer handles.
#
# Frontend JavaScript cannot hold Ruby objects. Serializing large
# binary data through JSON on every call is slow and wasteful.
#
# This table stores the object once and hands the frontend a small
# integer "resource ID" (rid) to pass back later.
#
# Use it to share images, file handles, or other heavy objects with
# the WebView.
```
<!-- SPDX-SnippetEnd -->

## 4. Method and Attribute Documentation

### Prose Style

*   **Attributes:** Use concise noun phrases. Avoid "This attribute returns..." or "Getter for...".
    *   *Bad:* "This is the label of the webview."
    *   *Good:* "The unique label identifying this webview."
*   **Methods:** Use active, third-person present tense verbs.
    *   *Bad:* "Will calculate the total."
    *   *Good:* "Calculates the total."
*   **Context:** For complex methods, you may use a condensed version of the Context-Problem-Solution pattern, but keep it brief.

### Syntax Standards

*   **Examples:** All public methods must include at least one usage example. Use `=== Example`.
*   **Attributes:** Use `attr_reader` with documentation comments immediately preceding them.
*   **Parameters:** Use strict RDoc definition lists `[name] description` for parameters in the `initialize` method.
*   **Formatting:** Use `+code+` for simple identifiers (e.g., `+nil+`, `+rid+`) and `<tt>` tags for anything with spaces or punctuation (e.g., `<tt>plugin:image|new</tt>`).
    *   Do **not** use backticks (\`) or markdown-style links `[text](url)`. RDoc does not render them correctly in all contexts.
    *   Do **not** use smart quotes.

### Example

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-FileCopyrightText: 2025 Kerrick Long
  SPDX-License-Identifier: MIT-0
-->
```ruby
  # The unique label identifying this webview.
  attr_reader :label

  # Creates a new Webview wrapper.
  #
  # [label] String, unique among webviews (e.g., <tt>"main"</tt>).
  # [native] Native::WebView handle from wry.
  def initialize(label:, native:)
    super
  end
```
<!-- SPDX-SnippetEnd -->

## 5. RDoc Specifics

*   **No Endless Methods:** Do **not** use Ruby 3.0+ endless method definitions (`def foo = bar`). RDoc currently has a bug where it fails to correctly parse the end of the method, causing subsequent methods to lose their visibility and comment attachment (they show up as undocumented public methods in `rake rdoc:coverage`). Always use standard `def ... end` blocks.
*   **No YARD:** Do not use `@param`, `@return`, or other YARD tags. Use standard RDoc formats.
*   **Directives:** Use `:nodoc:` for private or internal methods that should not appear in the API docs.
*   **Headings:** Use `===` for section headers like `=== Examples`.
*   **SPDX in Ruby:** Wrap SPDX headers in `#--` / `#++` so they stay out of the rendered docs (per AGENTS.md).

## 6. Checklist for Agents

Before finalizing documentation, ask:
1.  Did I explain the *problem* this code solves?
2.  Are my sentences short and active? (Did I remove "allows the user to"?)
3.  Is the code example valid and copy-pasteable?
4.  Did I cite the Tauri source this mirrors?
5.  Did I preserve every behavioral claim and caveat from the Tauri docs?
6.  Did I translate or drop Rust machinery instead of porting it?
7.  Did I use `+code+` or `<tt>` for symbols and code values?
8.  Did I document every attribute and parameter?
