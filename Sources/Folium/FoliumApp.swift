import SwiftUI

@main
struct FoliumApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { configuration in
            MarkdownWebView(bodyHTML: MarkdownRenderer.renderHTML(from: configuration.document.text))
        }
    }
}
