import Testing
@testable import Folium

struct RemoteContentStateTests {
    // MARK: - Initial state

    @Test func startsWithNoBlockedContentAndNotAllowedByDefault() {
        let state = RemoteContentState()
        #expect(!state.hasBlockedContent)
        #expect(!state.isAllowed)
    }

    @Test func computesHasBlockedContentFromTheBodyItWasCreatedWith() {
        // So the bar is correct on the very first render, not only after
        // the next one — a document with badges at the top must not flash
        // an unblocked frame before the bar catches up.
        let state = RemoteContentState(bodyHTML: #"<img src="https://example.com/badge.png">"#)
        #expect(state.hasBlockedContent)
    }

    // MARK: - render(bodyHTML:) recomputes hasBlockedContent

    @Test func renderTurnsOnHasBlockedContentWhenNewBodyReferencesRemoteContent() {
        let state = RemoteContentState(bodyHTML: "<p>no images</p>")
        #expect(!state.hasBlockedContent)

        state.render(bodyHTML: #"<img src="https://example.com/badge.png">"#)
        #expect(state.hasBlockedContent)
    }

    @Test func renderTurnsOffHasBlockedContentWhenTheRemoteReferenceIsEditedOut() {
        // A live-reloaded (issue #7) document that had its remote image
        // removed should stop showing the bar without the user doing
        // anything.
        let state = RemoteContentState(bodyHTML: #"<img src="https://example.com/badge.png">"#)
        #expect(state.hasBlockedContent)

        state.render(bodyHTML: "<p>image removed</p>")
        #expect(!state.hasBlockedContent)
    }

    @Test func renderDoesNotResetAnExistingAllowDecision() {
        // The whole point of allow() being one-way: a live reload of a
        // document the user already trusted must not silently re-block it
        // and swap the "Load" bar back in mid-read.
        let state = RemoteContentState(bodyHTML: #"<img src="https://example.com/badge.png">"#)
        state.allow()
        #expect(state.isAllowed)

        state.render(bodyHTML: #"<img src="https://example.com/badge.png">"#)
        #expect(state.isAllowed)
    }

    // MARK: - allow() is one-way

    @Test func allowSetsIsAllowedToTrue() {
        let state = RemoteContentState()
        #expect(!state.isAllowed)
        state.allow()
        #expect(state.isAllowed)
    }

    @Test func allowIsIdempotentAndStaysOnceSet() {
        let state = RemoteContentState()
        state.allow()
        state.allow()
        #expect(state.isAllowed)
    }
}
