import SwiftUI

@main
struct FoliumApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { configuration in
            let bodyHTML = MarkdownRenderer.renderHTML(from: configuration.document.text)
            MarkdownWebView(html: MarkdownPage.html(bodyHTML: bodyHTML))
        }
    }
}
