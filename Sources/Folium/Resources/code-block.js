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
