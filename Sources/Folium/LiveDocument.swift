import Combine
import Foundation

/// One open document's body HTML, kept in step with the file on disk
/// (issue #7).
///
/// Folium is permanently a viewer (`CONTEXT.md` non-goals), so the user's real
/// editor is the other half of the workflow: they save in one window and expect
/// the rendering in the other to already be right. Nothing here is a manual
/// refresh — there is no refresh command to find, because there is nothing to
/// refresh.
///
/// SwiftUI's `DocumentGroup` reads the file once and hands the content over as
/// a value, so the live half has to be owned somewhere. This is that owner:
/// `FileWatcher` reports changes, `ReloadCoalescer` collapses a save's burst
/// into one, and this type does the re-read and the re-render. It publishes
/// **body HTML** rather than text so the render happens once per actual change
/// rather than once per SwiftUI view update — a tab switch has a 50 ms budget
/// and is explicitly not supposed to re-render.
///
/// No SwiftUI/AppKit/WebKit dependency, so it stays in the unit-tested logic
/// layer; the `View` in `FoliumApp` that owns one is the glue.
@MainActor
final class LiveDocument: ObservableObject {
    /// The rendered document body, ready to hand to `MarkdownWebView`.
    @Published private(set) var bodyHTML: String

    private let fileURL: URL?
    private var coalescer: ReloadCoalescer?
    private var watcher: FileWatcher?

    /// - Parameters:
    ///   - text: the Markdown the document was opened with.
    ///   - fileURL: the file backing it, or `nil` for a document with no file
    ///     on disk — which simply gets no live-reload.
    ///   - scheduler: how the coalescing window is timed. Injected so tests can
    ///     drive it directly instead of sleeping.
    init(
        text: String,
        fileURL: URL?,
        scheduler: any ReloadScheduler = SleepingReloadScheduler()
    ) {
        self.fileURL = fileURL
        bodyHTML = MarkdownRenderer.renderHTML(from: text)

        guard let fileURL else { return }
        coalescer = ReloadCoalescer(scheduler: scheduler) { [weak self] in
            self?.reloadFromDisk()
        }
        let watcher = FileWatcher(url: fileURL) { [weak self] in
            Task { @MainActor in self?.fileDidChange() }
        }
        // A file that can't be watched (already gone, unreadable) still has a
        // perfectly good document on screen; live-reload is the part that is
        // missing, not the document.
        watcher.start()
        self.watcher = watcher
    }

    /// Records that the backing file changed. Called by the watcher on every
    /// notification; the reload follows once the burst settles.
    func fileDidChange() {
        coalescer?.noteChange()
    }

    /// Re-reads the file and re-renders, unless nothing about the output
    /// changed.
    ///
    /// A read or decode that fails leaves the last good body in place. The file
    /// being briefly absent or briefly invalid UTF-8 is the *normal* middle of
    /// a save, not a document to report — and blanking the window on the way
    /// past would be a worse answer than showing content that is a few
    /// milliseconds stale. (What Folium should do about a file that stays
    /// undecodable is an open question in `CONTEXT.md`, and is the *opening*
    /// path's to answer, not this one's.)
    private func reloadFromDisk() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        guard let text = try? MarkdownLoading.text(fromUTF8: data) else { return }

        let rendered = MarkdownRenderer.renderHTML(from: text)
        // A `touch`, a chmod, or a save that rewrote identical bytes should
        // cost nothing downstream: no publish, no injection, no repaint.
        guard rendered != bodyHTML else { return }
        bodyHTML = rendered
    }
}
