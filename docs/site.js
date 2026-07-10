/* Clean Mind — document interactions.
   The page is the conductor: it computes scroll progress for §02 and
   dispatches "figure:progress"; figure.js only draws what it's told. */

(function () {
  "use strict";

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const REPO = "MS-Teja/clean-mind";
  const clamp01 = (v) => Math.max(0, Math.min(1, v));
  const easeOut = (t) => 1 - Math.pow(1 - t, 3);

  /* ---------------- Copy buttons ---------------- */
  document.querySelectorAll(".copy").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const cmd = btn.closest(".cmd");
      const text = btn.getAttribute("data-copy") ||
        (cmd && cmd.querySelector("code") ? cmd.querySelector("code").textContent : "");
      try {
        await navigator.clipboard.writeText(text);
      } catch (e) {
        const ta = document.createElement("textarea");
        ta.value = text; ta.style.position = "fixed"; ta.style.opacity = "0";
        document.body.appendChild(ta); ta.select();
        try { document.execCommand("copy"); } catch (_) {}
        document.body.removeChild(ta);
      }
      btn.classList.add("copied");
      const prev = btn.textContent;
      btn.textContent = "copied";
      setTimeout(() => { btn.classList.remove("copied"); btn.textContent = prev; }, 1500);
    });
  });

  /* ---------------- Reveals ---------------- */
  const reveals = document.querySelectorAll(".reveal");
  if (reduceMotion || !("IntersectionObserver" in window)) {
    reveals.forEach((el) => el.classList.add("in"));
  } else {
    const io = new IntersectionObserver((entries) => {
      entries.forEach((en) => {
        if (en.isIntersecting) { en.target.classList.add("in"); io.unobserve(en.target); }
      });
    }, { threshold: 0.15, rootMargin: "0px 0px -6% 0px" });
    reveals.forEach((el) => io.observe(el));
  }

  /* ---------------- Masthead file counter ---------------- */
  const counter = document.getElementById("file-counter");
  if (counter && !reduceMotion) {
    const target = parseInt(counter.getAttribute("data-target"), 10) || 0;
    const t0 = performance.now(), dur = 1500;
    (function tick(now) {
      const t = clamp01((now - t0) / dur);
      counter.textContent = Math.round(easeOut(t) * target).toLocaleString("en-US");
      if (t < 1) requestAnimationFrame(tick);
    })(t0);
  }

  /* ---------------- §02 — scroll drives the figure ---------------- */
  const runway = document.getElementById("runway");
  const steps = Array.from(document.querySelectorAll(".step"));
  const railDots = Array.from(document.querySelectorAll(".step-rail li"));
  const reclaim = document.getElementById("reclaim-counter");
  const reclaimMb = document.getElementById("reclaim-mb");
  const RECLAIM_TOTAL = 519;

  let lastP = -1;
  function onScroll() {
    if (!runway) return;
    const rect = runway.getBoundingClientRect();
    const span = runway.offsetHeight - window.innerHeight;
    let p = span > 0 ? clamp01(-rect.top / span) : 0;

    // reduced motion: discrete states, no scrubbed tweening
    if (reduceMotion) p = (Math.min(3, Math.floor(p * 4)) + 0.5) / 4;
    if (p === lastP) return;
    lastP = p;

    document.dispatchEvent(new CustomEvent("figure:progress", { detail: { p } }));

    const u = p * 4;
    const seg = Math.min(3, Math.floor(u));
    steps.forEach((el, i) => el.classList.toggle("is-active", i === seg));
    railDots.forEach((el, i) => el.classList.toggle("is-active", i === seg));

    if (reclaim) {
      const cleanT = clamp01(u - 3);
      const show = u >= 3.02;
      reclaim.hidden = !show;
      if (show && reclaimMb) {
        reclaimMb.textContent = "+" + Math.round(easeOut(cleanT) * RECLAIM_TOTAL);
      }
    }
  }
  let ticking = false;
  window.addEventListener("scroll", () => {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(() => { ticking = false; onScroll(); });
  }, { passive: true });
  window.addEventListener("load", onScroll);
  onScroll();

  /* ---------------- Figure fallback (no WebGL) ---------------- */
  document.addEventListener("figure:fallback", () => {
    const fb = document.getElementById("fig-fallback");
    const hero = document.getElementById("axo-hero");
    if (!fb || !hero) return;
    const svg = hero.cloneNode(true);
    svg.removeAttribute("id");
    const pat = svg.querySelector("pattern"); if (pat) pat.removeAttribute("id");
    fb.appendChild(svg);
    fb.hidden = false;
    // mirror the chapter on the static figure
    const setState = () => {
      const seg = Math.min(3, Math.floor(clamp01(lastP) * 4));
      fb.className = "fig-fallback st-" + seg;
    };
    document.addEventListener("figure:progress", setState);
    setState();
  });

  /* ---------------- §04 — pseudonymization flip ---------------- */
  const ledger = document.getElementById("ledger");
  if (ledger && !reduceMotion && "IntersectionObserver" in window) {
    const GLYPHS = "abcdefghijklmnopqrstuvwxyz0123456789-_/";
    const scramble = (el) => {
      const final = el.getAttribute("data-final") || el.textContent;
      const t0 = performance.now(), dur = 900;
      (function frame(now) {
        const t = clamp01((now - t0) / dur);
        const settled = Math.floor(t * final.length);
        let out = final.slice(0, settled);
        for (let i = settled; i < final.length; i++) {
          const ch = final[i];
          out += (ch === "/" || ch === "-") ? ch : GLYPHS[(Math.random() * GLYPHS.length) | 0];
        }
        el.textContent = out;
        if (t < 1) requestAnimationFrame(frame); else el.textContent = final;
      })(t0);
    };
    const io = new IntersectionObserver((entries) => {
      entries.forEach((en) => {
        if (!en.isIntersecting) return;
        io.disconnect();
        ledger.querySelectorAll(".pseudo").forEach((el, i) => {
          setTimeout(() => scramble(el), i * 220);
        });
      });
    }, { threshold: 0.5 });
    io.observe(ledger);
  }

  /* ---------------- §06 — ticker loop ---------------- */
  const track = document.getElementById("ticker-track");
  if (track) track.innerHTML += track.innerHTML; /* duplicate once → seamless -50% loop */

  /* ---------------- Appendix A — resolve the latest release ---------------- */
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
      if (ver) document.querySelectorAll("[data-ver]").forEach((el) => { el.textContent = ver; });
      const assets = rel.assets || [];
      const find = (fn) => assets.find((a) => fn(a.name));
      const matched = {
        "dmg":       find((n) => n.endsWith(".dmg")),
        "win-x64":   find((n) => n.includes("windows-x64") && n.endsWith(".zip")),
        "win-arm64": find((n) => n.includes("windows-arm64") && n.endsWith(".zip")),
        "deb-amd64": find((n) => n.endsWith("amd64.deb")),
        "deb-arm64": find((n) => n.endsWith("arm64.deb")),
        "tgz-x64":   find((n) => n.includes("linux-x64") && n.endsWith(".tar.gz")),
        "tgz-arm64": find((n) => n.includes("linux-arm64") && n.endsWith(".tar.gz")),
      };
      Object.keys(matched).forEach((key) => {
        const a = matched[key];
        if (!a) return;
        document.querySelectorAll('[data-dl="' + key + '"]').forEach((el) => { el.href = a.browser_download_url; });
        document.querySelectorAll('[data-size="' + key + '"]').forEach((el) => { el.textContent = humanSize(a.size); });
        document.querySelectorAll('[data-name="' + key + '"]').forEach((el) => { el.textContent = a.name; });
      });
    })
    .catch(() => { /* markup already points at the releases page */ });
})();
