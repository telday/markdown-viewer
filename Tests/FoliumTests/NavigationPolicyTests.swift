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
        let expected: NavigationDecision
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
                name: "file: to a different file is blocked",
                url: URL(string: "file:///Users/me/notes.md"), isLinkActivation: true,
                expected: .block
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
                shellURL: shellURL
            )
            #expect(decision == testCase.expected, "\(testCase.name)")
        }
    }
}

private extension URL {
    func appendingFragment(_ fragment: String) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        components.fragment = fragment
        return components.url!
    }
}
