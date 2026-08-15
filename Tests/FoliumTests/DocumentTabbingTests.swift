import Testing
@testable import Folium

/// Unit tests for the tabbing decisions behind issue #5. The AppKit side —
/// that `addTabbedWindow` really produces one window with a native tab bar —
/// is `DocumentWindowTabbingTests` in the integration target.
struct DocumentTabbingTests {
    // MARK: - prefersTabbing

    @Test func overridesTheMacOSDefaultSoOpeningSeveralFilesTabsThem() {
        // "In Full Screen Only" is the out-of-the-box setting; leaving it
        // alone is exactly what leaves three open files as three loose
        // windows, which is the bug issue #5 is about.
        #expect(DocumentTabbing.prefersTabbing(userPreference: .inFullScreen))
    }

    @Test func tabsWhenTheUserAlreadyPrefersTabsEverywhere() {
        #expect(DocumentTabbing.prefersTabbing(userPreference: .always))
    }

    @Test func honorsAUserWhoTurnedAutomaticTabbingOff() {
        // Not a default — someone went to System Settings and asked for this.
        #expect(DocumentTabbing.prefersTabbing(userPreference: .manual) == false)
    }

    // MARK: - mergeTarget

    @Test func aNewWindowJoinsTheOnlyOpenDocumentWindow() {
        let target = DocumentTabbing.mergeTarget(
            prefersTabbing: true,
            newWindowIsAlreadyTabbed: false,
            orderedOtherWindows: [.document("first")]
        )
        #expect(target == "first")
    }

    @Test func theFirstWindowOpenedHasNothingToJoin() {
        let target = DocumentTabbing.mergeTarget(
            prefersTabbing: true,
            newWindowIsAlreadyTabbed: false,
            orderedOtherWindows: [] as [DocumentTabbing.Candidate<String>]
        )
        #expect(target == nil)
    }

    @Test func aNewTabLandsInTheFrontmostWindowWhenSeveralAreOpen() {
        // Front-to-back order: a second tab group the user pushed to the back
        // is not where the document they just opened should show up.
        let target = DocumentTabbing.mergeTarget(
            prefersTabbing: true,
            newWindowIsAlreadyTabbed: false,
            orderedOtherWindows: [.document("front"), .document("back")]
        )
        #expect(target == "front")
    }

    @Test func nonDocumentWindowsAreNeverAMergeTarget() {
        // The Open panel and friends are in NSApp.orderedWindows too, and
        // tabbing a document into one of them would be nonsense.
        let target = DocumentTabbing.mergeTarget(
            prefersTabbing: true,
            newWindowIsAlreadyTabbed: false,
            orderedOtherWindows: [
                DocumentTabbing.Candidate(window: "panel", isDocumentWindow: false, isVisible: true),
                .document("document")
            ]
        )
        #expect(target == "document")
    }

    @Test func offScreenWindowsAreNeverAMergeTarget() {
        let target = DocumentTabbing.mergeTarget(
            prefersTabbing: true,
            newWindowIsAlreadyTabbed: false,
            orderedOtherWindows: [
                DocumentTabbing.Candidate(window: "hidden", isDocumentWindow: true, isVisible: false),
                .document("onscreen")
            ]
        )
        #expect(target == "onscreen")
    }

    @Test func nothingIsMergedWhenTheUserOptedOutOfAutomaticTabbing() {
        let target = DocumentTabbing.mergeTarget(
            prefersTabbing: false,
            newWindowIsAlreadyTabbed: false,
            orderedOtherWindows: [.document("first")]
        )
        #expect(target == nil)
    }

    @Test func anAlreadyTabbedWindowIsLeftWhereItIs() {
        // Re-merging would drag a window out of the group AppKit (or the user,
        // by dragging) already put it in.
        let target = DocumentTabbing.mergeTarget(
            prefersTabbing: true,
            newWindowIsAlreadyTabbed: true,
            orderedOtherWindows: [.document("first")]
        )
        #expect(target == nil)
    }
}

private extension DocumentTabbing.Candidate where Window == String {
    /// A visible Folium document window — the ordinary merge candidate.
    static func document(_ name: String) -> Self {
        Self(window: name, isDocumentWindow: true, isVisible: true)
    }
}
