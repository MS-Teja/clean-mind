/* Clean Mind — site interactions
   - copy-to-clipboard
   - sticky-nav state, scroll reveals
   - resolve download links from the latest GitHub release
   - draw the flat 2D treemap only when the 3D skyline falls back */

(function () {
  "use strict";

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const REPO = "MS-Teja/clean-mind";
  const RELEASES = "https://github.com/" + REPO + "/releases/latest";

  /* ---------------- Copy to clipboard ---------------- */
  document.querySelectorAll("[data-copy]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const text = btn.getAttribute("data-copy");
      try {
        await navigator.clipboard.writeText(text);
      } catch (e) {
        const ta = document.createElement("textarea");
        ta.value = text; ta.style.position = "fixed"; ta.style.opacity = "0";
        document.body.appendChild(ta); ta.select();
        try { document.execCommand("copy"); } catch (_) {}
        document.body.removeChild(ta);
      }
      const label = btn.querySelector(".label");
      const original = label ? label.textContent : btn.textContent;
      btn.classList.add("copied");
      if (label) label.textContent = "Copied"; else btn.textContent = "Copied";
      setTimeout(() => {
        btn.classList.remove("copied");
        if (label) label.textContent = original; else btn.textContent = original;
      }, 1600);
    });
  });

  /* ---------------- Sticky nav shadow ---------------- */
  const nav = document.getElementById("nav");
  const onScroll = () => nav.classList.toggle("scrolled", window.scrollY > 8);
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  /* ---------------- Scroll reveals ---------------- */
  const reveals = document.querySelectorAll(".reveal");
  if (reduceMotion || !("IntersectionObserver" in window)) {
    reveals.forEach((el) => el.classList.add("in"));
  } else {
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) { entry.target.classList.add("in"); io.unobserve(entry.target); }
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -8% 0px" }
    );
    reveals.forEach((el) => io.observe(el));
  }

  /* ---------------- Resolve downloads from the latest release ----------------
     Assets are CleanMind-<ver>-macos.dmg / -windows-x64.zip / -linux-x64.tar.gz.
     Buttons default to the releases page; we upgrade them to direct links plus
     live version + size. Any failure just leaves the safe defaults. */
  function humanSize(bytes) {
    if (!bytes && bytes !== 0) return "";
    const mb = bytes / (1024 * 1024);
    if (mb >= 1024) return (mb / 1024).toFixed(1) + " GB";
    return (mb < 10 ? mb.toFixed(1) : Math.round(mb)) + " MB";
  }
  fetch("https://api.github.com/repos/" + REPO + "/releases/latest", {
    headers: { Accept: "application/vnd.github+json" },
  })
    .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
    .then((rel) => {
      const ver = (rel.tag_name || rel.name || "").trim();
      if (ver) {
        document.querySelectorAll("[data-ver]").forEach((el) => { el.textContent = ver; });
      }
      const assets = rel.assets || [];
      const pick = (needle, ext) =>
        assets.find((a) => a.name.includes(needle) && a.name.endsWith(ext));
      const byOs = {
        mac: pick("macos", ".dmg"),
        windows: pick("windows", ".zip"),
        linux: pick("linux", ".tar.gz"),
      };
      Object.keys(byOs).forEach((os) => {
        const asset = byOs[os];
        if (!asset) return;
        document.querySelectorAll('[data-dl="' + os + '"]').forEach((a) => {
          a.href = asset.browser_download_url;
        });
        const size = humanSize(asset.size);
        document.querySelectorAll('[data-size="' + os + '"]').forEach((el) => {
          el.textContent = size;
        });
      });
    })
    .catch(() => { /* keep the releases-page fallbacks already in the markup */ });

  /* ---------------- Flat 2D treemap (only if the 3D skyline can't run) ----------------
     scene.js dispatches "skyline:fallback" when WebGL/motion is unavailable. */
  let drawn = false;
  function drawFallbackTreemap() {
    if (drawn) return;
    const canvas = document.getElementById("treemap");
    if (!canvas) return;
    drawn = true;
    const ctx = canvas.getContext("2d");

    const items = [
      { label: "target", mb: 222, tier: "safe" },
      { label: "node_modules", mb: 138, tier: "safe" },
      { label: ".venv", mb: 101, tier: "safe" },
      { label: ".next", mb: 48, tier: "safe" },
      { label: "Photos", mb: 22, tier: "protected" },
      { label: "src", mb: 14, tier: "folder" },
      { label: ".ssh", mb: 6, tier: "protected" },
      { label: "docs", mb: 4, tier: "file" },
    ];
    const COLORS = { safe: "#2fd695", protected: "#3a423e", folder: "#3d5148", file: "#32424e" };
    const INK = "#e9efeb", INK_ON_SAFE = "#04231a";

    function squarify(data, x, y, w, h) {
      const total = data.reduce((s, d) => s + d.mb, 0);
      const scale = (w * h) / total;
      const nodes = data.map((d) => ({ ...d, area: d.mb * scale }));
      const rects = [];
      let rx = x, ry = y, rw = w, rh = h, row = [];
      const worst = (row, len) => {
        if (!row.length) return Infinity;
        const s = row.reduce((a, r) => a + r.area, 0);
        const mx = Math.max(...row.map((r) => r.area)), mn = Math.min(...row.map((r) => r.area));
        const s2 = s * s, l2 = len * len;
        return Math.max((l2 * mx) / s2, s2 / (l2 * mn));
      };
      let i = 0;
      while (i < nodes.length) {
        const shortest = Math.min(rw, rh), next = nodes[i];
        if (row.length === 0 || worst([...row, next], shortest) <= worst(row, shortest)) { row.push(next); i++; }
        else { layoutRow(row); row = []; }
      }
      if (row.length) layoutRow(row);
      return rects;
      function layoutRow(row) {
        const s = row.reduce((a, r) => a + r.area, 0);
        if (rw >= rh) {
          const rowW = s / rh; let oy = ry;
          row.forEach((r) => { const rh2 = r.area / rowW; rects.push({ ...r, x: rx, y: oy, w: rowW, h: rh2 }); oy += rh2; });
          rx += rowW; rw -= rowW;
        } else {
          const rowH = s / rw; let ox = rx;
          row.forEach((r) => { const rw2 = r.area / rowH; rects.push({ ...r, x: ox, y: ry, w: rw2, h: rowH }); ox += rw2; });
          ry += rowH; rh -= rowH;
        }
      }
    }

    function roundRect(x, y, w, h, r) {
      r = Math.min(r, w / 2, h / 2);
      ctx.beginPath();
      ctx.moveTo(x + r, y);
      ctx.arcTo(x + w, y, x + w, y + h, r);
      ctx.arcTo(x + w, y + h, x, y + h, r);
      ctx.arcTo(x, y + h, x, y, r);
      ctx.arcTo(x, y, x + w, y, r);
      ctx.closePath();
    }

    let rects = [], W = 0, H = 0;
    function layout() {
      const box = canvas.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      W = box.width; H = box.height;
      canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      rects = squarify(items, 6, 6, W - 12, H - 12);
    }
    function render() {
      ctx.clearRect(0, 0, W, H);
      const gap = 3;
      rects.forEach((r) => {
        const x = r.x + gap, y = r.y + gap, w = Math.max(0, r.w - gap * 2), h = Math.max(0, r.h - gap * 2);
        if (w <= 0 || h <= 0) return;
        roundRect(x, y, w, h, 7);
        ctx.fillStyle = COLORS[r.tier] || COLORS.folder; ctx.fill();
        const onSafe = r.tier === "safe";
        if (w > 78 && h > 40) {
          ctx.fillStyle = onSafe ? INK_ON_SAFE : INK;
          ctx.font = '600 13px "Space Grotesk", sans-serif';
          ctx.textBaseline = "top";
          ctx.fillText(r.label, x + 11, y + 10, w - 20);
          ctx.font = '500 11px "JetBrains Mono", monospace';
          ctx.fillStyle = onSafe ? "rgba(4,35,26,0.72)" : "rgba(233,239,235,0.6)";
          ctx.fillText(r.mb + " MB", x + 11, y + 28, w - 20);
        } else if (r.tier === "protected" && w > 24 && h > 24) {
          ctx.fillStyle = "rgba(233,239,235,0.5)";
          ctx.font = '600 12px "JetBrains Mono", monospace';
          ctx.fillText("🔒", x + w / 2 - 8, y + h / 2 - 8);
        }
      });
    }
    function go() { layout(); render(); }
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(go); else go();
    let t;
    window.addEventListener("resize", () => { clearTimeout(t); t = setTimeout(go, 120); });
  }

  document.addEventListener("skyline:fallback", drawFallbackTreemap);
  // safety: if the fallback is already visible (e.g. no module support), draw it
  const fb = document.getElementById("skyline-fallback");
  if (fb && !fb.hidden) drawFallbackTreemap();
})();
