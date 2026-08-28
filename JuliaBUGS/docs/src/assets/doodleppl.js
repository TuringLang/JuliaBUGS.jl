// Loads the DoodlePPL editor for pages that embed a graph, and keeps the widget's
// theme in step with Documenter's.
//
// The bundle is 4.2 MB, so it is injected only on pages that actually contain a
// <doodle-ppl> element. Documenter signals its theme by putting a "theme--<name>"
// class on <html>, and themeswap.js rewrites that class whenever the reader flips
// the toggle, so a MutationObserver on <html> is the reliable hook.
(function () {
  "use strict";

  var VERSION = "0.8.1";
  var BUNDLE = "https://unpkg.com/doodleppl@" + VERSION + "/dist/doodleppl.global.js";
  var SRI = "sha384-J2scl5T4h2iCNQWIjIDf8ypCTphR4Jm53tnX8ijKzKZqlsuI9kkH47vxqH5YkxRD";
  var TIMEOUT_MS = 15000;

  function embeds() {
    return document.querySelectorAll("doodle-ppl");
  }

  function isDark() {
    var cls = document.documentElement.className || "";
    return /theme--.*dark/.test(cls);
  }

  function applyTheme() {
    var mode = isDark() ? "dark" : "light";
    var nodes = embeds();
    var i;
    for (i = 0; i < nodes.length; i++) {
      if (nodes[i].getAttribute("theme-mode") !== mode) {
        nodes[i].setAttribute("theme-mode", mode);
      }
    }
  }

  // Shown when the CDN is unreachable, which is the normal case for offline docs.
  function degrade() {
    var wrappers = document.querySelectorAll(".doodleppl-embed");
    var i;
    for (i = 0; i < wrappers.length; i++) {
      wrappers[i].classList.add("doodleppl-unavailable");
    }
  }

  function boot() {
    if (embeds().length === 0) return;

    applyTheme();
    new MutationObserver(applyTheme).observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["class"],
    });

    var script = document.createElement("script");
    script.src = BUNDLE;
    script.integrity = SRI;
    script.crossOrigin = "anonymous";
    script.defer = true;

    var timer = setTimeout(function () {
      if (!window.customElements || !window.customElements.get("doodle-ppl")) degrade();
    }, TIMEOUT_MS);

    script.addEventListener("error", function () {
      clearTimeout(timer);
      degrade();
    });
    script.addEventListener("load", function () {
      clearTimeout(timer);
      // The widget reads theme-mode when it upgrades, so re-assert after definition.
      applyTheme();
    });

    document.head.appendChild(script);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
