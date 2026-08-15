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

/// The contents of one document window, kept live against the file on disk
/// (issue #7).
///
/// This exists only because `@StateObject` has to live in a `View`, and
/// `DocumentGroup`'s content closure isn't one. All it does is keep a
/// `LiveDocument` alive for as long as the window is open.
///
/// Deliberately inside `FoliumApp.swift`, which is already excluded from the
/// coverage requirement: a file of its own would grow the exclusion list in
/// `scripts/coverage.sh` for something with nothing in it to test.
private struct DocumentView: View {
    @StateObject private var document: LiveDocument

    init(text: String, fileURL: URL?) {
        _document = StateObject(wrappedValue: LiveDocument(text: text, fileURL: fileURL))
    }

    var body: some View {
        MarkdownWebView(bodyHTML: document.bodyHTML)
    }
}
