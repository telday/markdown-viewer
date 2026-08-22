import Testing
@testable import Folium

struct MarkdownWebViewStateTests {
    @Test func queuesContentRequestedBeforeTheShellFinishesLoading() {
        let state = MarkdownWebViewState()
        #expect(state.render(bodyHTML: "<p>one</p>") == nil)
    }

    @Test func shellFinishingDeliversTheQueuedContent() {
        let state = MarkdownWebViewState()
        _ = state.render(bodyHTML: "<p>one</p>")
        #expect(state.shellDidFinishLoading() == "<p>one</p>")
    }

    @Test func shellFinishingWithNothingQueuedReturnsNil() {
        let state = MarkdownWebViewState()
        #expect(state.shellDidFinishLoading() == nil)
    }

    @Test func onlyTheMostRecentlyQueuedContentSurvivesUntilTheShellLoads() {
        let state = MarkdownWebViewState()
        _ = state.render(bodyHTML: "<p>stale</p>")
        _ = state.render(bodyHTML: "<p>latest</p>")
        #expect(state.shellDidFinishLoading() == "<p>latest</p>")
    }

    @Test func rendersImmediatelyOnceTheShellHasLoaded() {
        let state = MarkdownWebViewState()
        _ = state.shellDidFinishLoading()
        #expect(state.render(bodyHTML: "<p>two</p>") == "<p>two</p>")
    }

    @Test func consumingTheQueueClearsItForNextTime() {
        let state = MarkdownWebViewState()
        _ = state.render(bodyHTML: "<p>one</p>")
        _ = state.shellDidFinishLoading()
        // Nothing new was queued since the shell loaded, and it's already
        // loaded, so a bare re-check delivers nothing stale.
        #expect(state.shellDidFinishLoading() == nil)
    }

    @Test func shouldConfirmFirstPaintIsTrueOnlyTheFirstTime() {
        let state = MarkdownWebViewState()

        #expect(state.shouldConfirmFirstPaint())
        #expect(!state.shouldConfirmFirstPaint())
        #expect(!state.shouldConfirmFirstPaint())
    }
}
