/* Clean Mind — the 3D "disk skyline".
   The product's core object, made dimensional: each folder is an extruded
   block, footprint = its treemap tile, height ∝ size. Mint blocks are safe to
   reclaim; dark blocks are folders/files; grey blocks are protected.
   Falls back to the flat 2D treemap when WebGL or motion isn't available. */

import * as THREE from "./vendor/three.module.js";

const host = document.getElementById("skyline");
const fallback = document.getElementById("skyline-fallback");
const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

function useFallback() {
  if (host) host.style.display = "none";
  if (fallback) fallback.hidden = false;
  // let site.js know to draw the 2D canvas
  document.dispatchEvent(new CustomEvent("skyline:fallback"));
}

// WebGL support probe
function webglOK() {
  try {
    const c = document.createElement("canvas");
    return !!(window.WebGLRenderingContext && (c.getContext("webgl") || c.getContext("experimental-webgl")));
  } catch (e) { return false; }
}

if (!host || !webglOK()) {
  useFallback();
} else {
  boot().catch(useFallback);
}

async function boot() {
  /* ---- The sample scan (mirrors the app: 555 MB, 519 MB reclaimable) ---- */
  const items = [
    { label: "target",        parent: "api-service",  mb: 222, tier: "safe" },
    { label: "node_modules",  parent: "webapp",       mb: 138, tier: "safe" },
    { label: ".venv",         parent: "data-science", mb: 101, tier: "safe" },
    { label: ".next",         parent: "webapp",       mb: 48,  tier: "safe" },
    { label: "DerivedData",   parent: "ios-app",      mb: 31,  tier: "safe" },
    { label: "Photos",        parent: "~",            mb: 24,  tier: "protected" },
    { label: "src",           parent: "api-service",  mb: 15,  tier: "folder" },
    { label: "Documents",     parent: "~",            mb: 13,  tier: "protected" },
    { label: "assets",        parent: "webapp",       mb: 11,  tier: "file" },
    { label: ".pub-cache",    parent: "~/.pub",       mb: 9,   tier: "safe" },
    { label: ".ssh",          parent: "~",            mb: 5,   tier: "protected" },
    { label: "docs",          parent: "api-service",  mb: 4,   tier: "file" },
  ];

  /* ---- Squarified treemap → 2D rects on a plane ---- */
  const PLANE_W = 12, PLANE_D = 8;
  const rects = squarify(items.slice(), 0, 0, PLANE_W, PLANE_D);

  /* ---- Renderer ---- */
  const renderer = new THREE.WebGLRenderer({ canvas: host, antialias: true, alpha: true });
  renderer.setClearColor(0x000000, 0);
  const DPR = Math.min(window.devicePixelRatio || 1, 2);
  renderer.setPixelRatio(DPR);
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.12;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;

  const scene = new THREE.Scene();
  scene.fog = new THREE.Fog(0x0b0f0d, 20, 42);

  const camera = new THREE.PerspectiveCamera(38, 1, 0.1, 100);
  const CAM = { r: 20, phi: 0.62, theta: 0.62 }; // spherical-ish framing
  function placeCamera(px = 0, py = 0) {
    // base position, plus gentle mouse parallax
    const theta = CAM.theta + px * 0.28;
    const phi = CAM.phi + py * 0.16;
    camera.position.set(
      Math.sin(theta) * CAM.r * Math.cos(phi),
      Math.cos(phi) * CAM.r * 0.62 + 3.2,
      Math.cos(theta) * CAM.r * Math.cos(phi)
    );
    camera.lookAt(0, 1.1, 0);
  }

  /* ---- Lights ---- */
  scene.add(new THREE.AmbientLight(0x2b3a34, 1.1));
  const key = new THREE.DirectionalLight(0xdff7ee, 2.1);
  key.position.set(-8, 14, 6);
  key.castShadow = true;
  key.shadow.mapSize.set(1024, 1024);
  key.shadow.camera.near = 1; key.shadow.camera.far = 50;
  key.shadow.camera.left = -14; key.shadow.camera.right = 14;
  key.shadow.camera.top = 14; key.shadow.camera.bottom = -14;
  key.shadow.bias = -0.0007;
  scene.add(key);
  const mintFill = new THREE.PointLight(0x3adfb4, 26, 40, 2);
  mintFill.position.set(7, 6, 8);
  scene.add(mintFill);
  const coolRim = new THREE.DirectionalLight(0x1b8f6e, 0.9);
  coolRim.position.set(9, 5, -8);
  scene.add(coolRim);

  /* ---- Ground ---- */
  const ground = new THREE.Mesh(
    new THREE.CircleGeometry(24, 64),
    new THREE.MeshStandardMaterial({ color: 0x0c110f, roughness: 1, metalness: 0 })
  );
  ground.rotation.x = -Math.PI / 2;
  ground.position.y = -0.02;
  ground.receiveShadow = true;
  scene.add(ground);

  // faint grid, echoing the app's terrain feel
  const grid = new THREE.GridHelper(PLANE_W * 2.4, 24, 0x1c2a24, 0x141d19);
  grid.position.y = 0.005;
  grid.material.transparent = true;
  grid.material.opacity = 0.5;
  scene.add(grid);

  /* ---- Materials per tier ---- */
  const mat = {
    safe: new THREE.MeshStandardMaterial({ color: 0x1f7a5c, emissive: 0x2fd695, emissiveIntensity: 0.62, roughness: 0.34, metalness: 0.1 }),
    folder: new THREE.MeshStandardMaterial({ color: 0x30433b, roughness: 0.7, metalness: 0.06 }),
    file: new THREE.MeshStandardMaterial({ color: 0x2b3a44, roughness: 0.7, metalness: 0.06 }),
    protected: new THREE.MeshStandardMaterial({ color: 0x39423e, emissive: 0x000000, roughness: 0.85, metalness: 0.02 }),
  };

  /* ---- Build blocks ---- */
  const group = new THREE.Group();
  scene.add(group);
  const maxMb = Math.max(...items.map((d) => d.mb));
  const blocks = [];
  const gap = 0.12;

  rects.forEach((r, i) => {
    const w = Math.max(0.2, r.w - gap);
    const d = Math.max(0.2, r.h - gap);
    // height: sqrt scale so a 222MB tower doesn't dwarf everything
    const h = 0.5 + 3.6 * Math.sqrt(r.mb / maxMb);
    const geo = new THREE.BoxGeometry(w, h, d);
    geo.translate(0, h / 2, 0); // sit on the ground, grow up
    const m = (mat[r.tier] || mat.folder).clone();
    const mesh = new THREE.Mesh(geo, m);
    mesh.position.set(r.x + r.w / 2 - PLANE_W / 2, 0, r.y + r.h / 2 - PLANE_D / 2);
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    mesh.userData = { ...r, h, baseY: 0, targetLift: 0, lift: 0, delay: i * 0.06 };
    group.add(mesh);
    blocks.push(mesh);

    // glow slab under safe towers for a soft bloom feel
    if (r.tier === "safe") {
      const glow = new THREE.Mesh(
        new THREE.PlaneGeometry(w * 1.5, d * 1.5),
        new THREE.MeshBasicMaterial({ color: 0x2fd695, transparent: true, opacity: 0.10, depthWrite: false })
      );
      glow.rotation.x = -Math.PI / 2;
      glow.position.set(mesh.position.x, 0.02, mesh.position.z);
      group.add(glow);
    }
  });

  /* ---- Hover label ---- */
  const label = document.createElement("div");
  label.className = "sky-label";
  label.setAttribute("aria-hidden", "true");
  host.parentElement.appendChild(label);
  const raycaster = new THREE.Raycaster();
  const pointer = new THREE.Vector2();
  let hovered = null;
  let hasPointer = false;

  const mouse = { x: 0, y: 0, tx: 0, ty: 0 };
  host.addEventListener("pointermove", (e) => {
    const rect = host.getBoundingClientRect();
    const nx = (e.clientX - rect.left) / rect.width;
    const ny = (e.clientY - rect.top) / rect.height;
    mouse.tx = nx * 2 - 1;
    mouse.ty = ny * 2 - 1;
    pointer.x = mouse.tx;
    pointer.y = -(ny * 2 - 1);
    hasPointer = true;
  });
  host.addEventListener("pointerleave", () => {
    hasPointer = false;
    mouse.tx = 0; mouse.ty = 0;
    if (hovered) { hovered.userData.targetLift = 0; hovered = null; }
    label.classList.remove("show");
  });

  function updateHover() {
    if (!hasPointer) return;
    raycaster.setFromCamera(pointer, camera);
    const hits = raycaster.intersectObjects(blocks, false);
    const top = hits.length ? hits[0].object : null;
    if (top !== hovered) {
      if (hovered) hovered.userData.targetLift = 0;
      hovered = top;
      if (hovered) hovered.userData.targetLift = 0.6;
    }
    if (hovered) {
      const u = hovered.userData;
      const badge = u.tier === "safe" ? '<b class="s">↻ safe</b>'
        : u.tier === "protected" ? '<b class="p">🔒 protected</b>' : "";
      label.innerHTML =
        `<span class="p">${u.parent}/</span><span class="n">${u.label}</span>` +
        `<span class="mb">${u.mb} MB</span>${badge}`;
      // project block top to screen
      const v = new THREE.Vector3(hovered.position.x, u.h + u.lift + 0.2, hovered.position.z);
      v.applyMatrix4(group.matrixWorld);
      v.project(camera);
      const rect = host.getBoundingClientRect();
      const sx = (v.x * 0.5 + 0.5) * rect.width;
      const sy = (-v.y * 0.5 + 0.5) * rect.height;
      label.style.transform = `translate(-50%, -120%) translate(${sx}px, ${sy}px)`;
      label.classList.add("show");
    } else {
      label.classList.remove("show");
    }
  }

  /* ---- Sizing ---- */
  function resize() {
    const w = host.clientWidth || host.parentElement.clientWidth;
    const h = host.clientHeight || Math.round(w * 0.72);
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  }
  resize();
  window.addEventListener("resize", resize);

  /* ---- Animation ---- */
  let running = true;
  const io = new IntersectionObserver((es) => {
    running = es[0].isIntersecting;
    if (running && !reduceMotion) tick();
  }, { threshold: 0.02 });
  io.observe(host);

  const clock = new THREE.Clock();
  let intro = 0;
  let spin = 0;

  function frame() {
    const dt = Math.min(clock.getDelta(), 0.05);
    intro = Math.min(1, intro + dt / 1.1);

    // mouse parallax easing
    mouse.x += (mouse.tx - mouse.x) * Math.min(1, dt * 4);
    mouse.y += (mouse.ty - mouse.y) * Math.min(1, dt * 4);
    placeCamera(mouse.x, mouse.y);

    // slow auto-orbit, paused a touch while pointer is active
    spin += dt * (hasPointer ? 0.04 : 0.11);
    group.rotation.y = spin;

    // block intro rise + hover lift
    blocks.forEach((b) => {
      const u = b.userData;
      const local = Math.max(0, Math.min(1, (intro - u.delay) / (1 - u.delay || 1)));
      const e = 1 - Math.pow(1 - local, 3); // easeOutCubic
      u.lift += (u.targetLift - u.lift) * Math.min(1, dt * 8);
      b.scale.y = Math.max(0.001, e);
      b.position.y = u.lift;
      // pulse the emissive of safe towers subtly
      if (u.tier === "safe") {
        b.material.emissiveIntensity = 0.55 + Math.sin(clock.elapsedTime * 1.4 + u.delay * 8) * 0.08 + u.lift * 0.4;
      }
    });

    updateHover();
    renderer.render(scene, camera);
  }

  function tick() {
    if (!running || reduceMotion) return;
    frame();
    requestAnimationFrame(tick);
  }

  // reveal the canvas, then run
  host.classList.add("ready");
  if (reduceMotion) {
    intro = 1;
    blocks.forEach((b) => { b.scale.y = 1; });
    placeCamera(0, 0);
    resize();
    renderer.render(scene, camera);
  } else {
    tick();
  }
}

/* ---- Squarified treemap (Bruls, Huizing, van Wijk) ---- */
function squarify(data, x, y, w, h) {
  const total = data.reduce((s, d) => s + d.mb, 0);
  const scale = (w * h) / total;
  const nodes = data.map((d) => ({ ...d, area: d.mb * scale }));
  const rects = [];
  let rx = x, ry = y, rw = w, rh = h;
  let row = [];

  const worst = (row, len) => {
    if (!row.length) return Infinity;
    const s = row.reduce((a, r) => a + r.area, 0);
    const mx = Math.max(...row.map((r) => r.area));
    const mn = Math.min(...row.map((r) => r.area));
    const s2 = s * s, l2 = len * len;
    return Math.max((l2 * mx) / s2, s2 / (l2 * mn));
  };

  let i = 0;
  while (i < nodes.length) {
    const shortest = Math.min(rw, rh);
    const next = nodes[i];
    if (row.length === 0 || worst([...row, next], shortest) <= worst(row, shortest)) {
      row.push(next); i++;
    } else { layoutRow(row); row = []; }
  }
  if (row.length) layoutRow(row);
  return rects;

  function layoutRow(row) {
    const s = row.reduce((a, r) => a + r.area, 0);
    if (rw >= rh) {
      const rowW = s / rh;
      let oy = ry;
      row.forEach((r) => { const rectH = r.area / rowW; rects.push({ ...r, x: rx, y: oy, w: rowW, h: rectH }); oy += rectH; });
      rx += rowW; rw -= rowW;
    } else {
      const rowH = s / rw;
      let ox = rx;
      row.forEach((r) => { const rectW = r.area / rowH; rects.push({ ...r, x: ox, y: ry, w: rectW, h: rowH }); ox += rectW; });
      ry += rowH; rh -= rowH;
    }
  }
}
