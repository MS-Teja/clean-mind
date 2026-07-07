/* Clean Mind — site interactions
   - a live squarified treemap in the hero (the product's signature object)
   - copy-to-clipboard, install tabs, sticky-nav state, scroll reveals */

(function () {
  "use strict";

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ---------------- Copy to clipboard ---------------- */
  document.querySelectorAll("[data-copy]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const text = btn.getAttribute("data-copy");
      try {
        await navigator.clipboard.writeText(text);
      } catch (e) {
        const ta = document.createElement("textarea");
        ta.value = text;
        ta.style.position = "fixed";
        ta.style.opacity = "0";
        document.body.appendChild(ta);
        ta.select();
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

  /* ---------------- Install tabs ---------------- */
  const tabs = Array.from(document.querySelectorAll('[role="tab"]'));
  const panels = {
    "tab-mac": "panel-mac",
    "tab-linux": "panel-linux",
    "tab-win": "panel-win",
  };
  function selectTab(tab) {
    tabs.forEach((t) => {
      const on = t === tab;
      t.setAttribute("aria-selected", on ? "true" : "false");
      const panel = document.getElementById(panels[t.id]);
      if (panel) panel.setAttribute("data-active", on ? "true" : "false");
    });
  }
  tabs.forEach((tab, i) => {
    tab.addEventListener("click", () => selectTab(tab));
    tab.addEventListener("keydown", (e) => {
      if (e.key !== "ArrowRight" && e.key !== "ArrowLeft") return;
      e.preventDefault();
      const dir = e.key === "ArrowRight" ? 1 : -1;
      const next = tabs[(i + dir + tabs.length) % tabs.length];
      next.focus();
      selectTab(next);
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
          if (entry.isIntersecting) {
            entry.target.classList.add("in");
            io.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -8% 0px" }
    );
    reveals.forEach((el) => io.observe(el));
  }

  /* ---------------- Live treemap ----------------
     A squarified treemap of a sample ~/Projects scan, echoing the app.
     Sizes in MB; `tier` drives color (safe = green, else neutral terrain). */
  const canvas = document.getElementById("treemap");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");

  // Sample data mirrors the product screenshots (555 MB, 519 MB reclaimable).
  const items = [
    { label: "api-service", sub: "target", mb: 222, tier: "safe", kind: "folder" },
    { label: "webapp", sub: "node_modules", mb: 138, tier: "safe", kind: "folder" },
    { label: "data-science", sub: ".venv", mb: 101, tier: "safe", kind: "folder" },
    { label: "webapp", sub: ".next", mb: 48, tier: "safe", kind: "folder" },
    { label: "assets", sub: "media", mb: 22, tier: "file", kind: "file" },
    { label: "src", sub: "source", mb: 14, tier: "folder", kind: "folder" },
    { label: ".ssh", sub: "protected", mb: 6, tier: "protected", kind: "folder" },
    { label: "docs", sub: "", mb: 4, tier: "file", kind: "file" },
  ];

  const COLORS = {
    safe: "#2fd695",
    protected: "#3a423e",
    folder: "#3d5148",
    file: "#32424e",
  };
  const INK = "#e9efeb";
  const INK_ON_SAFE = "#04231a";

  // Squarified treemap layout (Bruls, Huizing, van Wijk).
  function squarify(data, x, y, w, h) {
    const total = data.reduce((s, d) => s + d.mb, 0);
    const scale = (w * h) / total;
    const nodes = data.map((d) => ({ ...d, area: d.mb * scale }));
    const rects = [];
    let row = [];
    let rx = x, ry = y, rw = w, rh = h;

    const worst = (row, len) => {
      if (!row.length) return Infinity;
      const s = row.reduce((a, r) => a + r.area, 0);
      const max = Math.max(...row.map((r) => r.area));
      const min = Math.min(...row.map((r) => r.area));
      const s2 = s * s, len2 = len * len;
      return Math.max((len2 * max) / s2, s2 / (len2 * min));
    };

    let i = 0;
    while (i < nodes.length) {
      const shortest = Math.min(rw, rh);
      const next = nodes[i];
      if (row.length === 0 || worst([...row, next], shortest) <= worst(row, shortest)) {
        row.push(next);
        i++;
      } else {
        layoutRow(row);
        row = [];
      }
    }
    if (row.length) layoutRow(row);
    return rects;

    function layoutRow(row) {
      const s = row.reduce((a, r) => a + r.area, 0);
      if (rw >= rh) {
        const rowW = s / rh;
        let oy = ry;
        row.forEach((r) => {
          const rectH = r.area / rowW;
          rects.push({ ...r, x: rx, y: oy, w: rowW, h: rectH });
          oy += rectH;
        });
        rx += rowW; rw -= rowW;
      } else {
        const rowH = s / rw;
        let ox = rx;
        row.forEach((r) => {
          const rectW = r.area / rowH;
          rects.push({ ...r, x: ox, y: ry, w: rectW, h: rowH });
          ox += rectW;
        });
        ry += rowH; rh -= rowH;
      }
    }
  }

  let rects = [];
  let dpr = 1;
  let W = 0, H = 0;

  function computeLayout() {
    const box = canvas.getBoundingClientRect();
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    W = box.width; H = box.height;
    canvas.width = Math.round(W * dpr);
    canvas.height = Math.round(H * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const pad = 6;
    rects = squarify(items, pad, pad, W - pad * 2, H - pad * 2);
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

  function drawTile(r, reveal) {
    const gap = 3;
    const x = r.x + gap, y = r.y + gap;
    const w = Math.max(0, r.w - gap * 2), h = Math.max(0, r.h - gap * 2);
    if (w <= 0 || h <= 0) return;

    const base = COLORS[r.tier] || COLORS.folder;
    ctx.globalAlpha = reveal;
    roundRect(x, y, w, h, 7);
    ctx.fillStyle = base;
    ctx.fill();

    // subtle top sheen for terrain feel
    if (r.tier !== "safe") {
      roundRect(x, y, w, h, 7);
      const g = ctx.createLinearGradient(0, y, 0, y + h);
      g.addColorStop(0, "rgba(255,255,255,0.05)");
      g.addColorStop(1, "rgba(0,0,0,0.10)");
      ctx.fillStyle = g;
      ctx.fill();
    }

    // labels only where they fit
    const onSafe = r.tier === "safe";
    ctx.globalAlpha = reveal;
    if (w > 78 && h > 40) {
      ctx.fillStyle = onSafe ? INK_ON_SAFE : INK;
      ctx.font = '600 13px "Space Grotesk", sans-serif';
      ctx.textBaseline = "top";
      ctx.fillText(r.label, x + 11, y + 10, w - 20);

      ctx.font = '500 11px "JetBrains Mono", monospace';
      ctx.fillStyle = onSafe ? "rgba(4,35,26,0.72)" : "rgba(233,239,235,0.6)";
      ctx.fillText(r.mb + " MB", x + 11, y + 28, w - 20);

      // reclaim badge for safe tiles with room
      if (onSafe && w > 96 && h > 66) {
        const bw = 60, bh = 20, bx = x + w - bw - 9, by = y + h - bh - 9;
        ctx.globalAlpha = reveal * 0.92;
        roundRect(bx, by, bw, bh, 10);
        ctx.fillStyle = "rgba(4,35,26,0.22)";
        ctx.fill();
        ctx.fillStyle = INK_ON_SAFE;
        ctx.font = '600 10px "JetBrains Mono", monospace';
        ctx.textBaseline = "middle";
        ctx.fillText("↻ safe", bx + 10, by + bh / 2 + 0.5);
        ctx.textBaseline = "top";
      }
    } else if (r.tier === "protected" && w > 26 && h > 26) {
      // lock glyph so protected never relies on color alone
      ctx.fillStyle = "rgba(233,239,235,0.5)";
      ctx.font = '600 12px "JetBrains Mono", monospace';
      ctx.fillText("🔒", x + w / 2 - 8, y + h / 2 - 8);
    }
    ctx.globalAlpha = 1;
  }

  let start = null;
  const DURATION = 900;

  function frame(ts) {
    if (start === null) start = ts;
    const t = Math.min(1, (ts - start) / DURATION);
    const eased = 1 - Math.pow(1 - t, 3);
    ctx.clearRect(0, 0, W, H);
    rects.forEach((r, i) => {
      // staggered reveal, largest tiles first
      const delay = (i / rects.length) * 0.5;
      const local = Math.max(0, Math.min(1, (eased - delay) / (1 - delay)));
      drawTile(r, local);
    });
    if (t < 1) requestAnimationFrame(frame);
  }

  function render() {
    ctx.clearRect(0, 0, W, H);
    rects.forEach((r) => drawTile(r, 1));
  }

  function init() {
    computeLayout();
    if (reduceMotion) {
      render();
    } else {
      start = null;
      requestAnimationFrame(frame);
    }
  }

  // Wait for fonts so labels don't reflow after paint.
  if (document.fonts && document.fonts.ready) {
    document.fonts.ready.then(init);
  } else {
    init();
  }

  let resizeTimer;
  window.addEventListener("resize", () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
      computeLayout();
      render();
    }, 120);
  });
})();
