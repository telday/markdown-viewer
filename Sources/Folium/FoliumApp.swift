import SwiftUI

@main
struct FoliumApp: App {
    // Turns on document/window state restoration, which SwiftUI's own app
    // delegate leaves off. See FoliumAppDelegate.
    @NSApplicationDelegateAdaptor(FoliumAppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { configuration in
            MarkdownWebView(bodyHTML: MarkdownRenderer.renderHTML(from: configuration.document.text))
                // Files this document's window into the app's shared native
                // tab group — the only way to reach the NSWindow that
                // DocumentGroup made for it. See DocumentWindowTabber.
                .background(DocumentWindowTabber())
        }
    }
}
