const DOODLEPPL_SCRIPT = "https://unpkg.com/doodleppl@0.10/dist/doodleppl.global.js";
const BUNDLES = "https://mcmcjs.github.io/bugs-examples";
const REPORT = "https://mcmcjs.github.io/report/";
const BACKENDS = { juliabugs: "JuliaBUGS", turing: "Turing", stan: "Stan" };
const SVG_NS = "http://www.w3.org/2000/svg";
const SVG_TAGS = new Set([
  "svg", "g", "path", "rect", "line", "polyline", "polygon", "circle", "ellipse",
  "text", "tspan", "defs", "clipPath",
]);
const SVG_ATTRS = new Set([
  "viewBox", "width", "height", "x", "y", "x1", "y1", "x2", "y2", "cx", "cy", "r",
  "rx", "ry", "points", "d", "transform", "fill", "fill-opacity", "stroke",
  "stroke-width", "stroke-opacity", "opacity", "text-anchor", "font-family",
  "font-size", "font-weight", "data-tip",
]);

function loadWidget() {
  if (!document.querySelector("doodle-ppl")) return;
  const script = document.createElement("script");
  script.src = DOODLEPPL_SCRIPT;
  script.defer = true;
  document.head.appendChild(script);
}

// Inlining keeps the plot's CSS variables in sync with the page theme.
async function inlinePlot(url, label) {
  try {
    const response = await fetch(url);
    if (!response.ok) return null;
    const parsed = new DOMParser().parseFromString(await response.text(), "image/svg+xml");
    const svg = parsed.documentElement;
    if (svg.namespaceURI !== SVG_NS || svg.localName !== "svg") return null;
    for (const node of [svg, ...svg.querySelectorAll("*")]) {
      if (node.namespaceURI !== SVG_NS || !SVG_TAGS.has(node.localName)) {
        node.remove();
        continue;
      }
      for (const attr of [...node.attributes]) {
        if (attr.name === "xmlns" && attr.value === SVG_NS) continue;
        if (attr.namespaceURI || !SVG_ATTRS.has(attr.name) || /url\s*\(/i.test(attr.value)) {
          node.removeAttributeNode(attr);
        }
      }
    }
    const holder = document.createElement("div");
    holder.className = "mcmc-plot";
    svg.setAttribute("role", "img");
    svg.setAttribute("aria-label", label);
    svg.removeAttribute("width");
    holder.append(document.importNode(svg, true));
    return holder;
  } catch {
    return null;
  }
}

function paragraph(text) {
  const p = document.createElement("p");
  p.textContent = text;
  return p;
}

function describe(run) {
  const parts = [];
  if (run.backend) {
    const name = BACKENDS[run.backend.id] ?? run.backend.id;
    parts.push(run.backend.id === "stan" ? `${name} ${run.backend.version}` : `${name} on Julia ${run.backend.version}`);
  }
  const s = run.sampler;
  if (s) {
    parts.push(
      `${s.algorithm} with ${s.chains} chains of ${s.draws} draws after ${s.warmup} warmup` +
        (s.thin > 1 ? `, thinned by ${s.thin}` : ""),
    );
  }
  if (run.fitted_at) parts.push(`on ${run.fitted_at.slice(0, 10)}`);
  return parts.join(", ");
}

async function fillRun(slot, run) {
  const key = slot.dataset.example;
  const section = document.createDocumentFragment();
  const heading = document.createElement("h2");
  heading.id = "published-run";
  heading.textContent = "A published run";
  section.appendChild(heading);
  section.appendChild(
    paragraph(
      `This example was fitted with ${describe(run)}. ` +
        "The original used Gibbs sampling, so the posterior should agree but the Monte Carlo error will not.",
    ),
  );
  if (run.converged === false) {
    const rhat = typeof run.rhat_max === "number" ? ` (largest R-hat ${run.rhat_max.toFixed(2)})` : "";
    const warning = paragraph(
      `${rhat}, so its summaries are not reliable. It is published so the chains can be inspected.`,
    );
    const strong = document.createElement("strong");
    strong.textContent = "This run did not converge";
    warning.prepend(strong);
    section.appendChild(warning);
  }
  const plots = await Promise.all([
    inlinePlot(`${BUNDLES}/${key}-trace.svg`, "Trace of the monitored parameters, one line per chain"),
    inlinePlot(`${BUNDLES}/${key}-density.svg`, "Posterior density of the monitored parameters, one curve per chain"),
  ]);
  for (const plot of plots) if (plot) section.appendChild(plot);
  const bundle = `${BUNDLES}/${encodeURIComponent(run.file)}`;
  const links = document.createElement("p");
  const report = document.createElement("a");
  report.href = `${REPORT}#bundle=${bundle}`;
  report.textContent = "Open the full report";
  const download = document.createElement("a");
  download.href = bundle;
  download.textContent = "download the run bundle";
  links.append(report, " to explore every parameter interactively, or ", download, ".");
  section.appendChild(links);
  slot.replaceWith(section);
}

async function fillRuns() {
  const slots = Array.from(document.querySelectorAll(".mcmc-run[data-example]"));
  if (slots.length === 0) return;
  let runs = [];
  try {
    const response = await fetch(`${BUNDLES}/index.json`);
    if (response.ok) {
      const index = await response.json();
      if (Array.isArray(index.runs)) runs = index.runs;
    }
  } catch {}
  for (const slot of slots) {
    const run = runs.find((r) => r.key === slot.dataset.example);
    if (run) {
      await fillRun(slot, run);
    } else {
      slot.remove();
    }
  }
}

function start() {
  loadWidget();
  void fillRuns();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", start);
} else {
  start();
}
