import Testing
@testable import Folium

/// Unit tests for the restoration settings behind issue #5. That the settings
/// actually reach `UserDefaults` is `DocumentRestorationTests` in the
/// integration target, which drives the real app delegate.
struct DocumentRestorationTests {
    @Test func registersTheDefaultThatKeepsOpenDocumentsAcrossAQuit() {
        #expect(DocumentRestoration.registrationDefaults[DocumentRestoration.quitAlwaysKeepsWindowsKey] == true)
    }

    @Test func registersNothingElse() {
        // Registering unrelated defaults would quietly change AppKit behavior
        // nobody asked us to change.
        #expect(DocumentRestoration.registrationDefaults.count == 1)
    }
}
