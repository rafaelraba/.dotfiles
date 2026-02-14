import { createServer } from "node:http";
import { readFileSync, watchFile, unwatchFile, existsSync } from "node:fs";
import { resolve, basename, dirname, join, extname } from "node:path";
import { execSync } from "node:child_process";

const filePath = resolve(process.argv[2] || "");
if (!filePath || !filePath.endsWith(".md")) {
  console.error("Usage: node server.js <file.md>");
  process.exit(1);
}

const fileName = basename(filePath);
const fileDir = dirname(filePath);
let clients = [];

const MIME_TYPES = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
  ".webp": "image/webp",
  ".ico": "image/x-icon",
  ".css": "text/css",
  ".js": "text/javascript",
  ".json": "application/json",
  ".pdf": "application/pdf",
  ".mp4": "video/mp4",
  ".webm": "video/webm",
};

function getMarkdown() {
  try {
    return readFileSync(filePath, "utf-8");
  } catch {
    return "# File not found";
  }
}

function notifyClients() {
  const md = getMarkdown();
  for (const res of clients) {
    res.write(`data: ${JSON.stringify(md)}\n\n`);
  }
}

watchFile(filePath, { interval: 300 }, notifyClients);

const HTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${fileName}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css" id="hljs-theme">
<script src="https://cdnjs.cloudflare.com/ajax/libs/markdown-it/13.0.2/markdown-it.min.js"><\/script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"><\/script>
<script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"><\/script>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }

:root {
  --bg: #0d1117;
  --bg-secondary: #161b22;
  --bg-tertiary: #1c2128;
  --text: #e6edf3;
  --text-secondary: #8b949e;
  --accent: #58a6ff;
  --accent-hover: #79c0ff;
  --border: #30363d;
  --green: #3fb950;
  --purple: #bc8cff;
  --orange: #f0883e;
  --red: #f85149;
  --code-bg: #1c2128;
  --shadow: 0 8px 24px rgba(0,0,0,0.4);
  --radius: 10px;
}

:root.light {
  --bg: #ffffff;
  --bg-secondary: #f6f8fa;
  --bg-tertiary: #eef1f5;
  --text: #1f2328;
  --text-secondary: #656d76;
  --accent: #0969da;
  --accent-hover: #0550ae;
  --border: #d0d7de;
  --green: #1a7f37;
  --purple: #8250df;
  --orange: #bc4c00;
  --red: #cf222e;
  --code-bg: #f6f8fa;
  --shadow: 0 8px 24px rgba(0,0,0,0.08);
}

html { scroll-behavior: smooth; }

body {
  font-family: 'Inter', -apple-system, sans-serif;
  background: var(--bg);
  color: var(--text);
  line-height: 1.7;
  transition: background 0.3s, color 0.3s;
}

/* ── Top bar ── */
.topbar {
  position: sticky;
  top: 0;
  z-index: 100;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 32px;
  background: var(--bg-secondary);
  border-bottom: 1px solid var(--border);
  backdrop-filter: blur(12px);
}

.topbar-title {
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 14px;
  font-weight: 600;
  color: var(--text);
}

.topbar-title svg { opacity: 0.6; }

.topbar-actions { display: flex; gap: 8px; align-items: center; }

.btn {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 6px 14px;
  font-size: 12px;
  font-weight: 500;
  font-family: inherit;
  color: var(--text-secondary);
  background: var(--bg-tertiary);
  border: 1px solid var(--border);
  border-radius: 8px;
  cursor: pointer;
  transition: all 0.2s;
}

.btn:hover {
  color: var(--text);
  border-color: var(--accent);
  background: var(--bg);
}

.live-dot {
  width: 7px;
  height: 7px;
  background: var(--green);
  border-radius: 50%;
  animation: pulse 2s infinite;
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.4; }
}

/* ── Content ── */
.content {
  max-width: 1440px;
  margin: 0 auto;
  padding: 48px 64px 120px;
}

/* ── Typography ── */
.content h1, .content h2, .content h3,
.content h4, .content h5, .content h6 {
  font-weight: 600;
  line-height: 1.3;
  margin-top: 2em;
  margin-bottom: 0.75em;
  color: var(--text);
}

.content h1 {
  font-size: 2em;
  padding-bottom: 0.4em;
  border-bottom: 2px solid var(--border);
}

.content h2 {
  font-size: 1.5em;
  padding-bottom: 0.3em;
  border-bottom: 1px solid var(--border);
}

.content h3 { font-size: 1.25em; }

.content p { margin-bottom: 1em; }

.content a {
  color: var(--accent);
  text-decoration: none;
  border-bottom: 1px solid transparent;
  transition: border-color 0.2s;
}

.content a:hover { border-bottom-color: var(--accent); }

.content strong { font-weight: 600; color: var(--text); }

.content ul, .content ol {
  margin-bottom: 1em;
  padding-left: 2em;
}

.content li { margin-bottom: 0.35em; }

.content li::marker { color: var(--text-secondary); }

.content blockquote {
  margin: 1em 0;
  padding: 0.5em 1em;
  border-left: 4px solid var(--accent);
  background: var(--bg-secondary);
  border-radius: 0 var(--radius) var(--radius) 0;
  color: var(--text-secondary);
}

.content hr {
  border: none;
  height: 2px;
  background: var(--border);
  margin: 2em 0;
  border-radius: 1px;
}

.content table {
  width: 100%;
  border-collapse: collapse;
  margin: 1em 0;
  font-size: 0.9em;
}

.content th, .content td {
  padding: 10px 16px;
  border: 1px solid var(--border);
  text-align: left;
}

.content th {
  background: var(--bg-secondary);
  font-weight: 600;
}

.content tr:nth-child(even) { background: var(--bg-secondary); }

/* ── Code ── */
.content code {
  font-family: 'JetBrains Mono', monospace;
  font-size: 0.85em;
  background: var(--code-bg);
  padding: 2px 7px;
  border-radius: 6px;
  border: 1px solid var(--border);
}

.content pre {
  margin: 1.2em 0;
  border-radius: var(--radius);
  border: 1px solid var(--border);
  overflow-x: auto;
  box-shadow: var(--shadow);
}

.content pre code {
  display: block;
  padding: 20px 24px;
  border: none;
  background: var(--code-bg);
  font-size: 0.85em;
  line-height: 1.6;
}

/* ── Mermaid ── */
.mermaid-wrapper {
  position: relative;
  margin: 1.5em 0;
  padding: 24px;
  background: var(--bg-secondary);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  overflow: hidden;
  transition: all 0.3s;
}

.mermaid-wrapper:hover { border-color: var(--accent); }

.mermaid-wrapper .mermaid {
  display: flex;
  justify-content: center;
}

.mermaid-wrapper .mermaid svg {
  max-width: 100%;
  height: auto;
}

.mermaid-expand {
  position: absolute;
  top: 12px;
  right: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  background: var(--bg-tertiary);
  border: 1px solid var(--border);
  border-radius: 8px;
  color: var(--text-secondary);
  cursor: pointer;
  opacity: 0;
  transition: all 0.2s;
  z-index: 10;
}

.mermaid-wrapper:hover .mermaid-expand { opacity: 1; }
.mermaid-expand:hover {
  color: var(--accent);
  border-color: var(--accent);
  background: var(--bg);
  transform: scale(1.05);
}

/* ── Modal overlay ── */
.mermaid-overlay {
  position: fixed;
  inset: 0;
  z-index: 500;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.75);
  backdrop-filter: blur(6px);
  opacity: 0;
  transition: opacity 0.25s;
  cursor: zoom-out;
}

.mermaid-overlay.visible { opacity: 1; }

.mermaid-overlay-content {
  position: relative;
  width: 94vw;
  height: 90vh;
  background: var(--bg-secondary);
  border: 1px solid var(--border);
  border-radius: 14px;
  box-shadow: 0 24px 80px rgba(0, 0, 0, 0.5);
  overflow: hidden;
  cursor: default;
  transform: scale(0.92);
  transition: transform 0.25s;
}

.mermaid-overlay.visible .mermaid-overlay-content {
  transform: scale(1);
}

.mermaid-viewport {
  width: 100%;
  height: 100%;
  overflow: hidden;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: grab;
}

.mermaid-viewport:active { cursor: grabbing; }

.mermaid-viewport-inner {
  transform-origin: center center;
  transition: none;
}

.mermaid-viewport-inner svg {
  display: block;
  max-width: none;
  max-height: none;
}

.mermaid-overlay-toolbar {
  position: absolute;
  bottom: 20px;
  left: 50%;
  transform: translateX(-50%);
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 6px;
  background: var(--bg-tertiary);
  border: 1px solid var(--border);
  border-radius: 10px;
  box-shadow: 0 4px 16px rgba(0,0,0,0.3);
  z-index: 10;
}

.mermaid-overlay-toolbar button {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  background: transparent;
  border: 1px solid transparent;
  border-radius: 6px;
  color: var(--text-secondary);
  cursor: pointer;
  font-family: 'JetBrains Mono', monospace;
  font-size: 14px;
  font-weight: 600;
  transition: all 0.15s;
}

.mermaid-overlay-toolbar button:hover {
  color: var(--text);
  background: var(--bg);
  border-color: var(--border);
}

.mermaid-overlay-toolbar .zoom-label {
  min-width: 52px;
  text-align: center;
  font-family: 'JetBrains Mono', monospace;
  font-size: 11px;
  font-weight: 500;
  color: var(--text-secondary);
  pointer-events: none;
  user-select: none;
}

.mermaid-overlay-toolbar .separator {
  width: 1px;
  height: 20px;
  background: var(--border);
  margin: 0 4px;
}

.mermaid-overlay-close {
  position: absolute;
  top: 12px;
  right: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  background: var(--bg-tertiary);
  border: 1px solid var(--border);
  border-radius: 8px;
  color: var(--text-secondary);
  cursor: pointer;
  transition: all 0.2s;
  z-index: 10;
}

.mermaid-overlay-close:hover {
  color: var(--red);
  border-color: var(--red);
}

.mermaid-overlay-keys {
  position: absolute;
  top: 16px;
  left: 16px;
  display: flex;
  gap: 8px;
  font-size: 11px;
  color: var(--text-secondary);
  opacity: 0.5;
  pointer-events: none;
}

.mermaid-overlay-keys kbd {
  padding: 2px 6px;
  background: var(--bg-tertiary);
  border: 1px solid var(--border);
  border-radius: 4px;
  font-family: 'JetBrains Mono', monospace;
  font-size: 10px;
}

/* ── Task lists ── */
.content input[type="checkbox"] {
  appearance: none;
  width: 16px;
  height: 16px;
  border: 2px solid var(--border);
  border-radius: 4px;
  vertical-align: middle;
  margin-right: 6px;
  position: relative;
  top: -1px;
  cursor: default;
}

.content input[type="checkbox"]:checked {
  background: var(--accent);
  border-color: var(--accent);
}

.content input[type="checkbox"]:checked::after {
  content: '✓';
  color: white;
  font-size: 11px;
  position: absolute;
  top: -1px;
  left: 2px;
}

/* ── Scrollbar ── */
::-webkit-scrollbar { width: 8px; height: 8px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb {
  background: var(--border);
  border-radius: 4px;
}
::-webkit-scrollbar-thumb:hover { background: var(--text-secondary); }

/* ── Toast ── */
.toast {
  position: fixed;
  bottom: 24px;
  right: 24px;
  padding: 10px 18px;
  background: var(--bg-secondary);
  border: 1px solid var(--green);
  border-radius: 8px;
  font-size: 12px;
  color: var(--green);
  opacity: 0;
  transform: translateY(10px);
  transition: all 0.3s;
  pointer-events: none;
  z-index: 200;
}

.toast.show {
  opacity: 1;
  transform: translateY(0);
}
</style>
</head>
<body>
<div class="topbar">
  <div class="topbar-title">
    <svg width="18" height="18" viewBox="0 0 16 16" fill="currentColor">
      <path d="M3 5h4v1H3V5zm0 3h4V7H3v1zm0 2h4V9H3v1zm11-5h-4v1h4V5zm0 2h-4v1h4V7zm0 2h-4v1h4V9zm2-6v9c0 .55-.45 1-1 1H9.5l-1 1-1-1H2c-.55 0-1-.45-1-1V3c0-.55.45-1 1-1h5.5l1 1 1-1H15c.55 0 1 .45 1 1zm-8 .5L7.5 3H2v9h6V3.5zm7-.5H9.5l-.5.5V12h6V3z"/>
    </svg>
    <span>${fileName}</span>
    <div class="live-dot" title="Live reload active"></div>
  </div>
  <div class="topbar-actions">
    <button class="btn" id="theme-toggle" title="Toggle theme">
      <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor" id="theme-icon">
        <path d="M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1zm0 13V2a6 6 0 1 1 0 12z"/>
      </svg>
      <span id="theme-label">Light</span>
    </button>
    <button class="btn" id="toc-toggle" title="Table of contents">
      <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor">
        <path d="M2 4h12v1H2V4zm0 3h12v1H2V7zm0 3h8v1H2v-1z"/>
      </svg>
      TOC
    </button>
  </div>
</div>

<div class="content" id="content"></div>
<div class="toast" id="toast">Updated</div>

<div id="toc-panel" style="
  position: fixed; top: 53px; right: -320px; width: 300px; bottom: 0;
  background: var(--bg-secondary); border-left: 1px solid var(--border);
  padding: 24px; overflow-y: auto; transition: right 0.3s; z-index: 90;
  font-size: 13px;
">
  <div style="font-weight: 600; margin-bottom: 12px; color: var(--text-secondary); text-transform: uppercase; font-size: 11px; letter-spacing: 1px;">
    Table of Contents
  </div>
  <div id="toc-list"></div>
</div>

<style>
  #toc-list a {
    display: block;
    color: var(--text-secondary);
    text-decoration: none;
    padding: 5px 0;
    border-left: 2px solid transparent;
    padding-left: 12px;
    transition: all 0.2s;
    font-size: 13px;
  }
  #toc-list a:hover { color: var(--accent); border-left-color: var(--accent); }
  #toc-list a.h3 { padding-left: 28px; font-size: 12px; }
  #toc-list a.h4 { padding-left: 44px; font-size: 11px; }
</style>

<script>
const md = window.markdownit({
  html: true,
  linkify: true,
  typographer: true,
  highlight: (str, lang) => {
    if (lang && hljs.getLanguage(lang)) {
      try { return hljs.highlight(str, { language: lang }).value; } catch {}
    }
    return hljs.highlightAuto(str).value;
  }
});

const defaultFence = md.renderer.rules.fence.bind(md.renderer.rules);
md.renderer.rules.fence = (tokens, idx, options, env, slf) => {
  const token = tokens[idx];
  const code = token.content.trim();
  const info = (token.info || "").trim();

  const mermaidKeywords = ["graph", "flowchart", "sequenceDiagram", "classDiagram",
    "stateDiagram", "erDiagram", "gantt", "pie", "gitgraph", "mindmap", "timeline",
    "journey", "quadrantChart", "sankey", "xychart"];
  const firstWord = code.split(/[\s;]/)[0];
  const isMermaid = info === "mermaid" || mermaidKeywords.includes(firstWord);

  if (isMermaid) {
    const id = "mmd-" + Math.random().toString(36).slice(2, 9);
    return '<div class="mermaid-wrapper">' +
      '<div class="mermaid" id="' + id + '">' + code + '</div>' +
      '<button class="mermaid-expand" title="Expand" onclick="openMermaidModal(this.parentElement)">' +
        '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
          '<polyline points="15 3 21 3 21 9"/><polyline points="9 21 3 21 3 15"/>' +
          '<line x1="21" y1="3" x2="14" y2="10"/><line x1="3" y1="21" x2="10" y2="14"/>' +
        '</svg>' +
      '</button>' +
    '</div>';
  }
  return defaultFence(tokens, idx, options, env, slf);
};

function openMermaidModal(wrapper) {
  const svg = wrapper.querySelector(".mermaid svg");
  if (!svg) return;

  let scale = 1, panX = 0, panY = 0, dragging = false, dragStartX = 0, dragStartY = 0, panStartX = 0, panStartY = 0;

  const overlay = document.createElement("div");
  overlay.className = "mermaid-overlay";
  overlay.innerHTML =
    '<div class="mermaid-overlay-content">' +
      '<div class="mermaid-viewport">' +
        '<div class="mermaid-viewport-inner">' + svg.outerHTML + '</div>' +
      '</div>' +
      '<div class="mermaid-overlay-toolbar">' +
        '<button data-action="out" title="Zoom out (-)">−</button>' +
        '<span class="zoom-label">100%</span>' +
        '<button data-action="in" title="Zoom in (+)">+</button>' +
        '<div class="separator"></div>' +
        '<button data-action="fit" title="Fit to view (0)">Fit</button>' +
        '<button data-action="reset" title="Reset (R)">1:1</button>' +
      '</div>' +
      '<button class="mermaid-overlay-close" title="Close (Esc)">' +
        '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>' +
      '</button>' +
      '<div class="mermaid-overlay-keys">' +
        '<span><kbd>Scroll</kbd> zoom</span>' +
        '<span><kbd>Drag</kbd> pan</span>' +
        '<span><kbd>Esc</kbd> close</span>' +
      '</div>' +
    '</div>';

  const inner = overlay.querySelector(".mermaid-viewport-inner");
  const viewport = overlay.querySelector(".mermaid-viewport");
  const zoomLabel = overlay.querySelector(".zoom-label");

  function apply() {
    inner.style.transform = "translate(" + panX + "px," + panY + "px) scale(" + scale + ")";
    zoomLabel.textContent = Math.round(scale * 100) + "%";
  }

  function zoom(factor) {
    scale = Math.max(0.1, Math.min(10, scale * factor));
    apply();
  }

  function fit() {
    scale = 1; panX = 0; panY = 0;
    apply();
    const s = inner.querySelector("svg");
    if (!s) return;
    const vw = viewport.clientWidth;
    const vh = viewport.clientHeight;
    const rect = s.getBoundingClientRect();
    const sw = rect.width;
    const sh = rect.height;
    if (sw === 0 || sh === 0) return;
    scale = Math.min((vw * 0.9) / sw, (vh * 0.85) / sh);
    panX = 0; panY = 0;
    apply();
  }

  function resetZoom() { scale = 1; panX = 0; panY = 0; apply(); }

  viewport.addEventListener("wheel", (e) => {
    e.preventDefault();
    e.stopPropagation();
    zoom(e.deltaY > 0 ? 0.9 : 1.1);
  }, { passive: false });

  viewport.addEventListener("mousedown", (e) => {
    if (e.button !== 0) return;
    dragging = true;
    dragStartX = e.clientX;
    dragStartY = e.clientY;
    panStartX = panX;
    panStartY = panY;
    e.preventDefault();
  });

  const onMove = (e) => {
    if (!dragging) return;
    panX = panStartX + (e.clientX - dragStartX);
    panY = panStartY + (e.clientY - dragStartY);
    apply();
  };
  const onUp = () => { dragging = false; };
  window.addEventListener("mousemove", onMove);
  window.addEventListener("mouseup", onUp);

  overlay.querySelector('[data-action="in"]').onclick = () => zoom(1.3);
  overlay.querySelector('[data-action="out"]').onclick = () => zoom(1 / 1.3);
  overlay.querySelector('[data-action="reset"]').onclick = resetZoom;
  overlay.querySelector('[data-action="fit"]').onclick = fit;

  const close = () => {
    overlay.classList.remove("visible");
    setTimeout(() => overlay.remove(), 250);
    document.removeEventListener("keydown", onKey);
    window.removeEventListener("mousemove", onMove);
    window.removeEventListener("mouseup", onUp);
  };

  overlay.addEventListener("click", (e) => { if (e.target === overlay) close(); });
  overlay.querySelector(".mermaid-overlay-close").onclick = close;

  const onKey = (e) => {
    if (e.key === "Escape") close();
    else if (e.key === "=" || e.key === "+") zoom(1.3);
    else if (e.key === "-") zoom(1 / 1.3);
    else if (e.key === "0") fit();
    else if (e.key === "r" || e.key === "R") resetZoom();
  };
  document.addEventListener("keydown", onKey);

  document.body.appendChild(overlay);
  requestAnimationFrame(() => {
    overlay.classList.add("visible");
    setTimeout(fit, 50);
  });
}

function renderContent(text) {
  const scrollY = window.scrollY;
  const el = document.getElementById("content");
  el.innerHTML = md.render(text);

  mermaid.initialize({
    startOnLoad: false,
    theme: document.documentElement.classList.contains("light") ? "default" : "dark",
    securityLevel: "loose",
    fontFamily: "Inter, sans-serif",
  });

  document.querySelectorAll(".mermaid").forEach((node) => {
    const id = node.id;
    try {
      mermaid.render(id + "-svg", node.textContent.trim()).then(({ svg }) => {
        node.innerHTML = svg;
      });
    } catch {}
  });

  buildTOC();
  window.scrollTo(0, scrollY);
}

function buildTOC() {
  const headings = document.querySelectorAll(".content h1, .content h2, .content h3, .content h4");
  const list = document.getElementById("toc-list");
  list.innerHTML = "";
  headings.forEach((h, i) => {
    const id = "heading-" + i;
    h.id = id;
    const a = document.createElement("a");
    a.href = "#" + id;
    a.textContent = h.textContent;
    a.className = h.tagName.toLowerCase();
    list.appendChild(a);
  });
}

let tocOpen = false;
document.getElementById("toc-toggle").onclick = () => {
  tocOpen = !tocOpen;
  document.getElementById("toc-panel").style.right = tocOpen ? "0" : "-320px";
};

document.getElementById("theme-toggle").onclick = () => {
  document.documentElement.classList.toggle("light");
  const isLight = document.documentElement.classList.contains("light");
  document.getElementById("theme-label").textContent = isLight ? "Dark" : "Light";

  const link = document.getElementById("hljs-theme");
  link.href = isLight
    ? "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css"
    : "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css";

  document.querySelectorAll(".mermaid").forEach((node) => {
    const wrapper = node.closest(".mermaid-wrapper");
    if (wrapper) {
      const raw = wrapper.querySelector(".mermaid");
      if (raw && raw.__raw) {
        mermaid.initialize({
          startOnLoad: false,
          theme: isLight ? "default" : "dark",
          securityLevel: "loose",
          fontFamily: "Inter, sans-serif",
        });
        mermaid.render(raw.id + "-svg2", raw.__raw).then(({ svg }) => {
          raw.innerHTML = svg;
        });
      }
    }
  });
};

function showToast() {
  const t = document.getElementById("toast");
  t.classList.add("show");
  setTimeout(() => t.classList.remove("show"), 1500);
}

const evtSource = new EventSource("/events");
evtSource.onmessage = (e) => {
  const text = JSON.parse(e.data);
  renderContent(text);
  showToast();
};

fetch("/raw").then(r => r.text()).then(renderContent);
<\/script>
</body>
</html>`;

const server = createServer((req, res) => {
  if (req.url === "/events") {
    res.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
      "Access-Control-Allow-Origin": "*",
    });
    clients.push(res);
    req.on("close", () => {
      clients = clients.filter((c) => c !== res);
    });
    return;
  }

  if (req.url === "/raw") {
    const md = getMarkdown();
    res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
    res.end(md);
    return;
  }

  const localPath = join(fileDir, decodeURIComponent(req.url));
  const ext = extname(localPath).toLowerCase();
  if (MIME_TYPES[ext] && existsSync(localPath)) {
    try {
      const data = readFileSync(localPath);
      res.writeHead(200, { "Content-Type": MIME_TYPES[ext] });
      res.end(data);
      return;
    } catch {}
  }

  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  res.end(HTML);
});

const PORT = 4400 + Math.floor(Math.random() * 100);

server.listen(PORT, () => {
  const url = `http://localhost:${PORT}`;
  console.log(`\x1b[32m✓\x1b[0m Serving \x1b[1m${fileName}\x1b[0m at \x1b[36m${url}\x1b[0m`);
  console.log(`\x1b[90m  Live reload active · Ctrl+C to stop\x1b[0m`);
  try {
    execSync(`open "${url}"`);
  } catch {}
});

process.on("SIGINT", () => {
  unwatchFile(filePath);
  server.close();
  process.exit(0);
});
