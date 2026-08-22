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

    // MARK: - beginReload (issue #19: switching to the remote-content shell)

    @Test func beginReloadMakesRenderQueueAgainInsteadOfInjecting() {
        let state = MarkdownWebViewState()
        _ = state.shellDidFinishLoading()
        // Confirm the shell reads as loaded before the reload...
        #expect(state.render(bodyHTML: "<p>before</p>") == "<p>before</p>")

        state.beginReload()

        // ...and queues again afterward, the same as a shell that has never
        // finished its first load.
        #expect(state.render(bodyHTML: "<p>after reload</p>") == nil)
    }

    @Test func shellFinishingAfterAReloadDeliversTheContentQueuedDuringIt() {
        let state = MarkdownWebViewState()
        _ = state.shellDidFinishLoading()
        _ = state.render(bodyHTML: "<p>before</p>")

        state.beginReload()
        _ = state.render(bodyHTML: "<p>queued during reload</p>")

        // Mirrors the first-load path: the new page's own didFinish call
        // delivers whatever was queued while it was loading.
        #expect(state.shellDidFinishLoading() == "<p>queued during reload</p>")
    }
}
