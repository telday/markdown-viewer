import Foundation
import Testing
@testable import Folium

struct NavigationPolicyTests {
    private let shellURL = URL(string: "file:///Applications/Folium.app/Contents/Resources/Resources/page.html")!

    // MARK: - Table-driven coverage of every rule in NavigationPolicy.decide

    private struct Case {
        let name: String
        let url: URL?
        let isLinkActivation: Bool
        let documentDirectory: URL?
        let expected: NavigationDecision

        init(
            name: String,
            url: URL?,
            isLinkActivation: Bool,
            documentDirectory: URL? = nil,
            expected: NavigationDecision
        ) {
            self.name = name
            self.url = url
            self.isLinkActivation = isLinkActivation
            self.documentDirectory = documentDirectory
            self.expected = expected
        }
    }

    private var cases: [Case] {
        [
            Case(name: "nil URL blocks", url: nil, isLinkActivation: true, expected: .block),
            Case(
                name: "http link opens in the browser",
                url: URL(string: "http://example.com"), isLinkActivation: true,
                expected: .openInBrowser(URL(string: "http://example.com")!)
            ),
            Case(
                name: "https link opens in the browser",
                url: URL(string: "https://example.com/a"), isLinkActivation: true,
                expected: .openInBrowser(URL(string: "https://example.com/a")!)
            ),
            Case(
                name: "https link opens in the browser even as the initial navigation",
                url: URL(string: "https://example.com"), isLinkActivation: false,
                expected: .openInBrowser(URL(string: "https://example.com")!)
            ),
            Case(
                name: "in-shell fragment scrolls instead of navigating",
                url: shellURL.appendingFragment("usage"), isLinkActivation: true,
                expected: .scrollToAnchor("usage")
            ),
            Case(
                name: "in-shell fragment scrolls even when it wasn't a click",
                url: shellURL.appendingFragment("usage"), isLinkActivation: false,
                expected: .scrollToAnchor("usage")
            ),
            Case(
                name: "the shell's own initial load is allowed",
                url: shellURL, isLinkActivation: false,
                expected: .allow
            ),
            Case(
                name: "a link back to the shell with no fragment is blocked, not reloaded",
                url: shellURL, isLinkActivation: true,
                expected: .block
            ),
            Case(
                name: "file: to a different file opens as a sibling document",
                url: URL(string: "file:///Users/me/notes.md"), isLinkActivation: true,
                expected: .openDocument(URL(string: "file:///Users/me/notes.md")!)
            ),
            Case(
                name: "file: to a different file opens even when it wasn't a click",
                url: URL(string: "file:///Users/me/notes.md"), isLinkActivation: false,
                expected: .openDocument(URL(string: "file:///Users/me/notes.md")!)
            ),
            Case(
                name: "javascript: is blocked",
                url: URL(string: "javascript:alert(1)"), isLinkActivation: true,
                expected: .block
            ),
            Case(
                name: "data: is blocked",
                url: URL(string: "data:text/html,hi"), isLinkActivation: true,
                expected: .block
            ),
            Case(
                name: "mailto: is blocked",
                url: URL(string: "mailto:a@example.com"), isLinkActivation: true,
                expected: .block
            ),
            Case(
                name: "a custom scheme is blocked",
                url: URL(string: "myapp://open"), isLinkActivation: true,
                expected: .block
            )
        ]
    }

    @Test func decidesEveryRuleCorrectly() {
        for testCase in cases {
            let decision = NavigationPolicy.decide(
                NavigationRequest(url: testCase.url, isLinkActivation: testCase.isLinkActivation),
                shellURL: shellURL,
                documentDirectory: testCase.documentDirectory
            )
            #expect(decision == testCase.expected, "\(testCase.name)")
        }
    }

    // MARK: - folium-doc: links (issue #18)
    //
    // These need a real file on disk — DocumentResourceResolver.fileURL,
    // which decide() calls to map a clicked link back to a real path,
    // refuses to resolve anything that doesn't exist as a regular file — so
    // they're kept out of the table above and given their own fixture.

    @Test func documentSchemeLinkToAFileInsideTheDirectoryOpensAsASiblingDocument() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = directory.appendingPathComponent("notes.md")
        try Data().write(to: notes)

        let decision = NavigationPolicy.decide(
            NavigationRequest(url: URL(string: "folium-doc://doc/notes.md"), isLinkActivation: true),
            shellURL: shellURL,
            documentDirectory: directory
        )

        #expect(decision == .openDocument(notes.standardizedFileURL.resolvingSymlinksInPath()))
    }

    @Test func documentSchemeLinkThatEscapesTheDirectoryIsBlockedNotOpened() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let decision = NavigationPolicy.decide(
            NavigationRequest(url: URL(string: "folium-doc://doc/../../etc/passwd"), isLinkActivation: true),
            shellURL: shellURL,
            documentDirectory: directory
        )

        #expect(decision == .block)
    }

    @Test func documentSchemeLinkWithNoDocumentDirectoryIsBlocked() {
        // A document with nothing on disk (a brand-new untitled window) has
        // no directory of its own to resolve a folium-doc: link against.
        let decision = NavigationPolicy.decide(
            NavigationRequest(url: URL(string: "folium-doc://doc/notes.md"), isLinkActivation: true),
            shellURL: shellURL,
            documentDirectory: nil
        )

        #expect(decision == .block)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NavigationPolicyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private extension URL {
    func appendingFragment(_ fragment: String) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        components.fragment = fragment
        return components.url!
    }
}
