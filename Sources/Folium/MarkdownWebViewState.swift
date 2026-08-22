/// Tracks the one-time load of `MarkdownWebView`'s static page shell so
/// content updates can become cheap JS-injected DOM patches instead of full
/// page reloads (a full reload would re-parse every stylesheet and
/// re-parse/recompile all of highlight.js on every single content change —
/// prohibitive once live source-preview editing, already planned per ADR
/// 0001, means that happens on every keystroke).
///
/// No WebKit dependency, so this lives in the unit-testable logic layer
/// rather than growing inside `MarkdownWebView`'s excluded glue — see
/// `docs/agents/definition-of-done.md` on keeping real logic out of files
/// exempt from the coverage requirement.
final class MarkdownWebViewState {
    private var isShellLoaded = false
    private var pendingBodyHTML: String?
    private var hasConfirmedFirstPaint = false
    var benchMarker: BenchMarker = BenchMarker()

    /// Call when the shell's one-time `WKNavigationDelegate` `didFinish`
    /// fires. Returns body content to render immediately if one arrived
    /// (via `render(bodyHTML:)`) before the shell finished loading.
    func shellDidFinishLoading() -> String? {
        isShellLoaded = true
        defer { pendingBodyHTML = nil }
        return pendingBodyHTML
    }

    /// Call whenever new body content should render. Returns the HTML to
    /// inject immediately if the shell has already loaded, or `nil` if it's
    /// been queued to render once `shellDidFinishLoading()` is called
    /// instead — only the most recent call's content is kept.
    func render(bodyHTML: String) -> String? {
        guard isShellLoaded else {
            pendingBodyHTML = bodyHTML
            return nil
        }
        return bodyHTML
    }

    /// One-shot latch: `true` only the first time it is called, `false`
    /// every time after. `MarkdownWebView` calls this after an injection
    /// completes and the browser has confirmed a frame was actually drawn,
    /// and only marks `first-paint` when it answers `true` — the decision of
    /// *whether* an injection counts as the first paint lives here, where it
    /// can be unit-tested, while confirming the paint itself needs a real
    /// `WKWebView` and stays in that excluded glue file.
    ///
    /// Only the document's first paint is worth this round trip. Every
    /// injection after that is a live-reload, and its own speed is already
    /// measured by `LiveDocument`'s `reload-paint` marker — confirming a
    /// paint costs two animation frames, and paying that on every reload
    /// would eat into the 100 ms budget for a number nothing needs.
    func shouldConfirmFirstPaint() -> Bool {
        guard !hasConfirmedFirstPaint else { return false }
        hasConfirmedFirstPaint = true
        return true
    }
}
