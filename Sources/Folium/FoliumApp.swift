import SwiftUI

@main
struct FoliumApp: App {
    // Turns on document/window state restoration, which SwiftUI's own app
    // delegate leaves off. See FoliumAppDelegate.
    @NSApplicationDelegateAdaptor(FoliumAppDelegate.self) private var appDelegate

    // One store for the whole app: rebinding a key in the Settings scene has
    // to reach every document window, which is a separate scene.
    @StateObject private var scrollKeys = ScrollKeyStore()

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { configuration in
            DocumentView(
                text: configuration.document.text,
                fileURL: configuration.fileURL,
                scrollKeys: scrollKeys
            )
            // Files this document's window into the app's shared native
            // tab group — the only way to reach the NSWindow that
            // DocumentGroup made for it. See DocumentWindowTabber.
            .background(DocumentWindowTabber())
        }

        // The Settings scene is what puts "Settings…" in the app menu at ⌘,
        // and manages the window behind it. Opening a preferences window
        // ourselves would be the lookalike CONTEXT.md priority 1 rules out.
        Settings {
            PreferencesView(scrollKeys: scrollKeys)
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
    // Owned alongside `document` rather than inside `LiveDocument` itself
    // (issue #19) — see `RemoteContentState`'s doc comment. Not persisted:
    // a fresh one is created every time a document window opens, which is
    // what makes "closing and reopening blocks remote content again" true.
    @StateObject private var remoteContent: RemoteContentState
    @ObservedObject var scrollKeys: ScrollKeyStore

    init(text: String, fileURL: URL?, scrollKeys: ScrollKeyStore) {
        let liveDocument = LiveDocument(text: text, fileURL: fileURL)
        _document = StateObject(wrappedValue: liveDocument)
        _remoteContent = StateObject(wrappedValue: RemoteContentState(bodyHTML: liveDocument.bodyHTML))
        self.scrollKeys = scrollKeys
    }

    var body: some View {
        MarkdownWebView(
            bodyHTML: document.bodyHTML,
            scrollKeys: scrollKeys.bindings,
            remoteContentAllowed: remoteContent.isAllowed
        )
        // No `initial: true`: `hasBlockedContent` for the very first render
        // is already computed by `RemoteContentState.init(bodyHTML:)` above,
        // from this same `document.bodyHTML`. Firing here too on the initial
        // appearance would scan every document's body twice for no different
        // answer — this only needs to run for the reloads after that.
        .onChange(of: document.bodyHTML) { _, newBodyHTML in
            remoteContent.render(bodyHTML: newBodyHTML)
        }
        .safeAreaInset(edge: .top) {
            if remoteContent.shouldPromptToLoad {
                RemoteContentBar(onLoad: remoteContent.allow)
            }
        }
    }
}

/// The native "Load remote images" affordance (issue #19). CONTEXT.md
/// priority 1 rules out an HTML banner injected into the document body —
/// "the document is GitHub's, the chrome is macOS's" — so this is plain
/// SwiftUI laid over the web view via `.safeAreaInset`, styled like a
/// toolbar rather than part of the page.
private struct RemoteContentBar: View {
    let onLoad: () -> Void

    var body: some View {
        HStack {
            Label("This document contains remote images.", systemImage: "photo.on.rectangle.angled")
                .font(.callout)
            Spacer()
            Button("Load", action: onLoad)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
