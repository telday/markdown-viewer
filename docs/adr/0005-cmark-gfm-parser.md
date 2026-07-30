---
status: accepted
---

# Parse Markdown with cmark-gfm directly, not swift-markdown

Markdown is converted to HTML by calling `cmark-gfm` (GitHub's own reference
GFM implementation, in C) directly, via Apple's SPM packaging of it
(`swiftlang/swift-cmark`, `gfm` branch), rather than using `swift-markdown`
(Apple's Swift-native AST package, itself built on the same underlying
library).

The two candidates parse identically (same C library), but `swift-markdown`
exposes a Swift AST with no built-in HTML renderer — using it would mean
writing and maintaining a Swift-side AST-to-HTML walker for a job `cmark-gfm`
already does directly via `cmark_render_html`. Since all presentation
enhancement (copy buttons, syntax highlighting, and later Mermaid/PlantUML —
see ADR 0001) already happens in a JS layer operating on the rendered DOM,
there's no use for a Swift-side AST here today.

C interop risk was checked empirically before committing to this (a scratch
SPM package depending on `swift-cmark`'s `gfm` branch, registering GFM
extensions, and rendering real GFM output — tables, task lists,
strikethrough, autolink — all worked with no code-generation step needed at
build time, since the generated parser sources are already committed
upstream).

## Considered options

- **swift-markdown** — rejected. Would add a redundant rendering layer for
  no current benefit, since presentation logic lives in JS, not Swift.

## Consequences

- Any future need for Swift-side document manipulation (e.g. true in-place
  WYSIWYG editing, which ADR 0001 explicitly deferred rather than ruled out)
  would require introducing an AST layer at that point — this decision
  doesn't provide one today. If that need materializes, revisit in favor of
  `swift-markdown` or a hand-built AST walker over `cmark-gfm`'s node tree.
