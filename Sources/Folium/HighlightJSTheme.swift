/// highlight.js's "github" theme CSS (light + dark), vendored the same way
/// as `HighlightJS` — see that file and `scripts/vendor-highlightjs.sh` for
/// provenance. The dark variant is wrapped in a `prefers-color-scheme` query
/// so it tracks the same system-appearance switch as `GitHubStylesheet`
/// (issue #3's pattern, reused here for issue #4).
enum HighlightJSTheme {
    static let css: String = {
        let light = BundledAsset.contents(
            resource: "github.min",
            extension: "css",
            subdirectory: "HighlightJS/styles"
        )
        let dark = BundledAsset.contents(
            resource: "github-dark.min",
            extension: "css",
            subdirectory: "HighlightJS/styles"
        )
        return """
        \(light)

        @media (prefers-color-scheme: dark) {
        \(dark)
        }
        """
    }()
}
