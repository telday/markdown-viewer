// Defines window.FoliumScrollBy(lines), which Swift calls via
// evaluateJavaScript when a scroll key is pressed (MarkdownWebView).
//
// The key itself is never seen here. Capturing it with a keydown listener in
// the page would only work while the web content held focus, and would take
// the keystroke out of the responder chain before menus, key equivalents and
// VoiceOver ever saw it — so the capture is a native NSEvent one and this end
// only moves the viewport.
window.FoliumScrollBy = function (lines) {
  var article = document.getElementById("markdown-content");
  var style = window.getComputedStyle(article);

  // Resolves to a pixel value while the stylesheet gives the body a
  // line-height; the keyword "normal" parses as NaN, hence the fallback.
  var lineHeight = parseFloat(style.lineHeight);
  if (!isFinite(lineHeight) || lineHeight <= 0) {
    lineHeight = parseFloat(style.fontSize) * 1.5;
  }

  window.scrollBy({ top: lines * lineHeight, behavior: "smooth" });
};
