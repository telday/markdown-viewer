/// Chrome around fenced code blocks (issue #4): the container, header bar
/// holding the language label and Copy button, and the button's own states.
/// Layered on top of `GitHubStylesheet`'s base `pre`/`code` rules and
/// `HighlightJSTheme`'s token colors — this file owns only the wrapper
/// `CodeBlockDecorator` adds, not the syntax-highlighted text inside it.
///
/// Reuses `GitHubStylesheet`'s CSS custom properties (`--canvasSubtle`,
/// `--borderDefault`, etc.) so light/dark tracking is automatic, with no
/// separate `prefers-color-scheme` block needed here.
///
/// Authored as a real file (`Sources/Folium/Resources/code-block.css`),
/// compiled in via `.embedInCode` as `PackageResources.code_block_css` — see
/// `GitHubStylesheet` for why.
enum CodeBlockStylesheet {
    static let css = EmbeddedAsset.string(PackageResources.code_block_css)
}
