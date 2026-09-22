// The widget version and the mcmcjs URLs live here and nowhere else, so an example page
// carries only a <doodle-ppl model=...> element and a <div class="mcmc-run" data-example=...> slot.
const DOODLEPPL_SCRIPT = "https://unpkg.com/doodleppl@0.10/dist/doodleppl.global.js";
const BUNDLES = "https://mcmcjs.github.io/bugs-examples";
const REPORT = "https://mcmcjs.github.io/report/";
const BACKENDS = { juliabugs: "JuliaBUGS", turing: "Turing", stan: "Stan" };

function loadWidget() {
  if (!document.querySelector("doodle-ppl")) return;
  const script = document.createElement("script");
  script.src = DOODLEPPL_SCRIPT;
  script.defer = true;
  document.head.appendChild(script);
}

// An <img> renders an SVG as its own document, out of reach of the page's CSS variables,
// so a plot would stay light on a dark page. Inlining the SVG lets them apply.
async function inlinePlot(url, label) {
  const response = await fetch(url);
  if (!response.ok) return null;
  const holder = document.createElement("div");
  holder.className = "mcmc-plot";
  holder.innerHTML = await response.text();
  const svg = holder.querySelector("svg");
  if (!svg) return null;
  svg.setAttribute("role", "img");
  svg.setAttribute("aria-label", label);
  svg.removeAttribute("width");
  return holder;
}

function paragraph(html) {
  const p = document.createElement("p");
  p.innerHTML = html;
  return p;
}

// The bundle records the backend id and the Julia version it ran on.
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
        `The original used Gibbs sampling, so the posterior should agree but the Monte Carlo error will not.`,
    ),
  );
  if (run.converged === false) {
    const rhat = typeof run.rhat_max === "number" ? ` (largest R-hat ${run.rhat_max.toFixed(2)})` : "";
    section.appendChild(
      paragraph(
        `<strong>This run did not converge</strong>${rhat}, so its summaries are not reliable. ` +
          `It is published so the chains can be inspected.`,
      ),
    );
  }
  const plots = await Promise.all([
    inlinePlot(`${BUNDLES}/${key}-trace.svg`, "Trace of the monitored parameters, one line per chain"),
    inlinePlot(`${BUNDLES}/${key}-density.svg`, "Posterior density of the monitored parameters, one curve per chain"),
  ]);
  for (const plot of plots) if (plot) section.appendChild(plot);
  const bundle = `${BUNDLES}/${run.file}`;
  section.appendChild(
    paragraph(
      `<a href="${REPORT}#bundle=${bundle}">Open the full report</a> to explore every parameter interactively, ` +
        `or <a href="${bundle}">download the run bundle</a>.`,
    ),
  );
  slot.replaceWith(section);
}

async function fillRuns() {
  const slots = Array.from(document.querySelectorAll(".mcmc-run[data-example]"));
  if (slots.length === 0) return;
  let runs = [];
  try {
    const response = await fetch(`${BUNDLES}/index.json`);
    if (response.ok) runs = (await response.json()).runs || [];
  } catch {
    // Offline, the page reads fine without its run section.
  }
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
