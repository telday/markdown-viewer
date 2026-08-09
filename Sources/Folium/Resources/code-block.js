// Defines window.FoliumRenderBody(html) rather than running once at page
// load: the page shell (page.html) loads a single time per WKWebView, and
// Swift calls this function via evaluateJavaScript on every content update
// (MarkdownWebView / MarkdownWebViewState) instead of reloading the page —
// reloading would re-parse every stylesheet and re-parse/recompile all of
// highlight.js on every single update.
window.FoliumRenderBody = function (html) {
  var article = document.getElementById("markdown-content");
  article.innerHTML = html;

  if (window.hljs) {
    window.hljs.highlightAll();
  }

  article.querySelectorAll(".copy-button").forEach(function (button) {
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
};
