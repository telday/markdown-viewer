/// Runtime wiring for fenced code blocks (issue #4): runs highlight.js over
/// every code block, and gives each `.copy-button` (added by
/// `CodeBlockDecorator`) a click handler that copies the block's raw text
/// and shows brief "Copied!" confirmation.
///
/// Placed in a `<script>` right after the rendered article, so the DOM it
/// operates on already exists by the time it runs — no `DOMContentLoaded`
/// wait needed. Copies via `document.execCommand("copy")` rather than the
/// async Clipboard API: `MarkdownWebView` loads content with
/// `loadHTMLString(_:baseURL: nil)`, which WebKit treats as an opaque origin,
/// and `navigator.clipboard` is unavailable there — there's no secure-context
/// path to fall back from.
enum CodeBlockScript {
    static let script = """
    (function () {
      if (window.hljs) {
        window.hljs.highlightAll();
      }

      document.querySelectorAll(".copy-button").forEach(function (button) {
        button.addEventListener("click", function () {
          var block = button.closest(".code-block");
          var code = block ? block.querySelector("code") : null;
          var text = code ? code.textContent : "";

          var textarea = document.createElement("textarea");
          textarea.value = text;
          textarea.style.position = "fixed";
          textarea.style.opacity = "0";
          document.body.appendChild(textarea);
          textarea.select();
          document.execCommand("copy");
          document.body.removeChild(textarea);

          var original = button.textContent;
          button.textContent = "Copied!";
          button.classList.add("copied");
          window.setTimeout(function () {
            button.textContent = original;
            button.classList.remove("copied");
          }, 2000);
        });
      });
    })();
    """
}
