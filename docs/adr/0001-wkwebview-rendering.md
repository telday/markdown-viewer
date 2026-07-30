---
status: accepted
---

# Render Markdown via WKWebView, not native AppKit/SwiftUI

The core renderer displays Markdown as HTML/CSS/JS inside a `WKWebView`, rather than
building a native view tree (`NSAttributedString` / hand-built SwiftUI views) from a
parsed Markdown AST.

We built and compared a throwaway prototype of both (`prototypes/rendering-approach-poc/`,
see git history — dropped from `main` once the decision was made) against the same
sample document, with real vim-style `j`/`k` scroll handling wired into each. The
WKWebView variant looked better and required substantially less hand-built styling
to approach GitHub's code block fidelity, and it's the only realistic path to two
planned future features: Mermaid/PlantUML diagram rendering (both are JS libraries
that render to SVG in a DOM — trivial to embed in a web view, no native Swift
equivalent exists) and syntax highlighting (can reuse existing JS highlighters
instead of hand-rolling one).

## Considered options

- **Native AppKit/SwiftUI rendering** — rejected. Feels more "Mac native" and gives
  more direct control over scrolling and future editing, but GitHub-quality code
  blocks and diagram rendering would both have to be built (or, for diagrams,
  would end up embedding a WKWebView anyway just for those blocks — a hybrid that
  gets the downsides of both approaches without the benefits of either).

## Consequences

- Planned future rudimentary editing will be source-text-with-live-preview (a
  native `NSTextView`/`TextEditor` for the raw Markdown source, feeding the
  WKWebView preview on change) rather than in-place WYSIWYG editing of the
  rendered view. This sidesteps `contenteditable` + HTML↔Markdown round-tripping,
  which is where WKWebView would otherwise be a real liability. If in-place
  WYSIWYG editing is wanted later, revisit this ADR.
- Vim-style scroll keys are implemented via JS (`window.scrollBy` /
  `scroll-behavior: smooth`) rather than native `NSScrollView` handling.
