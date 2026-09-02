// Two small jobs for the example pages.
//
// An <img> loads an SVG as its own document, so the page's CSS variables never
// reach it and a published plot would stay light on a dark page. Fetching the
// same file and inlining it lets --mcmc-fg and --mcmc-bg apply.
//
// The theme sync is temporary. doodleppl gains a `theme-from` attribute in 0.9.0
// that does this itself; delete syncWidgets and its observer once the pages pin
// that release.
(() => {
  const isDark = () => /theme--.*dark/.test(document.documentElement.className);

  async function inlinePlots() {
    const targets = document.querySelectorAll("img[data-inline-svg]");
    await Promise.all(
      Array.from(targets, async (img) => {
        try {
          const response = await fetch(img.src);
          if (!response.ok) return;
          const holder = document.createElement("div");
          holder.className = "mcmc-plot";
          holder.innerHTML = await response.text();
          const svg = holder.querySelector("svg");
          if (!svg) return;
          svg.setAttribute("role", "img");
          svg.removeAttribute("width");
          const label = img.getAttribute("alt");
          if (label) svg.setAttribute("aria-label", label);
          img.replaceWith(holder);
        } catch {
          // Leave the <img> in place; it still renders, just without the theme.
        }
      }),
    );
  }

  function syncWidgets() {
    const mode = isDark() ? "dark" : "light";
    for (const el of document.querySelectorAll("doodle-ppl")) {
      if (el.getAttribute("theme-mode") !== mode) el.setAttribute("theme-mode", mode);
    }
  }

  function boot() {
    void inlinePlots();
    syncWidgets();
    new MutationObserver(syncWidgets).observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["class"],
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
