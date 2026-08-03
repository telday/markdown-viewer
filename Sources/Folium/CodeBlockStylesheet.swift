/// Chrome around fenced code blocks (issue #4): the container, header bar
/// holding the language label and Copy button, and the button's own states.
/// Layered on top of `GitHubStylesheet`'s base `pre`/`code` rules and
/// `HighlightJSTheme`'s token colors — this file owns only the wrapper
/// `CodeBlockDecorator` adds, not the syntax-highlighted text inside it.
///
/// Reuses `GitHubStylesheet`'s CSS custom properties (`--canvasSubtle`,
/// `--borderDefault`, etc.) so light/dark tracking is automatic, with no
/// separate `prefers-color-scheme` block needed here.
enum CodeBlockStylesheet {
    static let css = """
    .markdown-body .code-block {
      margin-top: 0;
      margin-bottom: 16px;
      overflow: hidden;
      border: 1px solid var(--borderDefault);
      border-radius: 6px;
      background-color: var(--canvasSubtle);
    }

    .markdown-body .code-block-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      padding: 6px 12px;
      border-bottom: 1px solid var(--borderDefault);
      font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas,
        "Liberation Mono", monospace;
      font-size: 12px;
    }

    .markdown-body .code-block-lang {
      color: var(--fgMuted);
      text-transform: uppercase;
      letter-spacing: 0.03em;
    }

    .markdown-body .copy-button {
      margin-left: auto;
      padding: 3px 10px;
      color: var(--fgDefault);
      background-color: var(--canvasDefault);
      border: 1px solid var(--borderDefault);
      border-radius: 6px;
      font-family: inherit;
      font-size: 12px;
      line-height: 1.4;
      cursor: pointer;
    }

    .markdown-body .copy-button:hover {
      background-color: var(--neutralMuted);
    }

    .markdown-body .copy-button.copied {
      color: var(--accentFg);
      border-color: var(--accentFg);
    }

    .markdown-body .code-block pre {
      margin: 0;
      background-color: transparent;
      border-radius: 0;
    }
    """
}
