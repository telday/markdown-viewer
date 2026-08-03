# Testing methodology

How to test changes in this repo — especially rendering/styling, where the
output is HTML+CSS interpreted by WebKit. This complements the
[Definition of Done](definition-of-done.md), which lists *which gates run*; this
doc is about *what to test and where*.

## The one principle: test the seam you own, not your dependencies

Before writing a test, ask: **is this asserting our behavior, or re-asserting a
dependency's?**

- cmark-gfm already tests that `# x` becomes `<h1>x</h1>`. GitHub's
  `github-markdown-css` already tests that `.markdown-body h1` gets a bottom
  border of some specific width and color.
- Re-encoding those facts as our `#expect`s adds no signal and *pins us to the
  dependency* — every upstream bump breaks our suite for no reason.

What is **ours** to test is the **seam**: the wiring between the pieces, and the
integration decisions only this app makes. That's where our bugs actually live,
and no upstream test covers it. Concretely for the render pipeline:

- Does our document wrapper apply the class the stylesheet's selectors target?
  (Drift here silently unstyles the *entire* document — and every
  string-assertion test still passes.)
- Do the stylesheet's selectors match the DOM **our** renderer actually emits?
  (See the worked example below — they didn't, at first.)
- Does our dark-mode plumbing — the `color-scheme` meta tag + WKWebView
  appearance — actually flip the rendering?

## The three tiers of rendering tests

From cheap-and-shallow to expensive-and-thorough. Use the shallowest tier that
gives real signal for what you changed.

1. **String / structural assertions** — assert the generated HTML *contains* the
   expected markup, class, or `<style>` block. Fast, no engine, no UI
   dependency, so these live in the **logic layer** (`FoliumTests`) and count
   toward coverage. Good for: "the fragment was wrapped," "the sheet is present."
   Blind spot: proves nothing *applies* — a typo'd selector or a class mismatch
   passes happily.

2. **Computed-style assertions in a real engine** *(the default for "does it
   actually style?")* — load the HTML in a `WKWebView`, then read
   `getComputedStyle(...)` on real elements and assert the *resolved* result.
   Tests that the CSS cascades onto the real DOM. Robust: no baseline images to
   babysit across OS/font drift. Needs WebKit, so these are **integration tests**
   (`FoliumIntegrationTests`), outside the logic-coverage gate. **Assert the
   seam, not the value:** check that a heading has *a* border (wiring works), not
   that it is `1px` (upstream's value). See the pattern below.

3. **Visual / screenshot regression** — render, screenshot, diff against a
   committed baseline PNG. Catches layout/spacing regressions the other tiers
   can't. But baselines are brittle across macOS/Xcode/font/Retina changes — and
   this repo selects the newest Xcode by glob in CI, so baselines *will* drift.
   **Not currently used.** Reach for it only when layout regressions become a
   real, recurring problem, and accept the baseline-maintenance cost when you do.

## Where each kind of test goes

| Test kind | Target | Coverage-gated? | Why |
| --------- | ------ | --------------- | --- |
| Pure logic (parsing, decoding, HTML assembly, string checks) | `FoliumTests` (unit) | **Yes** (≥97%) | No SwiftUI/AppKit/WebKit dependency; must be reachable. |
| Real-engine rendering (computed style, appearance) | `FoliumIntegrationTests` | No | Needs a live `WKWebView`; can't run under unit tests. |
| End-to-end pipeline (file → render → wrap) | `FoliumIntegrationTests` | No | Exercises the whole path against a real fixture. |

This mirrors the coverage rule: real logic belongs in plain, testable types
(e.g. `MarkdownPage` assembles the document with no WebKit dependency, so its
wiring is unit-tested), while anything that needs a rendering engine is an
integration test and is exempt from the coverage bar.

## Pattern: computed-style tests in WKWebView

`StyleRenderingTests` is the reference implementation. The shape:

1. Build the page the app builds — `MarkdownPage.html(bodyHTML: renderHTML(...))`
   — so you test the **real** DOM, not a hand-written fixture.
2. Load it into a `WKWebView` and `await` navigation completion (bridge
   `WKNavigationDelegate.didFinish` to a `CheckedContinuation`).
3. `evaluateJavaScript("getComputedStyle(document.querySelector(...))
   .getPropertyValue(...)")` and assert the resolved value.
4. For appearance: set `webView.appearance = NSAppearance(named: .aqua)` vs
   `.darkAqua` **before** loading, and assert the canvas background *differs* —
   not the exact hex.

These tests are `@MainActor` (WebKit is main-thread-only) and run in well under a
second each.

### Make sure the test has teeth

A rendering test that can't fail is worse than none. After writing one,
**temporarily break the thing it guards** (mutate the selector, drop the class)
and confirm it goes red, then revert. If it stays green, it's asserting the wrong
layer — usually a default value the browser would return regardless.

## Worked example: the dead-selector bug (why tier 1 isn't enough)

While adding the GitHub stylesheet (issue #3), the first draft styled task lists
with `li.task-list-item` / `ul.contains-task-list` — the classes **github.com**
adds server-side. But our cmark-gfm output emits **class-less**
`<li><input type="checkbox">`, so those selectors matched nothing: task lists
would have rendered with default bullets, unlike GitHub. Every string-assertion
test passed, because the CSS *was* present in the document — it just didn't
apply.

A tier-2 computed-style test caught it: `getComputedStyle(taskItem)
.listStyleType` was `"disc"`, not `"none"`. The fix was to target the DOM we
actually emit — `li:has(> input[type="checkbox"])` — and the same test now guards
against regressing it. This is the whole argument for testing the seam rather
than the stylesheet's values: the bug lived exactly in the gap between "our
renderer's output" and "the stylesheet's assumptions," which is ours alone.

## Checklist for a rendering/styling change

- [ ] Logic (HTML assembly, decoding, string shape) has **unit** tests in
      `FoliumTests` and keeps coverage ≥97%.
- [ ] If the change affects how something *renders*, a **computed-style**
      integration test asserts it applies to the real DOM — the seam, not the
      upstream value.
- [ ] Appearance-sensitive changes assert light **and** dark differ.
- [ ] Every new rendering test has been shown to fail when its target is broken.
- [ ] You did **not** re-assert cmark-gfm's HTML values or GitHub's CSS values.
- [ ] `make check` is green.
