/* Clean Mind — fig. 02, the performing figure.
   An axonometric treemap drawn like a technical illustration (white ground,
   ink edges, flat fills) that acts out SCAN → UNDERSTAND → CLASSIFY → CLEAN.
   It is a pure function of scroll progress: site.js dispatches
   "figure:progress" with detail.p in [0,1]; nothing here free-runs.
   If WebGL is unavailable it dispatches "figure:fallback" and site.js
   swaps in the static SVG from the masthead. */

import * as THREE from "./vendor/three.module.js";

(function () {
  "use strict";

  const host = document.getElementById("fig3d");
  const canvas = document.getElementById("figure");
  const labelHost = document.getElementById("fig-labels");
  if (!host || !canvas) return;

  /* ---------- WebGL probe ---------- */
  function webglOK() {
    try {
      const c = document.createElement("canvas");
      return !!(window.WebGLRenderingContext &&
        (c.getContext("webgl2") || c.getContext("webgl")));
    } catch (e) { return false; }
  }
  if (!webglOK()) {
    canvas.remove();
    document.dispatchEvent(new CustomEvent("figure:fallback"));
    return;
  }

  /* ---------- Sample scan (mirrors fig. 01 exactly) ---------- */
  const GAP = 0.14;
  const ITEMS = [
    { id: "target",       mb: 222, tier: "safe",      cmd: "↻ cargo build", x: 0,       y: 0,      w: 4.4698, h: 8.0    },
    { id: "node_modules", mb: 138, tier: "safe",      cmd: "↻ npm install", x: 4.4698,  y: 0,      w: 4.348,  h: 5.1123 },
    { id: ".venv",        mb: 101, tier: "safe",      cmd: "↻ pip install", x: 8.8178,  y: 0,      w: 3.1822, h: 5.1123 },
    { id: ".next",        mb: 48,  tier: "safe",      cmd: null,                 x: 4.4698,  y: 5.1123, w: 2.6774, h: 2.8877 },
    { id: "Downloads",    mb: 31,  tier: "review",    cmd: null,                 x: 7.1472,  y: 5.1123, w: 1.7292, h: 2.8877 },
    { id: "Photos",       mb: 22,  tier: "protected", cmd: null,                 x: 8.8764,  y: 5.1123, w: 2.0081, h: 1.7647 },
    { id: "src",          mb: 14,  tier: "plain",     cmd: null,                 x: 8.8764,  y: 6.877,  w: 2.0081, h: 1.123  },
    { id: "dist",         mb: 10,  tier: "safe",      cmd: null,                 x: 10.8844, y: 5.1123, w: 1.1156, h: 1.4439 },
    { id: ".ssh",         mb: 6,   tier: "protected", cmd: null,                 x: 10.8844, y: 6.5561, w: 1.1156, h: 0.8663 },
    { id: "docs",         mb: 4,   tier: "plain",     cmd: null,                 x: 10.8844, y: 7.4225, w: 1.1156, h: 0.5775 },
  ];
  const PLAN_W = 12, PLAN_D = 8;
  const blockHeight = (mb) => 0.5 + 3.0 * Math.sqrt(mb / 222);

  /* ---------- Palette (matches styles.css tokens) ---------- */
  const INK = 0x141715;
  const FACES = {
    plain:     { t: 0xffffff, e: 0xeceae2, s: 0xe1dfd5 },
    safe:      { t: 0x8feacb, e: 0x63d5ad, s: 0x52c79f },
    review:    { t: 0xf3dda9, e: 0xe3c78c, s: 0xd5b97c },
    protected: { t: 0xf3f2ec, e: 0xe6e4da, s: 0xdbd9cd },
  };

  /* ---------- Renderer / scene ---------- */
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
  renderer.setClearColor(0x000000, 0);
  const scene = new THREE.Scene();
  const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 200);

  /* ground sheet + hairline frame */
  const groundGeo = new THREE.PlaneGeometry(PLAN_W + 1.2, PLAN_D + 1.2);
  const ground = new THREE.Mesh(
    groundGeo,
    new THREE.MeshBasicMaterial({ color: 0xf1f0ea })
  );
  ground.rotation.x = -Math.PI / 2;
  ground.position.y = -0.015;
  scene.add(ground);
  const groundEdge = new THREE.LineSegments(
    new THREE.EdgesGeometry(groundGeo),
    new THREE.LineBasicMaterial({ color: INK, transparent: true, opacity: 0.22 })
  );
  groundEdge.rotation.x = -Math.PI / 2;
  groundEdge.position.y = -0.01;
  scene.add(groundEdge);

  /* diagonal hatch for protected tops (appears during CLASSIFY) */
  function hatchTexture() {
    const c = document.createElement("canvas");
    c.width = c.height = 64;
    const g = c.getContext("2d");
    g.strokeStyle = "rgba(20, 23, 21, 0.6)";
    g.lineWidth = 2.4;
    for (let x = -64; x <= 128; x += 16) {
      g.beginPath(); g.moveTo(x, -4); g.lineTo(x + 72, 68); g.stroke();
    }
    return c;
  }
  const hatchCanvas = hatchTexture();

  /* blocks — flat per-face colors + ink edges, like the printed figure */
  const blocks = ITEMS.map((it, i) => {
    const w = it.w - 2 * GAP, d = it.h - 2 * GAP, h = blockHeight(it.mb);
    const cx = it.x + it.w / 2 - PLAN_W / 2;
    const cz = it.y + it.h / 2 - PLAN_D / 2;

    const geo = new THREE.BoxGeometry(w, h, d);
    const plain = FACES.plain, tier = FACES[it.tier];
    // face order: px, nx, py, ny, pz, nz
    const mats = [
      new THREE.MeshBasicMaterial({ color: plain.e, transparent: true }), // px east
      new THREE.MeshBasicMaterial({ color: plain.e, transparent: true }), // nx
      new THREE.MeshBasicMaterial({ color: plain.t, transparent: true }), // py top
      new THREE.MeshBasicMaterial({ color: plain.t, transparent: true }), // ny
      new THREE.MeshBasicMaterial({ color: plain.s, transparent: true }), // pz south
      new THREE.MeshBasicMaterial({ color: plain.s, transparent: true }), // nz
    ];
    const mesh = new THREE.Mesh(geo, mats);
    const edges = new THREE.LineSegments(
      new THREE.EdgesGeometry(geo),
      new THREE.LineBasicMaterial({ color: INK, transparent: true })
    );
    mesh.add(edges);
    let hatch = null;
    if (it.tier === "protected") {
      const tex = new THREE.CanvasTexture(hatchCanvas);
      tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
      tex.repeat.set(w / 1.4, d / 1.4);
      hatch = new THREE.Mesh(
        new THREE.PlaneGeometry(w, d),
        new THREE.MeshBasicMaterial({ map: tex, transparent: true, opacity: 0 })
      );
      hatch.rotation.x = -Math.PI / 2;
      hatch.position.y = h / 2 + 0.01;
      mesh.add(hatch);
    }
    scene.add(mesh);
    return {
      it, mesh, edges, h, hatch,
      base: { x: cx, z: cz },
      colors: {
        plain: [new THREE.Color(plain.e), new THREE.Color(plain.t), new THREE.Color(plain.s)],
        tier:  [new THREE.Color(tier.e),  new THREE.Color(tier.t),  new THREE.Color(tier.s)],
      },
      stagger: i / ITEMS.length,
    };
  });

  /* ---------- Labels (DOM, projected each render) ---------- */
  const LABELED = [
    { id: "target",       lines: ["target", "222 MB"], cmd: "↻ cargo build" },
    { id: "node_modules", lines: ["node_modules", "138 MB"], cmd: "↻ npm install" },
    { id: ".venv",        lines: [".venv", "101 MB"], cmd: "↻ pip install" },
    { id: "Photos",       lines: ["Photos", "22 MB · protected \u{1f512}"], cmd: null },
  ];
  const labels = LABELED.map((spec) => {
    const el = document.createElement("span");
    el.className = "fig-lbl";
    el.innerHTML =
      "<b>" + spec.lines[0] + "</b><span class=\"mb\">" + spec.lines[1] + "</span>" +
      (spec.cmd ? "<span class=\"regen\">" + spec.cmd + "</span>" : "");
    labelHost.appendChild(el);
    return { el, block: blocks.find((b) => b.it.id === spec.id) };
  });

  /* ---------- Camera path (spherical keyframes per chapter) ---------- */
  // [azimuth°, elevation°, frustum half-height, lookAt-y]
  const CAM = [
    { a: 38, e: 27, s: 8.0, ty: 1.1 },  // 02a scan — low sweep
    { a: 24, e: 30, s: 7.6, ty: 1.1 },  //      (end of sweep)
    { a: 18, e: 87, s: 5.7, ty: 0.0 },  // 02b understand — top-down treemap
    { a: 44, e: 52, s: 7.0, ty: 0.8 },  // 02c classify — three-quarter
    { a: 52, e: 30, s: 8.2, ty: 1.4 },  // 02d clean — watch them lift away
  ];
  const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
  const easeOut = (t) => 1 - Math.pow(1 - t, 3);
  const clamp01 = (v) => Math.max(0, Math.min(1, v));
  const lerp = (a, b, t) => a + (b - a) * t;

  function camAt(p) {
    // p in [0,1] across 4 chapters → keyframe span [0..4]
    const u = p * 4;
    const i = Math.min(3, Math.floor(u));
    const t = easeInOut(clamp01(u - i));
    const A = CAM[i], B = CAM[i + 1];
    return {
      a: THREE.MathUtils.degToRad(lerp(A.a, B.a, t)),
      e: THREE.MathUtils.degToRad(lerp(A.e, B.e, t)),
      s: lerp(A.s, B.s, t),
      ty: lerp(A.ty, B.ty, t),
    };
  }

  /* ---------- State application: everything derives from p ---------- */
  let progress = 0;
  let width = 0, height = 0;

  function apply(p) {
    const u = p * 4;                       // chapter-space
    const seg = Math.min(3, Math.floor(u));

    // camera
    const c = camAt(p);
    const R = 60;
    camera.position.set(
      Math.cos(c.e) * Math.cos(c.a) * R,
      Math.sin(c.e) * R,
      Math.cos(c.e) * Math.sin(c.a) * R
    );
    const aspect = width / Math.max(1, height);
    camera.left = -c.s * aspect; camera.right = c.s * aspect;
    camera.top = c.s; camera.bottom = -c.s;
    camera.lookAt(0, c.ty, 0);
    camera.updateProjectionMatrix();

    // per-block state — the rise gets a head start so the scene is never empty
    const riseT = clamp01(0.3 + u / 0.75);       // "mid-scan" at entry, done early in 02a
    const classifyT = clamp01(u - 2);            // 0→1 across 02c
    const cleanT = clamp01(u - 3);               // 0→1 across 02d

    blocks.forEach((b) => {
      // 02a — rise from the sheet, staggered
      const local = clamp01((riseT - b.stagger * 0.55) / 0.45);
      const grow = easeOut(local);
      const sy = Math.max(0.028, grow);
      b.mesh.scale.set(1, sy, 1);

      // 02d — verified-safe blocks lift off the page and fade
      let lift = 0, fade = 1;
      if (b.it.tier === "safe" && cleanT > 0) {
        const ft = clamp01((cleanT - b.stagger * 0.25) / 0.7);
        lift = easeInOut(ft) * 10;
        fade = 1 - clamp01(ft * 1.5);
      }
      b.mesh.position.set(b.base.x, (b.h * sy) / 2 + lift, b.base.z);

      // 02c — tier colors arrive, staggered
      const ct = clamp01((classifyT - b.stagger * 0.4) / 0.55);
      const mix = easeInOut(ct);
      const [pe, pt, ps] = b.colors.plain, [te, tt, ts] = b.colors.tier;
      b.mesh.material[0].color.lerpColors(pe, te, mix);
      b.mesh.material[1].color.lerpColors(pe, te, mix);
      b.mesh.material[2].color.lerpColors(pt, tt, mix);
      b.mesh.material[3].color.lerpColors(pt, tt, mix);
      b.mesh.material[4].color.lerpColors(ps, ts, mix);
      b.mesh.material[5].color.lerpColors(ps, ts, mix);

      const op = grow < 1 ? grow : fade;
      b.mesh.material.forEach((m) => { m.opacity = op; });
      b.edges.material.opacity = op;
      if (b.hatch) b.hatch.material.opacity = mix * 0.5 * op;
      b.mesh.visible = op > 0.01;
    });

    renderer.render(scene, camera);

    // labels: appear for 02b + 02c, follow their blocks, leave for 02d
    const labelsOn = u > 1.25 && u < 3.15;
    const v = new THREE.Vector3();
    labels.forEach((L) => {
      const b = L.block;
      const on = labelsOn && b.mesh.visible;
      L.el.classList.toggle("on", !!on);
      if (!on) return;
      v.set(b.base.x, b.mesh.position.y + (b.h * b.mesh.scale.y) / 2, b.base.z);
      v.project(camera);
      L.el.style.left = ((v.x * 0.5 + 0.5) * 100).toFixed(2) + "%";
      /* clamp so the label never leaves the overflow-hidden box */
      const topPx = (-v.y * 0.5 + 0.5) * height;
      L.el.style.top = Math.max(topPx, L.el.offsetHeight + 2).toFixed(1) + "px";
    });
  }

  /* ---------- Size / render-on-demand ---------- */
  function resize() {
    const box = host.getBoundingClientRect();
    width = Math.max(1, Math.round(box.width));
    height = Math.max(1, Math.round(box.height));
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    renderer.setSize(width, height, false);
    apply(progress);
  }
  window.addEventListener("resize", resize);
  resize();

  document.addEventListener("figure:progress", (ev) => {
    progress = clamp01(ev.detail && ev.detail.p || 0);
    apply(progress);
  });
})();
