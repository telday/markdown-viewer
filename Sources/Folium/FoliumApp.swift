import SwiftUI

@main
struct FoliumApp: App {
    // Turns on document/window state restoration, which SwiftUI's own app
    // delegate leaves off. See FoliumAppDelegate.
    @NSApplicationDelegateAdaptor(FoliumAppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { configuration in
            DocumentView(text: configuration.document.text, fileURL: configuration.fileURL)
                // Files this document's window into the app's shared native
                // tab group — the only way to reach the NSWindow that
                // DocumentGroup made for it. See DocumentWindowTabber.
                .background(DocumentWindowTabber())
        }
    }
}

/// The contents of one document window: the rendered document, kept live
/// against the file on disk (issue #7).
///
/// This exists because `@StateObject` needs a `View` to live in — `DocumentGroup`'s
/// content closure is not one — and because `DocumentGroup` reads the file
/// exactly once, so the ongoing relationship with it has to be owned by
/// something with a lifetime. That owner is `LiveDocument`, in the logic layer;
/// all that is left here is holding onto one for as long as the window exists.
///
/// Part of the coverage-excluded `FoliumApp.swift` scene definition
/// deliberately: keeping it here rather than in a file of its own means the
/// exclusion list in `scripts/coverage.sh` does not grow, and there is nothing
/// in it to test that `LiveDocumentTests` and `LiveReloadTests` don't already
/// cover.
private struct DocumentView: View {
    @StateObject private var document: LiveDocument

    init(text: String, fileURL: URL?) {
        _document = StateObject(wrappedValue: LiveDocument(text: text, fileURL: fileURL))
    }

    var body: some View {
        MarkdownWebView(bodyHTML: document.bodyHTML)
    }
}
